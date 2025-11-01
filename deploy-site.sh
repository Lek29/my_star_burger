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

echo "8. Запуск nginx через docker run (постоянно)"
docker stop nginx 2>/dev/null || true
docker rm nginx 2>/dev/null || true

docker run -d \
  --name nginx \
  --network starburger_app-net \
  -p 0.0.0.0:80:80 \
  -p 0.0.0.0:443:443 \
  -v $(pwd)/nginx/nginx.prod.conf:/etc/nginx/conf.d/default.conf:ro \
  -v certbot_conf_vol:/etc/letsencrypt \
  -v certbot_www_vol:/var/www/certbot \
  -v static_files_vol:/var/www/static:ro \
  -v $(pwd)/media:/var/www/media:ro \
  --restart unless-stopped \
  starburger-nginx:latest

echo "ГОТОВО: http://$DOMAIN"
echo "Проверьте: curl -I http://$DOMAIN/static/index.js"
