FROM nginx:1.25-alpine

RUN rm /etc/nginx/conf.d/default.conf || true

COPY nginx.prod.conf /etc/nginx/conf.d/default.conf

RUN mkdir -p /var/www/frontend /var/www/static /var/www/media /var/www/certbot

EXPOSE 80 443
