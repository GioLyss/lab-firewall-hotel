#!/bin/sh
# =============================================================================
# 40-gateway.sh: roda no início do container do site (antes de o Nginx subir).
# Aponta o gateway padrão para o firewall. Sem isso, as respostas do site para a
# LAN não passariam pelo firewall (e a DMZ não teria caminho controlado).
# =============================================================================
set -eu

ip route replace default via "$GATEWAY_IP"
echo "40-gateway.sh: gateway padrao: $GATEWAY_IP (firewall)"