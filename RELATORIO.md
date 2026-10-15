# Relatório Técnico: Firewall Linux com Netfilter/iptables em Docker Compose

| | |
|---|---|
| **Disciplina** | Segurança da Informação, 2026/2 |
| **Professor** | Roitier Campos Gonçalves |
| **Curso** | Sistemas de Informação, IF Goiano, campus Ceres |
| **Aluno** | Giovana Lyssa Galdino Ribeiro |
| **Data de entrega** | 15/10/2026 |
| **Repositório** | https://github.com/GioLyss/lab-firewall-hotel.git |
| **Ambiente de execução** | Windows 11 com Docker Desktop, versão 4.95.0 |

**Sumário:** 1. Definição do Case · 2. Diagnóstico: Cenário Atual vs. Proposta de Solução · 3. Matriz de Regras de Segurança (Firewall) · 4. Metodologia de Testes e Validação · Apêndice A (estrutura do repositório) · Apêndice B (referências)

---

## 1. Definição do Case

### 1.1 A empresa

O **Hotel Vida Boa** é um hotel de pequeno porte. A **recepção** atende os hóspedes, faz check-in e check-out e lança os consumos no **PMS** (sistema de gestão do hotel), e os **hóspedes** usam um **portal de reservas** pela Internet para reservar e consultar a hospedagem. Essa é uma situação comum em hotéis e pousadas pequenos, que guardam dados pessoais e financeiros dos hóspedes em sistemas ligados à mesma rede.

### 1.2 Contexto de negócio

- O portal é a porta de entrada dos hóspedes. Se ele fica fora do ar, o hotel deixa de receber reservas.
- O PMS reúne o cadastro dos hóspedes (nome e telefone), as reservas e as contas de consumo. Deve ser lido apenas pela equipe da recepção, que precisa dele para atender. A Lei Geral de Proteção de Dados (Lei 13.709/2018) exige medidas técnicas de segurança (art. 46) e se apoia nos princípios da necessidade (art. 6º, III) e da segurança (art. 6º, VII).
- Há **dois perfis de acesso** com necessidades diferentes sobre a mesma infraestrutura: o **hóspede** (perfil usuário) e a **recepção**. O conflito entre eles é o centro do projeto: o hóspede precisa do portal, mas nunca do PMS, que guarda os dados de todos os hóspedes; a recepção precisa dos dois.
- A equipe é pequena e não tem especialista em segurança. A solução precisa ser simples de manter, reproduzível e baseada em software livre.

### 1.3 Perfis de acesso

| Perfil | Onde está | Portal (80, 443) | PMS (8443) | Banco (5432) |
|---|---|---|---|---|
| Hóspede (usuário) | Rede externa, `10.66.3.0/24` | Sim: reserva e consulta a hospedagem | **Não** | Não |
| Recepção | LAN interna, `10.66.1.0/24` | Sim: confere as reservas do dia | **Sim**: faz check-in e lança consumos | Não |

Nenhum dos dois perfis fala com o banco: quem consulta o banco é a aplicação, de dentro da DMZ.

### 1.4 Serviços que precisam operar

| Serviço | Zona e container | Quem acessa | Porta |
|---|---|---|---|
| Portal de reservas (Nginx) | DMZ, `dmz-web` | Hóspede e recepção | TCP 80 (HTTP) e 443 (HTTPS) |
| API do PMS (Nginx) | DMZ, `dmz-pms` | Somente a recepção | TCP 8443 (HTTPS) |
| Banco de dados (PostgreSQL) | DMZ, `dmz-db` | Somente a aplicação, dentro da DMZ | TCP 5432 |
| Estação da recepção | LAN, `recepcao` | Usa o portal e o PMS | não oferece serviço |
| Hóspede | Rede externa, `hospede` | Usa o portal | não oferece serviço |
| Firewall (Linux, iptables) | Entre as três redes, `firewall` | Ninguém: não expõe serviço | nenhuma |

### 1.5 Escopo e simplificações do laboratório

- O portal é uma página estática, o PMS é uma API simulada que devolve um JSON de exemplo e o banco é um PostgreSQL com dados fictícios. Os três representam as camadas de aplicação e de dados para efeito de filtragem; nenhuma aplicação consulta o banco.
- O perfil é decidido pela **rede de origem**: a rede externa representa a Internet (hóspedes) e a LAN representa a rede interna do hotel (recepção). O login de cada recepcionista dentro do PMS é papel da aplicação e está fora do escopo: o firewall é uma camada de defesa, não a única.
- O hóspede e a recepção são containers Alpine com `curl` e `nmap`. O HTTPS usa certificado autoassinado, só para o laboratório.
- Tudo roda em containers de um único computador. As "redes" são redes bridge do Docker, e a rede externa não usa NAT.

---

## 2. Diagnóstico: Cenário Atual vs. Proposta de Solução

### 2.1 Cenário Atual (Problemas Mapeados)

Hoje o portal, o PMS, o banco de dados e as estações estão na **mesma rede plana**, sem nenhum filtro entre eles. Quem consegue chegar a essa rede, inclusive o hóspede, alcança todos os serviços. O commit "Cenario atual" do histórico do repositório reproduz essa situação. Nele, o `acesso` do hóspede mostra tudo aberto, e o PMS (dados de todos os hóspedes) é lido sem nenhuma barreira:

~~~text
Perfil: hospede
  portal      dmz-web:80           ABERTO
  pms         dmz-pms:8443         ABERTO
  banco       dmz-db:5432          ABERTO
~~~

~~~text
{"sistema":"pms","reserva":1,"quarto":"101","hospede":"Hospede Exemplo 1","consumo":"Frigobar","observacao":"dados ficticios"}
~~~

| # | Problema mapeado | Risco | Consequência para o negócio |
|---|---|---|---|
| P1 | Rede plana: portal, PMS, banco e estações juntos | Qualquer máquina alcança qualquer serviço | Uma estação ou um servidor comprometido chega a tudo |
| P2 | Nenhuma separação entre os perfis: o hóspede alcança o PMS | Leitura de dados pessoais e de consumo de outros hóspedes por quem não deveria | Quebra de sigilo, sanções da LGPD, perda de confiança dos hóspedes |
| P3 | Banco acessível pela rede (porta 5432) | Consulta ou extração indevida de todos os dados | Vazamento em massa de dados pessoais |
| P4 | Nenhum filtro entre servidores e estações | Quem invade um servidor da DMZ avança para as estações (movimento lateral) | Comprometimento em cadeia |
| P5 | Política "libera tudo": serviços esquecidos ficam expostos | Superfície de ataque grande e desconhecida | Exploração de serviços que ninguém sabia que estavam abertos |
| P6 | Nenhuma visibilidade: nada conta nem registra tentativas bloqueadas | Varreduras e ataques passam despercebidos | Detecção tardia de incidentes |
| P7 | Origem forjada é aceita: o hóspede pode se passar pela estação da recepção | Falsa identidade para herdar o acesso da recepção | Acesso indevido ao PMS |

