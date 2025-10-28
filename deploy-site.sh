#!/bin/bash
set -e

DOMAIN="lek29.ru"
DOCKER_COMPOSE_FILE="docker-compose.prod.yaml"

compose() {
    sudo docker compose --file "$DOCKER_COMPOSE_FILE" "$@"
}

echo "1. Останавливаем системный nginx и чистим Docker"
sudo systemctl stop nginx || true
compose down --volumes --remove-orphans || true

echo "2. git pull"
git pull || true

echo "3. Сборка образов"
compose build

echo "4. Сборка фронтенда (Parcel)"
compose run --rm frontend npx parcel build bundles-src/index.js --public-url /bundles/ --dist-dir dist --no-source-maps

echo "5. Запуск БД и backend (без nginx)"
compose up -d db backend

echo "6. Применяем миграции и collectstatic"
sleep 10   # грубо ждём пока backend стартанёт. просто и надежно
compose exec -T backend python manage.py migrate --noinput
compose exec -T backend python manage.py collectstatic --noinput

echo "7. Запуск nginx (порт 80)"
compose up -d nginx

echo "✅ Готово: http://$DOMAIN"
