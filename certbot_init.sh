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
while ! docker compose -f docker-compose.prod.yaml exec nginx curl -s http://localhost >/dev/null 2>&1; do
    sleep 1
done

# 3. Запускаем Certbot для получения сертификата
docker compose run --rm \
  -v certbot_vol:/etc/ssl \
  -v certbot_vol_www:/var/www/certbot \
  certbot \
  certonly --webroot -w /var/www/certbot \
  -d $DOMAIN -d www.$DOMAIN \
  --email $EMAIL \
  $STAGING \
  --agree-tos -n || { echo "Ошибка Certbot"; docker compose -f docker-compose.prod.yaml down; exit 1; }


# 4. Выключаем временные сервисы
echo "Сертификат получен. Выключаем временные сервисы."
docker compose -f docker-compose.prod.yaml down

echo "Инициализация SSL завершена. Теперь запускайте продакшен: docker compose -f docker-compose.prod.yaml up -d --build"
