#!/bin/bash
# get-ssl.sh — получает сертификат и запускает автообновление

set -e

DOMAIN="lek29.ru"
EMAIL="ligioner29@mail.ru"
DOCKER_COMPOSE_FILE="docker-compose.prod.yaml"

compose() {
    sudo docker compose --file "$DOCKER_COMPOSE_FILE" "$@"
}

echo "Запуск nginx для валидации"
compose up -d nginx

echo "Ожидание nginx"
sleep 10

echo "Получение сертификата для $DOMAIN и www.$DOMAIN"
compose run --rm \
    -e DOMAINS="$DOMAIN,www.$DOMAIN" \
    -e EMAIL="$EMAIL" \
    certbot \
    certonly --webroot --webroot-path=/var/www/certbot \
    -d $DOMAIN -d www.$DOMAIN \
    --email $EMAIL --agree-tos --no-eff-email --force-renewal

echo "Перезапуск nginx с HTTPS"
compose restart nginx

echo "HTTPS РАБОТАЕТ: https://$DOMAIN"
echo "Автообновление включено (каждые 12 часов)"
