#!/bin/bash
set -e

DOMAIN="lek29.ru"
EMAIL="admin@lek29.ru"

echo "Получение SSL..."

docker run -it --rm --network host \
    -e DOMAINS="$DOMAIN,www.$DOMAIN" \
    -e EMAIL="$EMAIL" \
    certbot \
    certonly --webroot --webroot-path=/var/www/certbot \
    -d $DOMAIN -d www.$DOMAIN \
    --email $EMAIL --agree-tos --no-eff-email\
    --force-renewal

echo "Сертификат получен!"

# ПЕРЕКЛЮЧАЕМ nginx на HTTPS
docker stop nginx || true
docker rm nginx || true

docker run -d \
  --name nginx \
  --network starburger_app-net \
  -p 0.0.0.0:80:80 \
  -p 0.0.0.0:443:443 \
  -v $(pwd)/nginx/https.conf:/etc/nginx/conf.d/default.conf:ro \
  -v certbot_conf_vol:/etc/letsencrypt \
  -v certbot_www_vol:/var/www/certbot \
  -v static_files_vol:/var/www/static:ro \
  -v $(pwd)/media:/var/www/media:ro \
  --restart unless-stopped \
  starburger-nginx:latest


echo "HTTPS ВКЛЮЧЁН: https://$DOMAIN"
