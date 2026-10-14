# Servidor Nginx da DMZ (o portal e o PMS usam esta mesma imagem):
# Alpine + curl + iproute2 + certificado autoassinado (só para o laboratório).
FROM nginx:alpine

RUN apk add --no-cache curl iproute2 openssl \
    && mkdir -p /etc/nginx/certs \
    && openssl req -x509 -nodes -newkey rsa:2048 -days 825 \
         -keyout /etc/nginx/certs/lab.key -out /etc/nginx/certs/lab.crt \
         -subj "/CN=dmz-web/O=Hotel Vale Verde (laboratorio)"

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY html/ /usr/share/nginx/html/