### 2.2 Proposta de Solução (justificativa da arquitetura)

A proposta é separar o ambiente em **três zonas**, cada uma em sua própria rede: a **rede externa** (hóspedes), a **LAN** (recepcionistas) e a **DMZ** (portal, PMS e banco), com um **firewall Linux com iptables** como único caminho entre elas. Todo pacote que vai de uma zona a outra passa pelo firewall, que só deixa passar o que cada perfil precisa.

~~~text
                              DMZ 10.66.2.0/24
                  +--------------------------------------------+
                  | dmz-web   10.66.2.10  (80, 443)            |
                  | dmz-pms   10.66.2.12  (8443)               |
                  | dmz-db    10.66.2.11  (5432)               |
                  +----------------------+---------------------+
                                         | .254
EXTERNA 10.66.3.0/24              +------+-------+              LAN 10.66.1.0/24
+--------------------+  .254      |   firewall   |      .254    +---------------------+
| hospede 10.66.3.10 |------------|  iptables /  |--------------| recepcao 10.66.1.10 |
+--------------------+            |  Netfilter   |              +---------------------+
                                  +--------------+
~~~

| Container | Zona | Endereço | Observação |
|---|---|---|---|
| `hospede` | Externa | 10.66.3.10 | Gateway padrão: 10.66.3.254 (firewall) |
| `recepcao` | LAN | 10.66.1.10 | Gateway padrão: 10.66.1.254 (firewall) |
| `firewall` | Externa, LAN e DMZ | 10.66.3.254, 10.66.1.254 e 10.66.2.254 | `ip_forward=1`, política DROP |
| `dmz-web` | DMZ | 10.66.2.10 | Gateway padrão: 10.66.2.254 (firewall) |
| `dmz-pms` | DMZ | 10.66.2.12 | Gateway padrão: 10.66.2.254 (firewall) |
| `dmz-db` | DMZ | 10.66.2.11 | Gateway padrão: 10.66.2.254 (firewall) |

**Por que esta solução responde aos problemas**

1. **Segmentação em zonas, uma por perfil (P1, P2, P4).** Hóspede e recepção ficam em redes diferentes, e o único caminho entre elas e os servidores é o firewall. O perfil de quem acessa é definido pela zona de onde o pacote vem.
2. **Menor privilégio com política DROP (P2, P3, P5).** Nada atravessa o firewall sem uma regra explícita. O hóspede recebe só o portal; a recepção recebe o portal e o PMS; o banco não é alcançável por nenhuma estação.
3. **Regras presas à interface de entrada, não só ao IP (P7).** A liberação do PMS exige o pacote entrar pela interface da LAN. Se o hóspede trocar o IP de origem para o da recepção, o pacote continua entrando pela interface da rede externa e não casa com a regra; além disso, a F02 descarta qualquer pacote que chegue pela rede externa com origem de outra rede.
4. **Firewall com estado (stateful).** Libera-se a conexão no sentido de ida e a resposta volta pelo estado `ESTABLISHED`, sem abrir portas no sentido contrário.
5. **Regra de ouro da DMZ (P4).** A DMZ nunca inicia conexão para as redes internas. Se o portal for invadido, o invasor não consegue atacar as estações a partir dele.
6. **Descarte de pacotes inválidos e de origem forjada (P7).** Pacotes fora de estado e pacotes com origem incompatível com a interface de entrada são descartados antes de qualquer regra de liberação.
7. **Contadores por regra (P6).** Cada regra tem um identificador e um contador de pacotes. Isso permite provar qual regra tratou cada teste e notar tentativas bloqueadas. Registro em log ficou como melhoria (seção 2.4).
8. **Ambiente reproduzível.** O Docker Compose sobe o mesmo ambiente com um comando, e as regras são carregadas sozinhas quando o firewall inicia. Isso facilita a avaliação e a manutenção por uma equipe pequena.

### 2.3 Decisões de projeto

- **iptables com backend nf_tables.** É a ferramenta estudada na disciplina, e o pacote `iptables` do Alpine usa o backend nf_tables. Se o kernel não tiver nf_tables, o `entrypoint.sh` troca sozinho para o `iptables-legacy`. As mesmas regras poderiam ser escritas em nftables.
- **Política DROP em INPUT e FORWARD; OUTPUT em ACCEPT.** O firewall não inicia tráfego e não há o que restringir na saída neste laboratório. INPUT protege o próprio firewall; FORWARD controla o que atravessa.
- **DROP em vez de REJECT.** O DROP não responde nada, então quem varre a rede não descobre se a porta existe ou está filtrada. O custo é que um usuário legítimo que erra a porta espera o tempo limite.
- **Interfaces descobertas pelo IP.** A ordem `eth0`, `eth1` e `eth2` dentro do container não é garantida pelo Docker e chegou a mudar entre duas subidas do mesmo laboratório; o script procura a interface que tem o IP de cada zona.
- **Perfil por rede, não por IP.** Recepção e hóspede ficam em redes diferentes e as regras dos perfis usam `-i` (interface de entrada) junto com a sub-rede. Decidir só pelo IP de origem deixaria um hóspede se passar pela recepção.
- **Firewall como gateway padrão de todos.** Cada container aponta a rota padrão para o IP do firewall na sua rede. Assim todo tráfego entre zonas passa por ele.
- **Redes bridge no modo `routed`, sem `internal: true`.** Nos testes, o Docker descartava no próprio host (antes do firewall) o tráfego que o firewall deveria encaminhar entre redes: em redes `internal`, regras do Docker barram pacotes cujo destino está fora da sub-rede da ponte. O modo `routed` não usa NAT e deixa o firewall rotear. O isolamento entre as redes continua: sem o firewall, as zonas não se alcançam (controle 2 da seção 4.7).
- **Uma imagem Nginx, duas configurações.** O portal e o PMS usam a mesma imagem (`dmz-web`); o PMS monta o próprio `nginx.conf` por volume e escuta só na porta 8443.
- **Regras carregadas pelo `entrypoint.sh`.** Atende ao requisito de carregar o firewall na subida do container. O arquivo `rules.sh` é montado como volume, então pode ser editado sem reconstruir a imagem.
- **Healthchecks e `depends_on`.** A recepção e o hóspede só sobem depois que o firewall e os três servidores estão prontos, e os testes podem ser executados logo após o `docker compose up -d`.

