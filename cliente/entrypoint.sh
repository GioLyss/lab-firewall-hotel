#!/bin/sh
# =============================================================================
# entrypoint.sh da estação (recepcao ou hospede): aponta o gateway padrão para o firewall.
# Todo tráfego que sai da zona passa a ir para o firewall, que decide o que atravessa.
# =============================================================================
set -eu

ip route replace default via "$GATEWAY_IP"
echo "[${PERFIL:-estacao}] gateway padrao: $GATEWAY_IP (firewall)"

# Permite "docker compose run recepcao <comando>"; sem comando, fica em espera.
if [ "$#" -gt 0 ]; then
  exec "$@"
fi
exec tail -f /dev/null