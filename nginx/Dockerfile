FROM nginx:1.25-alpine

RUN apt-get update && apt-get install -y openssl && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/ssl

COPY nginx.prod.conf /etc/nginx/conf.d/default.conf

RUN openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/privkey.pem \
    -out /etc/ssl/fullchain.pem \
    -subj "/CN=localhost"
