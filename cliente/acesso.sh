#!/bin/sh
# =============================================================================
# acesso - mostra o que ESTE perfil consegue alcançar na DMZ
#
# Uso: docker compose exec -T hospede acesso
#      docker compose exec -T recepcao acesso
#
# Cada alvo é testado com curl, esperando no máximo 3 s:
#   ABERTO   -> o servidor respondeu
#   FILTRADO -> ninguém respondeu: o pacote foi descartado (DROP do firewall)
#   RECUSADO -> a máquina respondeu "porta fechada" (não há firewall no caminho)
# Os textos de saída são ASCII de propósito (evita caracteres quebrados no Windows).
# =============================================================================

# sondar ROTULO ALVO URL
sondar() {
  curl -ksS -m 3 -o /dev/null "$3" 2>/dev/null
  case $? in
    6)  estado="ERRO (nome nao resolvido)" ;;
    7)  estado="RECUSADO" ;;
    28) estado="FILTRADO" ;;
    *)  estado="ABERTO" ;;
  esac
  printf '  %-11s %-20s %s\n' "$1" "$2" "$estado"
}

echo "Perfil: ${PERFIL:-?}"
sondar portal dmz-web:80   http://dmz-web/
sondar pms    dmz-pms:8443 https://dmz-pms:8443/api/reservas/1
sondar banco  dmz-db:5432  http://dmz-db:5432/