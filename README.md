# Laboratório de Firewall Linux: Netfilter/iptables com Docker Compose

Trabalho Parcial de **Segurança da Informação** (2026/2) · IF Goiano, campus Ceres · Sistemas de Informação
Professor: Roitier Campos Gonçalves · Aluno: **Giovana Lyssa Galdino Ribeiro**

Caso (fictício): **Hotel Vida Boa**. O portal de reservas, o PMS (sistema de gestão do hotel) e o banco de dados ficam em uma **DMZ**. A **recepção** (equipe do hotel) fica na **LAN** interna e o **hóspede** (perfil usuário) vem da rede **externa**. Um **firewall Linux (iptables)** decide o que cada perfil pode alcançar: os dois usam o portal, **só a recepção** alcança o PMS e **ninguém** alcança o banco. Tudo sobe com um comando, em containers.

O relatório técnico (definição do case, diagnóstico, matriz de regras e metodologia de testes) está em [`RELATORIO.md`](RELATORIO.md).

> Projeto didático. Todos os nomes, dados e senhas são fictícios.

## Arquitetura

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

| Container  | Zona    | IP                                    | Função                                   |
|------------|---------|---------------------------------------|------------------------------------------|
| `hospede`  | Externa | 10.66.3.10                            | Perfil usuário: o hóspede (Alpine, curl, nmap) |
| `recepcao` | LAN     | 10.66.1.10                            | Estação da recepção (mesma imagem do hóspede) |
| `firewall` | As três | 10.66.1.254, 10.66.2.254, 10.66.3.254 | Gateway padrão das três redes; filtra com iptables |
| `dmz-web`  | DMZ     | 10.66.2.10                            | Portal de reservas (Nginx, portas 80 e 443) |
| `dmz-pms`  | DMZ     | 10.66.2.12                            | API do PMS (Nginx, HTTPS na porta 8443) |
| `dmz-db`   | DMZ     | 10.66.2.11                            | Banco de dados (PostgreSQL, porta 5432) |

O que cada perfil alcança (política padrão **DROP**):

| Perfil            | Portal (80, 443) | PMS (8443) | Banco (5432) |
|-------------------|------------------|------------|--------------|
| Hóspede (usuário) | Sim              | **Não**    | Não          |
| Recepção          | Sim              | **Sim**    | Não          |

A DMZ não inicia conexões para as redes internas e o próprio firewall não oferece serviço algum.

## Requisitos

- Docker Desktop (ou Docker Engine) com Docker Compose v2, de preferência uma versão recente.
- Git.

## Como executar

~~~bash
git clone https://github.com/GioLyss/lab-firewall-hotel.git
cd lab-firewall-hotel
docker compose up -d
~~~

A primeira execução baixa as imagens-base e constrói as imagens do laboratório, o que leva alguns minutos. Confirme o estado:

~~~bash
docker compose ps
~~~

`firewall`, `dmz-web`, `dmz-pms` e `dmz-db` devem aparecer como `healthy`; `recepcao` e `hospede` como `Up`. As regras do firewall são carregadas sozinhas pelo `firewall/entrypoint.sh` quando o container sobe.

## Como testar

O comando `acesso` mostra, em segundos, o que cada perfil alcança (`ABERTO` ou `FILTRADO`):

~~~bash
docker compose exec -T hospede acesso
docker compose exec -T recepcao acesso
~~~

Os testes completos mostram `[PASSOU]` ou `[FALHOU]` para cada caso, com a regra do firewall que cada teste exercita. Execute um por vez (cada um leva cerca de meio minuto, porque os testes de bloqueio esperam a resposta que nunca vem):

~~~bash
docker compose exec -T recepcao testar
docker compose exec -T hospede testar
docker compose exec -T dmz-web testar
docker compose exec -T hospede varredura
~~~

Resultado esperado: `15 passaram, 0 falharam` no `recepcao` e no `hospede`, e `7 passaram, 0 falharam` no `dmz-web`. O `varredura` mostra o `nmap` do hóspede vendo apenas as portas 80 e 443 do portal.

Para ver as regras e quantos pacotes cada uma tratou (o contador sobe depois dos testes):

~~~bash
docker compose exec -T firewall iptables -L FORWARD -n -v --line-numbers
docker compose exec -T firewall iptables -L INPUT -n -v --line-numbers
docker compose exec -T firewall sysctl net.ipv4.ip_forward
~~~

O passo a passo completo para o avaliador, com testes positivos, negativos e controles, está na seção 4 do [`RELATORIO.md`](RELATORIO.md).

## Regras do firewall (resumo)

| ID      | Cadeia  | Regra                                                                | Ação          |
|---------|---------|----------------------------------------------------------------------|---------------|
| F01     | FORWARD | Pacotes em estado INVALID                                            | DROP          |
| F02     | FORWARD | Entrada pela rede externa com origem fora de 10.66.3.0/24 (spoofing) | DROP          |
| F03     | FORWARD | Entrada pela LAN com origem fora de 10.66.1.0/24 (spoofing)          | DROP          |
| F04     | FORWARD | Conexões já autorizadas (ESTABLISHED, RELATED)                       | ACCEPT        |
| F05     | FORWARD | Hóspede para o portal, TCP 80 e 443                                  | ACCEPT        |
| F06     | FORWARD | Recepção para o portal, TCP 80 e 443                                 | ACCEPT        |
| F07     | FORWARD | **Recepção para o PMS, TCP 8443**                                    | ACCEPT        |
| F08     | FORWARD | Hóspede para o PMS (qualquer porta)                                  | DROP          |
| F09     | FORWARD | Hóspede e recepção para o banco                                      | DROP          |
| F10-F11 | FORWARD | Entre a rede externa e a LAN, nos dois sentidos                      | DROP          |
| F12     | FORWARD | DMZ para as redes internas, conexão nova                             | DROP          |
| F99     | FORWARD | Todo o resto                                                         | DROP          |
| I01-I03 | INPUT   | Loopback, descarte de inválidos, retorno de tráfego próprio          | ACCEPT / DROP |
| I99     | INPUT   | Todo o resto (o firewall não expõe serviços)                         | DROP          |

A matriz completa, com a justificativa de negócio de cada regra, está no `RELATORIO.md`. O código das regras está em [`firewall/rules.sh`](firewall/rules.sh), comentado linha a linha.

## Estrutura do repositório

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
└── RELATORIO.md              # relatório técnico
~~~

## Encerrar e limpar

~~~bash
docker compose down       # para e remove os containers e as redes (mantém o volume do banco)
docker compose down -v    # também apaga o volume do banco, deixando tudo do zero
~~~

## Problemas comuns

- **`Pool overlaps with other one on this address space`**: a faixa 10.66.x.x já existe na sua máquina. Edite o `.env`, troque `10.66` por outro prefixo (por exemplo `10.88`) em todas as linhas de IP e rode `docker compose up -d` de novo.
- **`curl` do hóspede ou da recepção expira e os contadores do FORWARD ficam zerados**: o Docker está descartando o tráfego antes do firewall. Atualize o Docker Desktop e confirme que as redes têm `gateway_mode_ipv4: