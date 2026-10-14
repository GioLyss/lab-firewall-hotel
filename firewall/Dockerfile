# Firewall: Alpine mínimo com iptables e iproute2.
FROM alpine:3.22

RUN apk add --no-cache iptables iproute2

# Por enquanto o container só fica de pé; as regras serão digitadas à mão (etapa 3).
CMD ["tail", "-f", "/dev/null"]