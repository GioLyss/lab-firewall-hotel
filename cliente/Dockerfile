# Estação de uma zona (recepção ou hóspede): Alpine com curl, nmap e iproute2 (comando ip).
FROM alpine:3.22

RUN apk add --no-cache curl nmap iproute2

COPY acesso.sh /usr/local/bin/acesso

# Remove o CR do fim de linha do Windows (se houver) e torna o script executável.
RUN sed -i 's/\r$//' /usr/local/bin/acesso \
 && chmod +x /usr/local/bin/acesso

# Por enquanto o container só fica de pé, esperando comandos.
CMD ["tail", "-f", "/dev/null"]