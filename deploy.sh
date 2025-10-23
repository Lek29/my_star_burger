#!/bin/bash
set -euo pipefail # Строгий режим: завершение при любой ошибке

# --- НАСТРОЙКИ ---
EMAIL="ligioner29@mail.ru" # Ваш email для Certbot
DOMAIN="lek29.ru"
DOCKER_COMPOSE_FILE="docker-compose.prod.yaml"

# --------------------------------------------------------
# 0. Подготовка и Очистка
# --------------------------------------------------------
echo "--- 0. Подготовка: Очистка старых контейнеров и обновление кода ---"
# Остановка и удаление всех старых контейнеров (кроме томов)
docker compose -f "$DOCKER_COMPOSE_FILE" down --remove-orphans
# Получение свежего кода
git pull

# --------------------------------------------------------
# 1. Сборка Docker-образов
# --------------------------------------------------------
echo "--- 1. Сборка новых Docker-образов... ---"
docker compose -f "$DOCKER_COMPOSE_FILE" build

# --------------------------------------------------------
# 2. ОДНОРАЗОВАЯ ИНИЦИАЛИЗАЦИЯ CERTBOT (Если сертификатов нет)
# --------------------------------------------------------
# Проверяем наличие файла сертификата. Обратите внимание, что мы ищем файл
# в локальном каталоге ./certbot/conf/, который монтируется в том.
if [ ! -f "./certbot/conf/live/$DOMAIN/fullchain.pem" ]; then
    echo "--- 2. СЕРТИФИКАТЫ НЕ НАЙДЕНЫ. Запуск инициализации Certbot... ---"

    # a. Запускаем временный Nginx для проверки (используя сервис nginx-init)
    echo "   > Поднимаем nginx-init на порту 80..."
    docker compose -f "$DOCKER_COMPOSE_FILE" up -d nginx-init

    # Ждем, пока Nginx-init будет готов
    sleep 5

    # b. Запускаем Certbot для получения сертификата
    echo "   > Запускаем Certbot для домена $DOMAIN..."
    docker compose -f "$DOCKER_COMPOSE_FILE" run --rm certbot \
        certonly --webroot -w /var/www/certbot \
        --email "$EMAIL" \
        -d "$DOMAIN" -d "www.$DOMAIN" \
        --rsa-key-size 4096 \
        --agree-tos \
        --noninteractive || {
            echo -e "\n--------------------------------------------------------"
            echo -e "⛔ КРИТИЧЕСКАЯ ОШИБКА CERTBOT ⛔"
            echo -e "Проверьте DNS, файрволл (порт 80) и логи nginx-init."
            docker compose -f "$DOCKER_COMPOSE_FILE" down
            exit 1
        }

    # c. Останавливаем временный Nginx
    echo "   > Остановка временного nginx-init..."
    # Останавливаем только nginx-init, а затем удаляем его контейнер
    docker compose -f "$DOCKER_COMPOSE_FILE" stop nginx-init
    docker compose -f "$DOCKER_COMPOSE_FILE" rm -f nginx-init
else
    echo "--- 2. Сертификаты уже существуют. Пропускаем инициализацию Certbot. ---"
fi


# --------------------------------------------------------
# 3. Запуск Продакшен-среды
# --------------------------------------------------------
echo "--- 3. Запуск всех продакшен-сервисов (db, web, nginx, certbot)... ---"
docker compose -f "$DOCKER_COMPOSE_FILE" up -d --remove-orphans

# --------------------------------------------------------
# 4. Сборка фронтенда (Parcel)
# --------------------------------------------------------
echo "--- 4. Сборка фронтенда (Parcel)... ---"
docker compose -f "$DOCKER_COMPOSE_FILE" run --rm frontend npx parcel build bundles-src/index.js --public-url /bundles/ --dist-dir dist --no-source-maps

# --------------------------------------------------------
# 5. Выполнение миграций и сбор статики
# --------------------------------------------------------
echo "--- 5. Выполнение миграций БД и сбор статики... ---"
docker compose -f "$DOCKER_COMPOSE_FILE" exec -T web python manage.py migrate --noinput
docker compose -f "$DOCKER_COMPOSE_FILE" exec -T web python manage.py collectstatic --noinput

# --------------------------------------------------------
# 6. Перезагрузка Nginx
# --------------------------------------------------------
echo "--- 6. Перезагрузка Nginx для применения новой статики и бандлов... ---"
docker compose -f "$DOCKER_COMPOSE_FILE" kill -s HUP nginx || true

echo -e "\n--------------------------------------------------------"
echo -e "✅ Продакшен-деплой завершен!"
echo -e "Сайт доступен по адресу https://$DOMAIN"
echo -e "--------------------------------------------------------"
