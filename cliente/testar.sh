#!/bin/sh
# =============================================================================
# testar - testes feitos a partir de uma zona (container recepcao OU hospede)
#
# Uso: docker compose exec -T recepcao testar
#      docker compose exec -T hospede testar
#
# O MESMO roteiro roda nos dois perfis; o que muda é o resultado esperado para o PMS:
#   recepcao -> alcança o PMS (regra F07)
#   hospede  -> NÃO alcança (regra F08)
# Cada teste mostra [PASSOU] ou [FALHOU] e, entre colchetes, a regra do firewall que ele exercita.
# O código de saída é 0 se tudo passou. Os textos de saída são ASCII de propósito (Windows).
#
# Como diferenciar "bloqueado pelo firewall" de "porta fechada":
#   curl sai com 7  -> conexao recusada (o destino respondeu: nao ha firewall no caminho)
#   curl sai com 28 -> tempo esgotado   (ninguem respondeu: o pacote foi descartado por DROP)
# =============================================================================
PERFIL="${PERFIL:?variavel PERFIL nao definida}"
GW="${GATEWAY_IP:?variavel GATEWAY_IP nao definida}"
OUTRO="${OUTRO_IP:?variavel OUTRO_IP nao definida}"
WEB=dmz-web
PMS=dmz-pms
DB=dmz-db
PASS=0
FAIL=0

# Regra do firewall que cada perfil exercita
if [ "$PERFIL" = "recepcao" ]; then
  R_PORTAL="[F06]"; R_PMS="[F07]"; R_PMS80="[F99]"; R_OUTRA="[F11]"; R_SPOOF="[F03]"
else
  R_PORTAL="[F05]"; R_PMS="[F08]"; R_PMS80="[F08]"; R_OUTRA="[F10]"; R_SPOOF="[F02]"
fi

# ok "descricao" "[regra]"   |   bad "descricao" "[regra]" "detalhe"
ok() { PASS=$((PASS + 1)); printf '[PASSOU] %-50s %s\n' "$1" "$2"; }
bad() {
  FAIL=$((FAIL + 1)); printf '[FALHOU] %-50s %s\n' "$1" "$2"
  if [ -n "$3" ]; then printf '                      -> %s\n' "$3"; fi
}

# estado_tcp HOST PORTA -> imprime: aberta | recusada | filtrada
estado_tcp() {
  curl -s -m 3 -o /dev/null "http://$1:$2/" 2>/dev/null
  case $? in
    7)  echo recusada ;;
    28) echo filtrada ;;
    *)  echo aberta ;;
  esac
}

# deve_passar "descricao" "[regra]" comando...   -> passa se o comando funcionar
deve_passar() {
  desc=$1; tag=$2; shift 2
  if "$@" >/dev/null 2>&1; then ok "$desc" "$tag"; else bad "$desc" "$tag"; fi
}

# deve_falhar "descricao" "[regra]" comando...   -> passa se o comando NAO funcionar
deve_falhar() {
  desc=$1; tag=$2; shift 2
  if "$@" >/dev/null 2>&1; then
    bad "$desc" "$tag" "funcionou, mas deveria estar bloqueado"
  else
    ok "$desc" "$tag"
  fi
}

# deve_ser_filtrada "descricao" "[regra]" HOST PORTA -> passa se o pacote for descartado (sem resposta)
deve_ser_filtrada() {
  estado=$(estado_tcp "$3" "$4")
  if [ "$estado" = "filtrada" ]; then ok "$1" "$2"; else bad "$1" "$2" "estado observado: $estado"; fi
}

echo "=== Testes a partir da zona: $PERFIL ==="
echo "(cada teste de bloqueio espera 3 s por uma resposta que nao vem; o conjunto leva menos de 1 minuto)"

echo
echo "--- Preparacao"
if ip route | grep -q "^default via $GW"; then
  ok "gateway padrao da zona e o firewall ($GW)" ""
else
  bad "gateway padrao da zona e o firewall ($GW)" "" "rota default nao aponta para o firewall"
fi

echo
echo "--- Portal: permitido para os dois perfis"
deve_passar "P1 portal HTTP (dmz-web:80)"   "$R_PORTAL" curl -fsS -m 5 -o /dev/null "http://$WEB/"
deve_passar "P2 portal HTTPS (dmz-web:443)" "$R_PORTAL" curl -fsSk -m 5 -o /dev/null "https://$WEB/"
if curl -fsS -m 5 "http://$WEB/" 2>/dev/null | grep -q "Portal de reservas"; then
  ok "P3 pagina do portal carregada (Portal de reservas)" "$R_PORTAL"
