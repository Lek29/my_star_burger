#!/bin/bash

echo "--- 1. Обновление кода с Git... ---"
git pull

echo "--- 2. Сборка новых Docker-образов... ---"
docker compose build

echo "--- 3. Сборка фронтенда (Parcel)... ---"
docker compose run --rm frontend sh -c "npm ci && npm run build"

echo "--- 4. Выполнение миграций БД... ---"
docker compose run --rm web python manage.py migrate

echo "--- 5. Сборка статики Django и объединение в frontend_dist... ---"
docker compose run --rm web python manage.py collectstatic --no-input

echo "--- 6. Запуск всех сервисов в продакшене... ---"
docker compose up -d --remove-orphans

echo "✅ Продакшен-деплой завершен!"
