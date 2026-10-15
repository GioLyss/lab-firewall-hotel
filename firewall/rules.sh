#!/bin/sh
# =============================================================================
# rules.sh - Regras do firewall (Netfilter/iptables, tabela filter)
# Caso: Hotel Vale Verde (fictício) - laboratório de Segurança da Informação
#
#   EXTERNA (hóspede) --[ EXT_IF ]                   [ DMZ_IF ]-- DMZ: portal, PMS, banco
#                                    FIREWALL
#   LAN (recepção)    --[ LAN_IF ]
#
# Princípios:
#   1. Política padrão DROP em INPUT e FORWARD: só passa o que for liberado de forma explícita.
#   2. Firewall stateful (conntrack): libera-se a IDA (estado NEW) e a VOLTA entra por ESTABLISHED.
#   3. O PERFIL É DEFINIDO PELA ZONA. Hóspede e recepção estão em redes diferentes e as regras
#      testam a interface de entrada (-i), não só o IP: quem trocar o IP de origem continua
#      entrando pela interface errada. Só a recepção alcança o PMS.
#   4. Regra de ouro da DMZ: a DMZ nunca inicia conexão para as redes internas.
#   5. Cada regra tem um identificador (-m comment): I01..I99 no INPUT e F01..F99 no FORWARD.
#      Os mesmos identificadores aparecem na matriz de regras do relatório e nos contadores.
#
# INPUT   = tráfego destinado ao próprio firewall.
# FORWARD = tráfego que atravessa o firewall (entre as zonas).
# =============================================================================
set -eu

: "${FW_LAN_IP:?variavel FW_LAN_IP nao definida}"
: "${FW_EXT_IP:?variavel FW_EXT_IP nao definida}"
: "${FW_DMZ_IP:?variavel FW_DMZ_IP nao definida}"
: "${LAN_SUBNET:?variavel LAN_SUBNET nao definida}"
: "${EXT_SUBNET:?variavel EXT_SUBNET nao definida}"
: "${WEB_IP:?variavel WEB_IP nao definida}"
: "${PMS_IP:?variavel PMS_IP nao definida}"
: "${DB_IP:?variavel DB_IP nao definida}"

# --- 1. Interfaces: achadas pelo IP, porque a ordem eth0/eth1/eth2 não é garantida ---
iface_do_ip() {
    ip -o -4 addr show | awk -v ip="$1" '$4 ~ ("^" ip "/") { print $2; exit }'
}
LAN_IF=$(iface_do_ip "$FW_LAN_IP")
EXT_IF=$(iface_do_ip "$FW_EXT_IP")
DMZ_IF=$(iface_do_ip "$FW_DMZ_IP")
if [ -z "$LAN_IF" ] || [ -z "$EXT_IF" ] || [ -z "$DMZ_IF" ]; then
    echo "[rules] ERRO: nao encontrei as interfaces de $FW_LAN_IP, $FW_EXT_IP e $FW_DMZ_IP" >&2
    exit 1
fi
echo "[rules] interfaces: lan=$LAN_IF | externa=$EXT_IF | dmz=$DMZ_IF"

# --- 2. Política padrão e limpeza (só a tabela filter; a tabela nat é do Docker) ---
# Fecha tudo primeiro e só depois abre o que for necessário (falha segura).
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT        # o firewall não inicia tráfego; nada a restringir aqui
iptables -F
iptables -X
iptables -Z

# --- 3. INPUT: o firewall não oferece serviço algum ---
iptables -A INPUT -i lo -m comment --comment "I01 loopback" -j ACCEPT
iptables -A INPUT -m conntrack --ctstate INVALID -m comment --comment "I02 descarta invalidos" -j DROP
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -m comment --comment "I03 retorno de trafego proprio" -j ACCEPT
iptables -A INPUT -m comment --comment "I99 nega o resto (firewall invisivel)" -j DROP

# --- 4. FORWARD: o que pode atravessar o firewall ---
# F01-F04: higiene do tráfego (estado e origem)
iptables -A FORWARD -m conntrack --ctstate INVALID -m comment --comment "F01 descarta invalidos" -j DROP
iptables -A FORWARD -i "$EXT_IF" ! -s "$EXT_SUBNET" -m comment --comment "F02 anti-spoofing da rede externa" -j DROP
iptables -A FORWARD -i "$LAN_IF" ! -s "$LAN_SUBNET" -m comment --comment "F03 anti-spoofing da LAN" -j DROP
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -m comment --comment "F04 retorno de conexoes autorizadas" -j ACCEPT

# F05-F06: os DOIS perfis podem usar o PORTAL (80 e 443)
# (--syn: uma conexão nova só começa com um SYN puro; ACK ou FIN soltos não abrem conexão)
iptables -A FORWARD -i "$EXT_IF" -o "$DMZ_IF" -s "$EXT_SUBNET" -d "$WEB_IP" -p tcp --syn -m multiport --dports 80,443 \
  -m conntrack --ctstate NEW -m comment --comment "F05 Hospede para portal HTTP e HTTPS" -j ACCEPT
iptables -A FORWARD -i "$LAN_IF" -o "$DMZ_IF" -s "$LAN_SUBNET" -d "$WEB_IP" -p tcp --syn -m multiport --dports 80,443 \
  -m conntrack --ctstate NEW -m comment --comment "F06 Recepcao para portal HTTP e HTTPS" -j ACCEPT

# F07: SÓ a recepção alcança o PMS (API HTTPS na porta 8443)
iptables -A FORWARD -i "$LAN_IF" -o "$DMZ_IF" -s "$LAN_SUBNET" -d "$PMS_IP" -p tcp --syn --dport 8443 \
  -m conntrack --ctstate NEW -m comment --comment "F07 Recepcao para PMS HTTPS" -j ACCEPT

# F08-F09: bloqueios explícitos (a política DROP já bastaria; assim aparecem na matriz e contam tentativas)
iptables -A FORWARD -i "$EXT_IF" -o "$DMZ_IF" -d "$PMS_IP" \
  -m comment --comment "F08 Hospede para PMS bloqueado" -j DROP
iptables -A FORWARD -o "$DMZ_IF" -d "$DB_IP" \
  -m comment --comment "F09 Hospede e recepcao para banco bloqueado" -j DROP

# F10-F11: sem trânsito direto entre a rede externa e a LAN
iptables -A FORWARD -i "$EXT_IF" -o "$LAN_IF" -m comment --comment "F10 Externa para LAN bloqueado" -j DROP
iptables -A FORWARD -i "$LAN_IF" -o "$EXT_IF" -m comment --comment "F11 LAN para externa bloqueado" -j DROP

# F12: regra de ouro da DMZ: conexão NOVA da DMZ para as redes internas nunca passa
iptables -A FORWARD -i "$DMZ_IF" -m conntrack --ctstate NEW \
  -m comment --comment "F12 DMZ nao inicia conexao para as redes internas" -j DROP

# F99: todo o resto é negado (a política DROP já garante; a regra explícita deixa o contador visível)
iptables -A FORWARD -m comment --comment "F99 nega o resto" -j DROP

echo "[rules] regras carregadas (INPUT: I01-I03 e I99; FORWARD: F01-F12 e F99)"