### 2.4 Limitações e melhorias possíveis

- **O firewall separa redes, não pessoas.** Dentro do PMS, cada recepcionista precisa de login próprio e de registro de acesso (auditoria). O firewall é uma camada; a aplicação é outra.
- **Portal, PMS e banco compartilham a DMZ.** O tráfego dos servidores para o banco acontece dentro da mesma rede e não passa pelo firewall. Melhoria: uma rede de dados só para o banco, com regra explícita para a porta 5432.
- **Internet e acesso remoto.** A rede externa do laboratório representa a Internet sem NAT. Em produção, o portal ficaria atrás de NAT e de um proxy reverso ou WAF, e recepcionistas fora do hotel entrariam por VPN.
- **Containers com `NET_ADMIN`.** Necessário para configurar rotas e iptables dentro do laboratório. Em produção, as rotas viriam da infraestrutura e as máquinas não teriam essa permissão.
- **Janela de milissegundos na subida.** O Compose liga o encaminhamento (`ip_forward=1`) quando cria o container, um instante antes de o `entrypoint.sh` carregar as regras. Em produção, o encaminhamento só seria ligado depois das regras.
- **Sem IPv6.** As redes do laboratório não têm IPv6; em produção seriam necessárias regras equivalentes.
- **Sem registro em log.** A evidência são os contadores. O alvo `LOG` pode ser acrescentado, mas dentro de containers só aparece no log do host se `net.netfilter.nf_log_all_netns` estiver ligado.
- **Sem proteção de aplicação.** Um firewall de rede não detecta ataques na camada de aplicação (por exemplo, injeção de SQL).
- **HTTPS com certificado autoassinado,** apenas para o laboratório.

---

## 3. Matriz de Regras de Segurança (Firewall)

A política padrão é **DROP** em `INPUT` e `FORWARD`. As regras são avaliadas de cima para baixo, na ordem das tabelas, e a primeira que combina decide. O mesmo identificador aparece no script `firewall/rules.sh` e nos contadores do `iptables`.

### 3.1 Cadeia FORWARD (tráfego que atravessa o firewall)

| ID | Origem | Destino | Porta/Protocolo | Ação (ACCEPT/DROP) | Justificativa do Negócio |
|---|---|---|---|---|---|
| F01 | Qualquer | Qualquer | Pacotes em estado `INVALID` | DROP | Pacotes que não pertencem a nenhuma conexão válida são lixo ou tentativa de ataque; descartá-los não afeta nenhum usuário legítimo. |
| F02 | Entrada pela rede externa com origem fora de 10.66.3.0/24 | Qualquer | Qualquer | DROP | Impede que o hóspede (ou um invasor) se passe pela estação da recepção ou por outro servidor usando um IP de outra rede. |
| F03 | Entrada pela LAN com origem fora de 10.66.1.0/24 | Qualquer | Qualquer | DROP | Impede que uma estação da LAN comprometida forje a origem para ganhar confiança ou despistar rastros. |
| F04 | Qualquer | Qualquer | Estados `ESTABLISHED` e `RELATED` | ACCEPT | Deixa voltar a resposta de conexões já autorizadas: hóspede e recepção recebem as páginas sem que se abram portas no sentido contrário. |
| F05 | Hóspede (rede externa, 10.66.3.0/24) | Portal (10.66.2.10) | TCP 80 e 443, conexão nova (SYN) | ACCEPT | O hóspede reserva e consulta a hospedagem pelo portal; o HTTPS protege os dados em trânsito. |
| F06 | Recepção (LAN, 10.66.1.0/24) | Portal (10.66.2.10) | TCP 80 e 443, conexão nova (SYN) | ACCEPT | A recepção confere as reservas do dia pelo portal. |
| F07 | Recepção (LAN, 10.66.1.0/24) | PMS (10.66.2.12) | TCP 8443, conexão nova (SYN) | ACCEPT | Só a recepção precisa do PMS para fazer check-in, check-out e lançar consumos (princípio da necessidade). |
| F08 | Hóspede (rede externa) | PMS (10.66.2.12) | Qualquer | DROP | O PMS tem dados pessoais e de consumo de todos os hóspedes, protegidos pela LGPD: o hóspede não precisa dele, e o contador mostra tentativas. |
| F09 | Hóspede e recepção (redes externa e LAN) | Banco (10.66.2.11) | Qualquer | DROP | O banco guarda todos os dados do hotel: só a aplicação, dentro da DMZ, fala com ele. Nenhuma estação o usa diretamente. |
| F10 | Rede externa | LAN | Qualquer | DROP | O hóspede nunca alcança as estações do hotel. |
| F11 | LAN | Rede externa | Qualquer | DROP | A estação da recepção não inicia conexões para a rede externa (controle de saída): reduz o risco de exfiltração e de acesso indevido. |
| F12 | DMZ | Redes internas (LAN e externa) | Qualquer, conexão nova | DROP | Regra de ouro da DMZ: se o portal ou o PMS forem invadidos, o invasor não inicia conexões contra as estações. |
| F99 | Qualquer | Qualquer | Qualquer | DROP | Política padrão: o que não foi liberado de forma explícita é negado, e o contador mostra as tentativas bloqueadas. |

### 3.2 Cadeia INPUT (tráfego destinado ao próprio firewall)

| ID | Origem | Destino | Porta/Protocolo | Ação (ACCEPT/DROP) | Justificativa do Negócio |
|---|---|---|---|---|---|
| I01 | Loopback (`lo`) | Firewall | Qualquer | ACCEPT | Comunicação interna do próprio firewall. |
| I02 | Qualquer | Firewall | Estado `INVALID` | DROP | Mesmo motivo da F01, agora para o tráfego dirigido ao firewall. |
| I03 | Qualquer | Firewall | Estados `ESTABLISHED` e `RELATED` | ACCEPT | Respostas ao tráfego que o próprio firewall iniciou. |
| I99 | Qualquer | Firewall | Qualquer | DROP | O firewall não oferece serviço nenhum: fica invisível para todas as redes, o que reduz a superfície de ataque. |

