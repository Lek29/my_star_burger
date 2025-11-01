#!/bin/bash
set -e

DOMAIN="lek29.ru"
DOCKER_COMPOSE_FILE="docker-compose.prod.yaml"

compose() {
    sudo docker compose --file "$DOCKER_COMPOSE_FILE" "$@"
}

echo "1. Очистка"
sudo systemctl stop nginx || true
compose down --volumes --remove-orphans

echo "2. git pull"
git pull

echo "3. Сборка образов"
compose build

echo "4. СБОРКА ФРОНТЕНДА (Parcel)"
compose run --rm backend \
    npx parcel build bundles-src/index.js \
      --dist-dir /app/bundles \
      --public-url /static/ \
      --no-source-maps

echo "5. Запуск БД и backend"
compose up -d db backend

echo "6. Ожидание backend"
until compose exec -T backend python manage.py check --deploy >/dev/null 2>&1; do
    echo "Ждём backend..."
    sleep 5
done

echo "7. Миграции + collectstatic"
compose exec -T backend python manage.py migrate --noinput
compose exec -T backend python manage.py collectstatic --noinput --clear

echo "8. Запуск nginx"
compose up -d nginx

echo "ГОТОВО: http://$DOMAIN"
echo "Проверьте: curl -I http://$DOMAIN/static/index.js"
