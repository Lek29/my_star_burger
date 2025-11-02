#!/bin/bash
set -e

echo "1. Очистка"
docker stop nginx backend db 2>/dev/null || true
docker rm nginx backend db 2>/dev/null || true
docker volume prune -f

echo "2. git pull"
git pull

echo "3. Сборка"
docker compose -f docker-compose.prod.yaml build



echo "5. Запуск БД и backend"
docker compose -f docker-compose.prod.yaml up -d db backend

echo "6. Миграции + collectstatic"
docker compose -f docker-compose.prod.yaml run --rm backend \
    python manage.py collectstatic --noinput

echo "7. Запуск nginx на HTTP"
docker stop nginx || true
docker rm nginx || true

docker run -d \
  --name nginx \
  --network starburger_app-net \
  -p 0.0.0.0:80:80 \
  -v $(pwd)/nginx/http.conf:/etc/nginx/conf.d/default.conf:ro \
  -v certbot_conf_vol:/etc/letsencrypt \
  -v certbot_www_vol:/var/www/certbot \
  -v static_files_vol:/var/www/static:ro \
  -v $(pwd)/media:/var/www/media:ro \
  --restart unless-stopped \
  starburger-nginx:latest

echo "САЙТ ПОДНЯТ: http://lek29.ru"
echo "Запустите: ./get-ssl.sh — для HTTPS"
