# Estação de uma zona (recepção ou hóspede): Alpine com curl, nmap e iproute2 (comando ip).
FROM alpine:3.22

RUN apk add --no-cache curl nmap iproute2

COPY acesso.sh /usr/local/bin/acesso
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Remove o CR do fim de linha do Windows (se houver) e torna os scripts executáveis.
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh /usr/local/bin/acesso \
  && chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/acesso

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]