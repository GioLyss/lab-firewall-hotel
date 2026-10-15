#!/bin/sh
# =============================================================================
# testar - testes feitos de DENTRO da DMZ (container dmz-web)
#
# Uso: docker compose exec -T dmz-web testar
#
# Simula um servidor comprometido tentando atacar as redes internas (problema P4 do relatório):
# a DMZ nunca inicia conexao para a LAN nem para a rede externa.
# Os textos sao ASCII de proposito (Windows).
#   curl sai com 7  -> conexao recusada (o destino respondeu)
#   curl sai com 28 -> tempo esgotado   (nenhuma resposta: pacote descartado)
# =============================================================================
GW="${GATEWAY_IP:?variavel GATEWAY_IP nao definida}"
PASS=0
FAIL=0

# ok "descricao" "[regra]"   |   bad "descricao" "[regra]" "detalhe"
ok() { PASS=$((PASS + 1)); printf '[PASSOU] %-50s %s\n' "$1" "$2"; }
bad() {
  FAIL=$((FAIL + 1)); printf '[FALHOU] %-50s %s\n' "$1" "$2"
  if [ -n "$3" ]; then printf '         -> %s\n' "$3"; fi
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

# deve_ser "descricao" "[regra]" ESTADO_ESPERADO HOST PORTA
deve_ser() {
  estado=$(estado_tcp "$4" "$5")
  if [ "$estado" = "$3" ]; then ok "$1" "$2"; else bad "$1" "$2" "estado observado: $estado (esperado: $3)"; fi
}

echo "=== Testes a partir da DMZ (dmz-web) ==="

echo
echo "--- Servico e gateway"
if curl -fsS -m 3 -o /dev/null http://127.0.0.1/health; then
  ok "D1 Nginx responde localmente (/health)" ""
else
  bad "D1 Nginx responde localmente (/health)" ""
fi
if ip route | grep -q "^default via $GW"; then
  ok "D2 gateway padrao da DMZ e o firewall ($GW)" ""
else
  bad "D2 gateway padrao da DMZ e o firewall ($GW)" "" "rota default nao aponta para o firewall"
fi

echo
echo "--- Permitido dentro da DMZ (mesma rede, nao passa pelo firewall)"
deve_ser "D3 portal alcanca o banco (dmz-db:5432)" "" aberta "$DB_IP" 5432

echo
echo "--- Bloqueado pelo firewall (a DMZ nao inicia conexao para as redes internas)"
deve_ser "D4 DMZ para a LAN: porta 80 da recepcao"     "[F12]" filtrada "$RECEPCAO_IP" 80
deve_ser "D5 DMZ para a externa: porta 80 do hospede"  "[F12]" filtrada "$HOSPEDE_IP" 80
if ping -c 1 -W 2 "$RECEPCAO_IP" >/dev/null 2>&1; then
  bad "D6 DMZ para a LAN: ping na recepcao" "[F12]" "funcionou, mas deveria estar bloqueado"
else
  ok "D6 DMZ para a LAN: ping na recepcao" "[F12]"
fi
deve_ser "D7 DMZ para o firewall: porta 80" "[I99]" filtrada "$GW" 80

echo
echo "=== Resumo: $PASS passaram, $FAIL falharam ==="
[ "$FAIL" -eq 0 ]