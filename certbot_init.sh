#!/bin/bash
# Скрипт для получения первого SSL-сертификата. Запускать ОДИН РАЗ.

# --- Настройки ---
DOMAIN="lek29.ru"
EMAIL="your_email@example.com"
# Установите STAGING="" для продакшена.
STAGING="--staging"

echo "Начало получения сертификата для $DOMAIN..."

# 1. Поднимаем Nginx, Web и Frontend для Certbot Challenge
docker compose -f docker-compose.prod.yaml up -d --build nginx web frontend  || { echo "Ошибка запуска сервисов."; exit 1; }

# 2. Ожидание готовности Nginx
echo "Ожидаем Nginx..."
while ! docker compose -f docker-compose.prod.yaml exec nginx nc -z localhost 80; do
    sleep 1
done

# 3. Запускаем Certbot для получения сертификата
docker compose run --rm certbot \
    certonly --webroot -w /var/www/certbot \
    -d $DOMAIN \
    --email $EMAIL \
    $STAGING \
    --agree-tos \
    -n || { echo "Ошибка Certbot. Отмена."; docker compose down; exit 1; }


# 4. Выключаем временные сервисы
echo "Сертификат получен. Выключаем временные сервисы."
docker compose -f docker-compose.prod.yaml down

echo "Инициализация SSL завершена. Теперь запускайте продакшен: docker compose -f docker-compose.prod.yaml up -d --build"