else
  bad "P3 pagina do portal carregada (Portal de reservas)" "$R_PORTAL"
fi

echo
echo "--- PMS: o teste que separa os perfis"
if [ "$PERFIL" = "recepcao" ]; then
  if curl -fsSk -m 5 "https://$PMS:8443/api/reservas/1" 2>/dev/null | grep -q '"sistema":"pms"'; then
    ok "P4 recepcao le o PMS (dmz-pms:8443)" "$R_PMS"
  else
    bad "P4 recepcao le o PMS (dmz-pms:8443)" "$R_PMS"
  fi
else
  deve_ser_filtrada "P4 hospede NAO alcanca o PMS (:8443)" "$R_PMS" "$PMS" 8443
fi

echo
echo "--- Acessos bloqueados (devem ficar sem resposta)"
deve_ser_filtrada "N1 PMS em outra porta (:80)"          "$R_PMS80" "$PMS" 80
deve_ser_filtrada "N2 banco de dados (dmz-db:5432)"      "[F09]"    "$DB" 5432
deve_falhar       "N3 ping no banco (dmz-db)"            "[F09]"    ping -c 1 -W 2 "$DB"
deve_falhar       "N4 ping na estacao da outra zona"     "$R_OUTRA" ping -c 1 -W 2 "$OUTRO"
deve_ser_filtrada "N5 SSH no portal (dmz-web:22)"        "[F99]"    "$WEB" 22
deve_ser_filtrada "N6 firewall nao atende na porta 80"   "[I99]"    "$GW" 80
deve_falhar       "N7 firewall nao responde a ping"      "[I99]"    ping -c 1 -W 2 "$GW"

# N8: origem forjada. A estacao passa a usar o IP da OUTRA zona e tenta falar com o PMS.
# Se o firewall decidisse so pelo IP, o hospede se passaria pela recepcao. Como as regras olham a
# interface de entrada, o pacote e descartado (anti-spoofing).
iface=$(ip route | awk '/^default/ { print $5; exit }')
ip addr add "$OUTRO/32" dev "$iface" 2>/dev/null
curl -ksS -m 3 --interface "$OUTRO" -o /dev/null "https://$PMS:8443/api/reservas/1" 2>/dev/null
rc=$?
ip addr del "$OUTRO/32" dev "$iface" 2>/dev/null
if [ "$rc" -eq 28 ]; then
  ok "N8 origem forjada (IP da outra zona) descartada" "$R_SPOOF"
else
  bad "N8 origem forjada (IP da outra zona) descartada" "$R_SPOOF" "curl saiu com codigo $rc (esperado 28)"
fi

# N9 e N10: varredura de portas com nmap (-Pn: nao depende de ping)
pms=$(nmap -Pn -n -T4 --max-retries 1 --host-timeout 40s -p 80,8443 -oG - "$PMS_IP" 2>/dev/null | grep 'Ports:')
banco=$(nmap -Pn -n -T4 --max-retries 1 --host-timeout 40s -p 22,80,443,5432,8443 -oG - "$DB_IP" 2>/dev/null | grep 'Ports:')
if [ "$PERFIL" = "recepcao" ]; then
  if echo "$pms" | grep -q ' 8443/open/' && echo "$pms" | grep -q ' 80/filtered/'; then
    ok "N9 nmap no PMS: so a 8443 aberta" "[F07 F99]"
  else
    bad "N9 nmap no PMS: so a 8443 aberta" "[F07 F99]" "$pms"
  fi
else
  if [ -n "$pms" ] && ! echo "$pms" | grep -q '/open/'; then
    ok "N9 nmap no PMS: nenhuma porta aberta" "[F08]"
  else
    bad "N9 nmap no PMS: nenhuma porta aberta" "[F08]" "$pms"
  fi
fi
if [ -n "$banco" ] && ! echo "$banco" | grep -q '/open/'; then
  ok "N10 nmap no banco: nenhuma porta aberta" "[F09]"
else
  bad "N10 nmap no banco: nenhuma porta aberta" "[F09]" "$banco"
fi

echo
echo "=== Resumo ($PERFIL): $PASS passaram, $FAIL falharam ==="
echo "Contadores das regras: docker compose exec -T firewall iptables -L FORWARD -n -v --line-numbers"
[ "$FAIL" -eq 0 ]