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
    python manage.py collectstatic --noinput --clear

echo "7. Запуск nginx на HTTP (через compose)"
docker compose -f docker-compose.prod.yaml up -d nginx

echo "САЙТ ПОДНЯТ: http://lek29.ru"
echo "Запустите: ./get-ssl.sh — для HTTPS"
