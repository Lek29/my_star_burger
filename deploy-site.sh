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

echo "4. Запуск БД и backend"
docker compose -f docker-compose.prod.yaml up -d db backend

echo "5. Миграции + collectstatic"
docker compose -f docker-compose.prod.yaml exec backend \
    python manage.py collectstatic --noinput --clear

echo "6. Запуск nginx на HTTP (через compose)"
docker compose -f docker-compose.prod.yaml up -d nginx

echo "САЙТ ПОДНЯТ: http://lek29.ru"
echo "Запустите: ./get-ssl.sh — для HTTPS"