### 3.3 Cadeia OUTPUT

A política é **ACCEPT**. O firewall não inicia tráfego e, no laboratório, não há o que restringir na saída.

### 3.4 Fluxos que a matriz resume

| Fluxo | Resultado | Regra |
|---|---|---|
| Hóspede para o portal, HTTP (80) ou HTTPS (443) | Permitido | F05 (ida) e F04 (volta) |
| Hóspede para o PMS (qualquer porta) | Bloqueado | F08 |
| Hóspede para o banco | Bloqueado | F09 |
| Hóspede para a LAN | Bloqueado | F10 |
| Hóspede com IP de origem forjado (o da recepção) | Bloqueado | F02 |
| Recepção para o portal, HTTP ou HTTPS | Permitido | F06 (ida) e F04 (volta) |
| Recepção para o PMS, porta 8443 | Permitido | F07 (ida) e F04 (volta) |
| Recepção para o PMS em outra porta | Bloqueado | F99 |
| Recepção para o banco | Bloqueado | F09 |
| Recepção para a rede externa | Bloqueado | F11 |
| Qualquer estação para o firewall | Bloqueado | I99 |
| DMZ para a LAN ou a rede externa, conexão nova | Bloqueado | F12 |
| Portal ou PMS para o banco | Não passa pelo firewall (mesma rede DMZ) | não se aplica (ver seção 2.4) |

---

## 4. Metodologia de Testes e Validação

Esta seção é o passo a passo para quem for avaliar. Os testes são de dois tipos: **positivos** (o que cada perfil precisa deve funcionar) e **negativos** (o que não deve ser permitido tem de ser bloqueado). A mesma bateria roda nos dois perfis e o resultado esperado para o PMS é o contrário: a recepção alcança, o hóspede não.

### 4.1 Preparação

Requisitos: Docker Desktop (ou Docker Engine) com Compose v2, aberto e em execução, e Git.

~~~bash
git clone https://github.com/GioLyss/lab-firewall-hotel.git
cd lab-firewall-hotel
docker compose up -d
docker compose ps
~~~

A primeira execução baixa as imagens-base e constrói as imagens do laboratório, o que leva alguns minutos. Resultado esperado: `firewall`, `dmz-web`, `dmz-pms` e `dmz-db` como `healthy`, e `recepcao` e `hospede` como `Up`.

~~~text
NAME                 IMAGE                                                                     COMMAND                                                                                             SERVICE    CREATED              STATUS                        PORTS
fwhotel-dmz-db-1     postgres:16-alpine                                                        "/bin/sh -c 'ip route replace default via \"$GATEWAY_IP\" && exec docker-entrypoint.sh postgres'"   dmz-db     7 hours ago          Up 7 hours (healthy)          5432/tcp
fwhotel-dmz-pms-1    sha256:3a2ad24eaeab8dcdc3a3122cf61a236bfe2a0a6440bffb8af519da38c35da7fd   "/docker-entrypoint.sh nginx -g 'daemon off;'"                                                      dmz-pms    About a minute ago   Up About a minute (healthy)   80/tcp
fwhotel-dmz-web-1    sha256:a94c6c7c50356b48e20f0377c59dc85794c189e857f852f2bd7fe590fa831a3c   "/docker-entrypoint.sh nginx -g 'daemon off;'"                                                      dmz-web    About a minute ago   Up About a minute (healthy)   80/tcp
fwhotel-firewall-1   sha256:5d6905526b49b8ec197af8dc5abf5755f548f15906562e5cc4880dcf708c1cd1   "/usr/local/bin/entrypoint.sh"                                                                      firewall   About a minute ago   Up About a minute (healthy)
fwhotel-hospede-1    sha256:d91e30256bf9f0f7dd99051c10a6826d9a0a28ab228892382364606786aba149   "/usr/local/bin/entrypoint.sh"                                                                      hospede    About an hour ago    Up 50 minutes
fwhotel-recepcao-1   sha256:20bb40ca2349a6c67d8b51943439214b7d405f96973ea23aa538bd1f56dd0776   "/usr/local/bin/entrypoint.sh"                                                                      recepcao   About an hour ago    Up About an hour
~~~

Para conferir que o firewall encaminha pacotes e que as regras foram carregadas na subida:

~~~bash
docker compose exec -T firewall sysctl net.ipv4.ip_forward
~~~

~~~text
net.ipv4.ip_forward = 1
~~~

~~~bash
docker compose exec -T firewall iptables -L FORWARD -n --line-numbers
~~~

~~~text
Chain FORWARD (policy DROP)
num  target     prot opt source               destination
1    DROP       all  --  0.0.0.0/0            0.0.0.0/0            ctstate INVALID /* F01 descarta invalidos */
2    DROP       all  -- !10.66.3.0/24         0.0.0.0/0            /* F02 anti-spoofing da rede externa */
3    DROP       all  -- !10.66.1.0/24         0.0.0.0/0            /* F03 anti-spoofing da LAN */
4    ACCEPT     all  --  0.0.0.0/0            0.0.0.0/0            ctstate RELATED,ESTABLISHED /* F04 retorno de conexoes autorizadas */
5    ACCEPT     tcp  --  10.66.3.0/24         10.66.2.10           tcp flags:0x17/0x02 multiport dports 80,443 ctstate NEW /* F05 Hospede para portal HTTP e HTTPS */
6    ACCEPT     tcp  --  10.66.1.0/24         10.66.2.10           tcp flags:0x17/0x02 multiport dports 80,443 ctstate NEW /* F06 Recepcao para portal HTTP e HTTPS */
7    ACCEPT     tcp  --  10.66.1.0/24         10.66.2.12           tcp dpt:8443 flags:0x17/0x02 ctstate NEW /* F07 Recepcao para PMS HTTPS */
8    DROP       all  --  0.0.0.0/0            10.66.2.12           /* F08 Hospede para PMS bloqueado */
9    DROP       all  --  0.0.0.0/0            10.66.2.11           /* F09 Hospede e recepcao para banco bloqueado */
10   DROP       all  --  0.0.0.0/0            0.0.0.0/0            /* F10 Externa para LAN bloqueado */
11   DROP       all  --  0.0.0.0/0            0.0.0.0/0            /* F11 LAN para externa bloqueado */
12   DROP       all  --  0.0.0.0/0            0.0.0.0/0            ctstate NEW /* F12 DMZ nao inicia conexao para as redes internas */
13   DROP       all  --  0.0.0.0/0            0.0.0.0/0            /* F99 nega o resto */
~~~

