#!/bin/sh
# =============================================================================
# entrypoint.sh do firewall: roda toda vez que o container sobe.
#   1) confere o encaminhamento de pacotes (net.ipv4.ip_forward=1)
#   2) escolhe o backend do iptables que funciona neste kernel
#   3) carrega as regras de /etc/firewall/rules.sh
#   4) cria /run/firewall.ready (o healthcheck do Compose espera por esse arquivo)
# =============================================================================
set -eu

READY=/run/firewall.ready
RULES=/etc/firewall/rules.sh

# Se o container for reiniciado, o marcador antigo não pode valer: as regras são recarregadas.
rm -f "$READY"

# 1) Encaminhamento. O Compose já define "sysctls: net.ipv4.ip_forward=1"; aqui só conferimos.
{ echo 1 > /proc/sys/net/ipv4/ip_forward; } 2>/dev/null || true
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
  echo "[firewall] ERRO: net.ipv4.ip_forward nao esta ativo" >&2
  exit 1
fi
echo "[firewall] ip_forward=1 (encaminhamento de pacotes ativo)"

# 2) Backend do iptables: nf_tables (padrao do Alpine atual) ou, se o kernel nao tiver, legacy.
if ! iptables -S >/dev/null 2>&1; then
  if command -v iptables-legacy >/dev/null 2>&1 && iptables-legacy -S >/dev/null 2>&1; then
    echo "[firewall] nf_tables indisponivel neste kernel; usando iptables-legacy"
    for cmd in iptables iptables-save iptables-restore; do
      ln -sf "$(command -v "$cmd-legacy")" "$(command -v "$cmd")"
    done
  else
    echo "[firewall] ERRO: o iptables nao funciona neste kernel" >&2
    exit 1
  fi
fi

# 3) Regras. O tr remove CR caso o arquivo tenha sido salvo com fim de linha do Windows.
echo "[firewall] carregando as regras de $RULES"
tr -d '\r' < "$RULES" > /tmp/rules.sh
sh /tmp/rules.sh

# 4) Pronto: o healthcheck passa a responder "healthy" e os outros containers podem subir.
touch "$READY"
echo "[firewall] regras ativas:"
iptables -L -n --line-numbers
echo "[firewall] pronto"
exec tail -f /dev/null
