#!/bin/bash
set -e

DOMAIN="lek29.ru"
EMAIL="admin@lek29.ru"

echo "Получение SSL сертификата..."

# Убедимся, что nginx запущен
docker compose -f docker-compose.prod.yaml up -d nginx 2>/dev/null || true

# Получаем сертификат
docker compose -f docker-compose.prod.yaml run --rm \
    -e DOMAINS="$DOMAIN,www.$DOMAIN" \
    -e EMAIL="$EMAIL" \
    certbot \
    certonly --webroot --webroot-path=/var/www/certbot \
    -d $DOMAIN -d www.$DOMAIN \
    --email $EMAIL --agree-tos --no-eff-email

echo "Сертификат получен!"

# Перезапускаем nginx — он сам включит HTTPS
docker restart nginx

echo "HTTPS ВКЛЮЧЁН: https://$DOMAIN"
echo "Автообновление: docker compose up -d certbot"