### 4.2 Mapa de acesso de cada perfil

O comando `acesso` testa, de dentro de cada container, o portal, o PMS e o banco, e mostra `ABERTO` (o servidor respondeu) ou `FILTRADO` (ninguém respondeu: o firewall descartou o pacote). É o resumo da política em seis linhas.

~~~bash
docker compose exec -T recepcao acesso
docker compose exec -T hospede acesso
~~~

~~~text
Perfil: recepcao
  portal      dmz-web:80           ABERTO
  pms         dmz-pms:8443         ABERTO
  banco       dmz-db:5432          FILTRADO
Perfil: hospede
  portal      dmz-web:80           ABERTO
  pms         dmz-pms:8443         FILTRADO
  banco       dmz-db:5432          FILTRADO
~~~

### 4.3 Testes positivos (devem funcionar)

Os identificadores são os mesmos do comando `testar` (seção 4.5). Nos comandos de `P1` e `P2`, troque `hospede` por `recepcao` para testar o outro perfil.

| ID | O que testa | Comando manual | Resultado esperado | Regra |
|---|---|---|---|---|
| P1 | O portal responde por HTTP (hóspede e recepção) | `docker compose exec -T hospede curl -sS -m 5 http://dmz-web/` | HTML da página "Hotel Vida Boa" (o `testar` confere também o texto "Portal de reservas", teste P3) | F05 (hóspede), F06 (recepção) |
| P2 | O portal responde por HTTPS (hóspede e recepção) | `docker compose exec -T hospede curl -sSk -m 5 https://dmz-web/` | A mesma página (`-k` aceita o certificado autoassinado) | F05 (hóspede), F06 (recepção) |
| P4 | **A recepção lê o PMS** | `docker compose exec -T recepcao curl -sSk -m 5 https://dmz-pms:8443/api/reservas/1` | JSON do PMS da reserva 1 (quarto 101) | F07 |
| D3 | O portal alcança o banco, dentro da DMZ | `docker compose exec -T dmz-web curl -sS -m 3 http://dmz-db:5432/` | `curl: (52) Empty reply from server`: o PostgreSQL atendeu e fechou a conexão, pois não fala HTTP. Prova que o banco está de pé e acessível aos servidores | nenhuma (mesma rede, não passa pelo firewall) |

~~~text
{"sistema":"pms","reserva":1,"quarto":"101","hospede":"Hospede 1","consumo":"Frigobar","observacao":"dados ficticios"}
~~~

### 4.4 Testes negativos (devem ser bloqueados)

Um pacote descartado por DROP não recebe resposta nenhuma, então o resultado esperado é **tempo esgotado** (`curl: (28) Connection timed out`), e não "conexão recusada" (código 7), que indicaria uma porta fechada sem firewall.

| ID | O que testa | Comando manual | Resultado esperado | Regra |
|---|---|---|---|---|
| P4 | **O hóspede não lê o PMS** | `docker compose exec -T hospede curl -sSk -m 5 https://dmz-pms:8443/api/reservas/1` | Tempo esgotado (código 28) | F08 |
| N1 | A recepção não usa o PMS em outra porta | `docker compose exec -T recepcao curl -sS -m 3 http://dmz-pms:80/` | Tempo esgotado | F99 |
| N2 | O hóspede não alcança o banco | `docker compose exec -T hospede curl -sS -m 3 http://dmz-db:5432/` | Tempo esgotado | F09 |
| N2 | A recepção não alcança o banco | `docker compose exec -T recepcao curl -sS -m 3 http://dmz-db:5432/` | Tempo esgotado | F09 |
| N3 | Ninguém faz ping no banco | `docker compose exec -T hospede ping -c 2 -W 2 dmz-db` | 100% de perda | F09 |
| N4 | O hóspede não alcança a estação da recepção | `docker compose exec -T hospede ping -c 2 -W 2 10.66.1.10` | 100% de perda | F10 |
| N5 | O hóspede não acessa SSH no portal | `docker compose exec -T hospede curl -sS -m 3 http://dmz-web:22/` | Tempo esgotado | F99 |
| N6 | O firewall não atende o hóspede | `docker compose exec -T hospede curl -sS -m 3 http://10.66.3.254/` | Tempo esgotado | I99 |
| N7 | O firewall não responde a ping | `docker compose exec -T hospede ping -c 2 -W 2 10.66.3.254` | 100% de perda | I99 |
| N8 | **O hóspede não se passa pela recepção (IP forjado)** | automático (`testar`) ou a demonstração da seção 4.7 | Tempo esgotado; a prova é o contador da F02 (na recepção, a F03) | F02 |
| N9 | Varredura do PMS | `docker compose exec -T hospede varredura` | Hóspede: todas as portas `filtered`. Recepção: só a 8443 `open` | F08 (hóspede); F07 e F99 (recepção) |
| N10 | Varredura (`nmap`) do banco, a partir do cliente | `docker compose exec -T recepcao nmap -Pn -n -p 5432 dmz-db` (no hóspede, troque `recepcao` por `hospede`) | `5432/tcp filtered postgresql`: nenhuma porta aberta, para os dois perfis (o `varredura` repete a varredura nos três servidores) | F09 |
| D4 | A DMZ não inicia conexão para a LAN | `docker compose exec -T dmz-web curl -sS -m 3 http://10.66.1.10/` | Tempo esgotado | F12 |
| D5 | A DMZ não inicia conexão para a rede externa | `docker compose exec -T dmz-web curl -sS -m 3 http://10.66.3.10/` | Tempo esgotado | F12 |
| D6 | A DMZ não faz ping na LAN | `docker compose exec -T dmz-web ping -c 2 -W 2 10.66.1.10` | 100% de perda | F12 |
| D7 | O firewall não atende a DMZ | `docker compose exec -T dmz-web curl -sS -m 3 http://10.66.2.254/` | Tempo esgotado | I99 |

~~~text
curl: (28) Connection timed out after 5003 milliseconds
~~~

### 4.5 Testes automatizados

Os mesmos casos, com veredito de aprovado ou reprovado, rodam com um comando em cada zona. O código de saída é 0 quando tudo passa. O roteiro é o mesmo nos dois perfis: o que muda é a expectativa do teste P4 (a recepção lê o PMS; o hóspede não) e a regra que cada teste exercita.

~~~bash
docker compose exec -T recepcao testar
docker compose exec -T hospede testar
docker compose exec -T dmz-web testar
docker compose exec -T hospede varredura
docker compose exec -T recepcao varredura
~~~

