# Firewall: Alpine mínimo com iptables (backend nf_tables) e iproute2.
FROM alpine:3.22

# iptables-legacy é só um plano B para kernels sem nf_tables; se o pacote não existir, segue sem ele.
RUN apk add --no-cache iptables iproute2 \
 && (apk add --no-cache iptables-legacy || true)

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY rules.sh /etc/firewall/rules.sh

# Remove o CR do fim de linha do Windows (se houver) e torna o entrypoint executável.
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh /etc/firewall/rules.sh \
 && chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]