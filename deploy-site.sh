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
git pull

echo "3. Сборка образов"
compose build

echo "4. Сборка фронтенда (Parcel) — вручную"
compose run --rm \
  -v $(pwd)/frontend/bundles-src:/app/bundles-src \
  -v $(pwd)/frontend/package.json:/app/package.json \
  -v $(pwd)/frontend/package-lock.json:/app/package-lock.json \
  backend \
  npx parcel build bundles-src/index.js \
    --dist-dir /bundles \
    --public-url /static/ \
    --no-source-maps

echo "5. Запуск БД и backend"
compose up -d db backend

echo "6. Ожидание готовности backend"
until compose exec -T backend python manage.py check --deploy 2>/dev/null; do
  echo "Ждём backend..."
  sleep 5
done

echo "7. Применяем миграции и collectstatic"
compose exec -T backend python manage.py migrate --noinput
compose exec -T backend python manage.py collectstatic --noinput --clear

echo "8. Запуск nginx"
compose up -d nginx

echo "Готово: http://$DOMAIN"
echo "Проверьте: curl -I http://$DOMAIN/static/..."