~~~text
=== Testes a partir da zona: recepcao ===
(cada teste de bloqueio espera 3 s por uma resposta que nao vem; o conjunto leva menos de 1 minuto)

--- Preparacao
[PASSOU] gateway padrao da zona e o firewall (10.66.1.254)

--- Portal: permitido para os dois perfis
[PASSOU] P1 portal HTTP (dmz-web:80)                        [F06]
[PASSOU] P2 portal HTTPS (dmz-web:443)                      [F06]
[PASSOU] P3 pagina do portal carregada (Portal de reservas) [F06]

--- PMS: o teste que separa os perfis
[PASSOU] P4 recepcao le o PMS (dmz-pms:8443)                [F07]

--- Acessos bloqueados (devem ficar sem resposta)
[PASSOU] N1 PMS em outra porta (:80)                        [F99]
[PASSOU] N2 banco de dados (dmz-db:5432)                    [F09]
[PASSOU] N3 ping no banco (dmz-db)                          [F09]
[PASSOU] N4 ping na estacao da outra zona                   [F11]
[PASSOU] N5 SSH no portal (dmz-web:22)                      [F99]
[PASSOU] N6 firewall nao atende na porta 80                 [I99]
[PASSOU] N7 firewall nao responde a ping                    [I99]
[PASSOU] N8 origem forjada (IP da outra zona) descartada    [F03]
[PASSOU] N9 nmap no PMS: so a 8443 aberta                   [F07 F99]
[PASSOU] N10 nmap no banco: nenhuma porta aberta            [F09]

=== Resumo (recepcao): 15 passaram, 0 falharam ===
Contadores das regras: docker compose exec -T firewall iptables -L FORWARD -n -v --line-numbers
~~~

~~~text
=== Testes a partir da zona: hospede ===
(cada teste de bloqueio espera 3 s por uma resposta que nao vem; o conjunto leva menos de 1 minuto)

--- Preparacao
[PASSOU] gateway padrao da zona e o firewall (10.66.3.254)

--- Portal: permitido para os dois perfis
[PASSOU] P1 portal HTTP (dmz-web:80)                        [F05]
[PASSOU] P2 portal HTTPS (dmz-web:443)                      [F05]
[PASSOU] P3 pagina do portal carregada (Portal de reservas) [F05]

--- PMS: o teste que separa os perfis
[PASSOU] P4 hospede NAO alcanca o PMS (:8443)               [F08]

--- Acessos bloqueados (devem ficar sem resposta)
[PASSOU] N1 PMS em outra porta (:80)                        [F08]
[PASSOU] N2 banco de dados (dmz-db:5432)                    [F09]
[PASSOU] N3 ping no banco (dmz-db)                          [F09]
[PASSOU] N4 ping na estacao da outra zona                   [F10]
[PASSOU] N5 SSH no portal (dmz-web:22)                      [F99]
[PASSOU] N6 firewall nao atende na porta 80                 [I99]
[PASSOU] N7 firewall nao responde a ping                    [I99]
[PASSOU] N8 origem forjada (IP da outra zona) descartada    [F02]
[PASSOU] N9 nmap no PMS: nenhuma porta aberta               [F08]
[PASSOU] N10 nmap no banco: nenhuma porta aberta            [F09]

=== Resumo (hospede): 15 passaram, 0 falharam ===
Contadores das regras: docker compose exec -T firewall iptables -L FORWARD -n -v --line-numbers
~~~

~~~text
=== Testes a partir da DMZ (dmz-web) ===

--- Servico e gateway
[PASSOU] D1 Nginx responde localmente (/health)
[PASSOU] D2 gateway padrao da DMZ e o firewall (10.66.2.254)

--- Permitido dentro da DMZ (mesma rede, nao passa pelo firewall)
[PASSOU] D3 portal alcanca o banco (dmz-db:5432)

--- Bloqueado pelo firewall (a DMZ nao inicia conexao para as redes internas)
[PASSOU] D4 DMZ para a LAN: porta 80 da recepcao            [F12]
[PASSOU] D5 DMZ para a externa: porta 80 do hospede         [F12]
[PASSOU] D6 DMZ para a LAN: ping na recepcao                [F12]
[PASSOU] D7 DMZ para o firewall: porta 80                   [I99]

=== Resumo: 7 passaram, 0 falharam ===
~~~

~~~text
Perfil: hospede

1) Varredura de portas na DMZ (nmap -Pn)

Starting Nmap 7.97 ( https://nmap.org ) at 2026-10-15 20:24 +0000
Nmap scan report for 10.66.2.10
Host is up (0.000035s latency).

PORT     STATE    SERVICE
22/tcp   filtered ssh
80/tcp   open     http
443/tcp  open     https
5432/tcp filtered postgresql
8443/tcp filtered https-alt

Nmap scan report for 10.66.2.12
Host is up.

PORT     STATE    SERVICE
22/tcp   filtered ssh
80/tcp   filtered http
443/tcp  filtered https
5432/tcp filtered postgresql
8443/tcp filtered https-alt

Nmap scan report for 10.66.2.11
Host is up.

PORT     STATE    SERVICE
22/tcp   filtered ssh
80/tcp   filtered http
443/tcp  filtered https
5432/tcp filtered postgresql
8443/tcp filtered https-alt

Nmap done: 3 IP addresses (3 hosts up) scanned in 1.47 seconds

2) Varredura NULL (pacotes TCP sem flags) contra o portal e o PMS

Starting Nmap 7.97 ( https://nmap.org ) at 2026-10-15 20:24 +0000
Nmap scan report for 10.66.2.10
Host is up.

PORT     STATE         SERVICE
80/tcp   open|filtered http
8443/tcp open|filtered https-alt

Nmap scan report for 10.66.2.12
Host is up.

PORT     STATE         SERVICE
80/tcp   open|filtered http
8443/tcp open|filtered https-alt

Nmap done: 2 IP addresses (2 hosts up) scanned in 2.07 seconds
~~~

A varredura comum (nmap com `-Pn`) mostra, para o hóspede, só as portas 80 e 443 do portal abertas; o PMS e o banco aparecem inteiros como `filtered`. A varredura NULL envia pacotes TCP sem nenhuma flag, que não existem em conexões reais: o `conntrack` os marca como inválidos e a regra F01 os descarta. Para a recepção, a única diferença é a porta 8443 do PMS, que aparece `open`:

~~~text
Perfil: recepcao

1) Varredura de portas na DMZ (nmap -Pn)

