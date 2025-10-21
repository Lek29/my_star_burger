FROM nginx:latest

RUN apt update && apt install -y openssl && rm -rf /var/cache/apk/*

RUN mkdir -p /etc/ssl

RUN openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/privkey.pem \
    -out /etc/ssl/fullchain.pem \
    -subj "/CN=localhost"

COPY nginx.prod.conf /etc/nginx/conf.d/default.conf


