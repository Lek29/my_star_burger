#!/bin/bash
set -e

DOMAIN="lek29.ru"
DOCKER_COMPOSE_FILE="docker-compose.prod.yaml"

compose() {
    sudo docker compose --file "$DOCKER_COMPOSE_FILE" "$@"
}

echo "1. Очистка"
sudo systemctl stop nginx || true
compose down --volumes --remove-orphans || true

echo "2. git pull"
git pull

echo "3. Сборка образов"
compose build

echo "4. Сборка фронтенда"
compose run --rm backend \
    npx parcel build bundles-src/index.js \
      --dist-dir /app/bundles \
      --public-url /static/ \
      --no-source-maps

echo "5. Запуск БД и backend"
compose up -d db backend

echo "6. Ожидание"
until compose exec -T backend python manage.py check --deploy; do
    sleep 5
done

echo "7. Миграции + collectstatic"
compose exec -T backend python manage.py migrate --noinput
compose exec -T backend python manage.py collectstatic --noinput --clear

echo "8. Запуск nginx"
compose up -d nginx

echo "ГОТОВО: http://$DOMAIN"