Starting Nmap 7.97 ( https://nmap.org ) at 2026-10-15 20:24 +0000
Nmap scan report for 10.66.2.10
Host is up (0.000040s latency).

PORT     STATE    SERVICE
22/tcp   filtered ssh
80/tcp   open     http
443/tcp  open     https
5432/tcp filtered postgresql
8443/tcp filtered https-alt

Nmap scan report for 10.66.2.12
Host is up (0.000032s latency).

PORT     STATE    SERVICE
22/tcp   filtered ssh
80/tcp   filtered http
443/tcp  filtered https
5432/tcp filtered postgresql
8443/tcp open     https-alt

Nmap scan report for 10.66.2.11
Host is up.

PORT     STATE    SERVICE
22/tcp   filtered ssh
80/tcp   filtered http
443/tcp  filtered https
5432/tcp filtered postgresql
8443/tcp filtered https-alt

Nmap done: 3 IP addresses (3 hosts up) scanned in 1.27 seconds
~~~

### 4.6 Evidência: contadores das regras

Depois dos testes, cada regra mostra quantos pacotes tratou. O contador maior que zero prova que foi aquela regra que agiu.

~~~bash
docker compose exec -T firewall iptables -L FORWARD -n -v --line-numbers
docker compose exec -T firewall iptables -L INPUT -n -v --line-numbers
~~~

~~~text
Chain FORWARD (policy DROP 0 packets, 0 bytes)
num   pkts bytes target     prot opt in     out     source               destination
1       16   640 DROP       all  --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate INVALID /* F01 descarta invalidos */
2        3   180 DROP       all  --  eth2   *      !10.66.3.0/24         0.0.0.0/0            /* F02 anti-spoofing da rede externa */
3        3   180 DROP       all  --  eth0   *      !10.66.1.0/24         0.0.0.0/0            /* F03 anti-spoofing da LAN */
4      105 24570 ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate RELATED,ESTABLISHED /* F04 retorno de conexoes autorizadas */
5        5   268 ACCEPT     tcp  --  eth2   eth1    10.66.3.0/24         10.66.2.10           tcp flags:0x17/0x02 multiport dports 80,443 ctstate NEW /* F05 Hospede para portal HTTP e HTTPS */
6        5   268 ACCEPT     tcp  --  eth0   eth1    10.66.1.0/24         10.66.2.10           tcp flags:0x17/0x02 multiport dports 80,443 ctstate NEW /* F06 Recepcao para portal HTTP e HTTPS */
7        3   148 ACCEPT     tcp  --  eth0   eth1    10.66.1.0/24         10.66.2.12           tcp dpt:8443 flags:0x17/0x02 ctstate NEW /* F07 Recepcao para PMS HTTPS */
8       20   976 DROP       all  --  eth2   eth1    0.0.0.0/0            10.66.2.12           /* F08 Hospede para PMS bloqueado */
9       48  2288 DROP       all  --  *      eth1    0.0.0.0/0            10.66.2.11           /* F09 Hospede e recepcao para banco bloqueado */
10       1    84 DROP       all  --  eth2   eth0    0.0.0.0/0            0.0.0.0/0            /* F10 Externa para LAN bloqueado */
11       1    84 DROP       all  --  eth0   eth2    0.0.0.0/0            0.0.0.0/0            /* F11 LAN para externa bloqueado */
12       7   444 DROP       all  --  eth1   *       0.0.0.0/0            0.0.0.0/0            ctstate NEW /* F12 DMZ nao inicia conexao para as redes internas */
13      31  1508 DROP       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* F99 nega o resto */
~~~

~~~text
Chain INPUT (policy DROP 0 packets, 0 bytes)
num   pkts bytes target     prot opt in     out     source               destination
1        0     0 ACCEPT     all  --  lo     *       0.0.0.0/0            0.0.0.0/0            /* I01 loopback */
2        0     0 DROP       all  --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate INVALID /* I02 descarta invalidos */
3        0     0 ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate RELATED,ESTABLISHED /* I03 retorno de trafego proprio */
4       11   708 DROP       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* I99 nega o resto (firewall invisivel) */
~~~

Como ler: a coluna `pkts` é o número de pacotes que a regra tratou, e o comentário `/* Fxx ... */` ao final identifica a regra na matriz. Nas colunas `in` e `out`, os nomes `eth0`, `eth1` e `eth2` podem vir em outra ordem em outra máquina (ou depois de reiniciar o firewall); isso não altera o resultado, porque o script descobre a interface de cada zona pelo IP.

| Teste | Contador que deve subir |
|---|---|
| P1 e P2 (portal) e a volta das respostas | F05, F06 e F04 |
| P4 da recepção (lê o PMS) | F07 e F04 |
| P4 do hóspede e N1 do hóspede (PMS) | F08 |
| N1 da recepção (PMS em outra porta) e N5 (SSH) | F99 |
| N2, N3 e N10 (banco) | F09 |
| N4 (estação da outra zona) | F10 e F11 |
| N6, N7 e D7 (firewall) | I99 |
| N8 (origem forjada) | F02 (hóspede) ou F03 (recepção) |
| Varredura NULL (pacotes TCP sem flags) | F01 |
| D4, D5 e D6 (DMZ para as redes internas) | F12 |

Para provar que o banco existe e funciona, mas só dentro da DMZ:

~~~bash
docker compose exec -T dmz-db psql -U hotel_app -d hotel -c "SELECT count(*) AS consumos FROM consumos;"
~~~

~~~text
 consumos
----------
        3
(1 row)
~~~

### 4.7 Testes de controle (opcionais)

Servem para provar que os testes detectam a ausência do firewall e que o hóspede não consegue se passar pela recepção.

**Controle 1: firewall sem regras.** Zera as regras e libera tudo; os testes de bloqueio devem **falhar**.

~~~bash
docker compose exec -T firewall sh -c "iptables -P FORWARD ACCEPT; iptables -P INPUT ACCEPT; iptables -F"
docker compose exec -T hospede sh -c "testar | grep -E 'FALHOU|Resumo'"
docker compose restart firewall
~~~

O segundo comando mostra só as linhas reprovadas e o resumo. O terceiro reinicia o firewall, que recarrega as regras sozinho. Saída do segundo comando:

~~~text
[FALHOU] P4 hospede NAO alcanca o PMS (:8443)               [F08]
[FALHOU] N1 PMS em outra porta (:80)                        [F08]
[FALHOU] N2 banco de dados (dmz-db:5432)                    [F09]
[FALHOU] N3 ping no banco (dmz-db)                          [F09]
[FALHOU] N4 ping na estacao da outra zona                   [F10]
[FALHOU] N5 SSH no portal (dmz-web:22)                      [F99]
[FALHOU] N6 firewall nao atende na porta 80                 [I99]
[FALHOU] N7 firewall nao responde a ping                    [I99]
[FALHOU] N9 nmap no PMS: nenhuma porta aberta               [F08]
[FALHOU] N10 nmap no banco: nenhuma porta aberta            [F09]
=== Resumo (hospede): 5 passaram, 10 falharam ===
~~~

O P4 do hóspede deixa de passar: sem firewall, ele alcançaria o PMS. O N8 continua passando mesmo sem firewall: a resposta ao pacote forjado volta para o endereço forjado (o da recepção) e nunca chega ao hóspede, então o `curl` expira de qualquer jeito. Por isso a prova do N8 é o contador da F02 (demonstração abaixo), e não o resultado do `curl`.

Espere o firewall voltar a `healthy` (alguns segundos; confira com `docker compose ps`) e rode o resumo de novo:

~~~bash
docker compose exec -T hospede sh -c "testar | grep Resumo"
~~~

~~~text
=== Resumo (hospede): 15 passaram, 0 falharam ===
~~~

**Controle 2: firewall parado.** Sem o firewall não existe caminho entre as redes: nem a recepção nem o hóspede alcançam os servidores.

~~~bash
docker compose stop firewall
docker compose exec -T hospede curl -sS -m 5 http://dmz-web/
docker compose exec -T recepcao curl -sSk -m 5 https://dmz-pms:8443/api/reservas/1
docker compose start firewall
~~~

Saída dos dois `curl` com o firewall parado. Primeiro o do hóspede:

~~~text
curl: (28) Connection timed out after 5003 milliseconds
~~~

Depois o da recepção:

~~~text
curl: (28) Connection timed out after 5002 milliseconds
~~~

Nos dois `curl` com o firewall parado, o resultado esperado é o tempo esgotado (`curl: (28) Connection timed out`), porque não existe caminho entre as redes.

Depois do `start` (e de o firewall voltar a `healthy`, o que leva alguns segundos), os mesmos comandos voltam a funcionar.

**Demonstração: o hóspede finge ser a recepção.** O hóspede ganha, por instantes, o IP da recepção (`10.66.1.10`) e tenta ler o PMS usando esse IP como origem. A liberação do PMS exige entrar pela interface da LAN; o pacote entra pela interface da rede externa e é descartado pela F02.

~~~bash
docker compose exec -T hospede sh -c "ip addr add 10.66.1.10/32 dev eth0; curl -ksS -m 5 --interface 10.66.1.10 https://dmz-pms:8443/api/reservas/1; ip addr del 10.66.1.10/32 dev eth0"
docker compose exec -T firewall iptables -L FORWARD -n -v --line-numbers
~~~

Saída do primeiro comando (o `curl` expira, porque o pacote é descartado):

~~~text
curl: (28) Connection timed out after 5002 milliseconds
~~~

Começo da listagem da FORWARD logo depois (aqui, só as três primeiras regras). A coluna `pkts` da F02 sobe a cada tentativa; compare com o valor da seção 4.6, que é anterior a esta demonstração. O número exato varia com o kernel, porque ele decide quantas vezes reenvia o pacote de abertura da conexão:

~~~text
Chain FORWARD (policy DROP 0 packets, 0 bytes)
num   pkts bytes target     prot opt in     out     source               destination
1       16   640 DROP       all  --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate INVALID /* F01 descarta invalidos */
2        8   480 DROP       all  --  eth2   *      !10.66.3.0/24         0.0.0.0/0            /* F02 anti-spoofing da rede externa */
3        3   180 DROP       all  --  eth0   *      !10.66.1.0/24         0.0.0.0/0            /* F03 anti-spoofing da LAN */
~~~

### 4.8 Encerramento

~~~bash
docker compose down -v
~~~

O `-v` apaga também o volume do banco, devolvendo o ambiente ao estado inicial.

---

## Apêndice A. Estrutura do repositório

~~~text
.
├── docker-compose.yml        # redes, volumes e os 6 containers
├── .env                      # IPs e credenciais do laboratório (fictícios)
├── firewall/
│   ├── Dockerfile
│   ├── entrypoint.sh         # liga o encaminhamento e carrega as regras na subida
│   └── rules.sh              # regras do iptables (editável sem rebuild)
├── cliente/                  # imagem usada pela recepção e pelo hóspede
│   ├── Dockerfile
│   ├── entrypoint.sh         # aponta o gateway padrão para o firewall
│   ├── acesso.sh             # mapa rápido: o que este perfil alcança
│   ├── testar.sh             # testes positivos e negativos do perfil
│   └── varredura.sh          # nmap contra a DMZ
├── dmz-web/                  # imagem Nginx usada pelo portal e pelo PMS
│   ├── Dockerfile
│   ├── nginx.conf            # portal: HTTP e HTTPS (certificado autoassinado)
│   ├── 40-gateway.sh         # aponta o gateway padrão para o firewall
│   ├── testar.sh             # testes feitos de dentro da DMZ
│   └── html/index.html
├── dmz-pms/
│   └── nginx.conf            # API do PMS: só a porta 8443 (HTTPS)
├── dmz-db/
│   └── init.sql              # tabelas e dados fictícios do hotel
├── README.md
└── RELATORIO.md              # este relatório
~~~

## Apêndice B. Referências

- Netfilter Project. *Documentation about the netfilter/iptables project*. https://www.netfilter.org/documentation/
- Linux kernel documentation. *Netfilter Sysfs variables* (`nf_log_all_netns`). https://docs.kernel.org/networking/netfilter-sysctl.html
- Docker Docs. *Port publishing and mapping: gateway modes*. https://docs.docker.com/engine/network/port-publishing/
- Docker Docs. *Docker Compose*. https://docs.docker.com/compose/
- Brasil. *Lei nº 13.709, de 14 de agosto de 2018* (Lei Geral de Proteção de Dados Pessoais), arts. 6º e 46. https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/l13709.htm
- GONÇALVES, Roitier Campos. *Firewall Linux, Arquitetura Netfilter e Iptables*. Material de aula, Segurança da Informação, IF Goiano.
