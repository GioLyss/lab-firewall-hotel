#!/bin/sh
# =============================================================================
# varredura - simula uma estação comprometida varrendo a DMZ (problemas P5 e P6 do relatório)
#
# Uso: docker compose exec -T hospede varredura
#      docker compose exec -T recepcao varredura
#
# 1) Varredura comum (nmap -Pn, que não depende de ping). Esperado:
#      portal (dmz-web):  80 e 443 abertas; o resto filtrado
#      PMS (dmz-pms):     8443 aberta SÓ para a recepção; filtrada para o hóspede
#      banco (dmz-db):    tudo filtrado para os dois perfis
# 2) Varredura NULL (-sN): envia pacotes TCP sem nenhuma flag, que não existem em
#    conexões reais. O conntrack os marca como INVALID e o contador de F01 sobe.
# =============================================================================
echo "Perfil: ${PERFIL:-?}"
echo
echo "1) Varredura de portas na DMZ (nmap -Pn)"
echo
nmap -Pn -n -T4 --max-retries 1 --host-timeout 60s -p 22,80,443,5432,8443 "$WEB_IP" "$PMS_IP" "$DB_IP"

echo
echo "2) Varredura NULL (pacotes TCP sem flags) contra o portal e o PMS"
echo
nmap -Pn -n -sN -T4 --max-retries 1 --host-timeout 60s -p 80,8443 "$WEB_IP" "$PMS_IP"
