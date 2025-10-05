echo "--- 1. Запуск сборки фронтенда (Parcel)... ---"
# Мы запускаем контейнер frontend_builder, который собирает бандлы в папку bundles
docker compose run frontend_builder

echo "--- 2. Сборка статики Django (collectstatic)... ---"
# Запускаем collectstatic внутри контейнера web
docker compose exec web python manage.py collectstatic --no-input

echo "--- 3. Объединение статики Parcel и Django в папку frontend_dist... ---"
docker compose exec web /bin/sh -c "rm -rf frontend_dist && \
  mkdir -p frontend_dist && \
  cp -r ./staticfiles/* ./frontend_dist/ && \
  cp -r ./bundles/* ./frontend_dist/"

echo "--- 4. Запуск всех сервисов (DB, Web, Nginx)... ---"
docker compose up -d

echo "✅ Деплой локальной статики завершен! Сайт доступен на http://localhost/"
