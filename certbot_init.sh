#!/bin/bash
# Скрипт для получения первого SSL-сертификата. Запускать ОДИН РАЗ.

# --- Настройки ---
DOMAIN="lek29.ru"
EMAIL="your_email@example.com"
# Установите STAGING="" для продакшена.
STAGING="--staging"

echo "Начало получения сертификата для $DOMAIN..."

# 1. *** КРИТИЧЕСКИЙ ШАГ: ПОДМЕНА КОНФИГА NGINX ***
# Копируем временный конфиг (без SSL) на то место, которое Docker Compose ожидает найти (nginx.conf)
echo "Временно копируем nginx.init.conf в nginx.conf..."
cp ./nginx.init.conf ./nginx.conf

# 2. Поднимаем Nginx, Web и Frontend для Certbot Challenge
# Добавлена очистка временного файла при неудачном запуске
docker compose -f docker-compose.prod.yaml up -d --build nginx web frontend || {
    echo "Ошибка запуска сервисов. Отменяем запуск и удаляем временный конфиг."
    rm -f ./nginx.conf
    exit 1
}

# 3. Ожидание готовности Nginx (Добавлена диагностика и таймаут)
echo "Ожидаем Nginx..."
MAX_ATTEMPTS=30
i=0
while ! docker compose -f docker-compose.prod.yaml exec nginx curl -s http://localhost >/dev/null 2>&1; do
    sleep 1
    i=$((i+1))

    if [ "$i" -gt "$MAX_ATTEMPTS" ]; then
        echo "--------------------------------------------------------"
        echo "ТАЙМАУТ: Nginx не запустился за $MAX_ATTEMPTS секунд."
        echo "Выводим логи контейнера Nginx для диагностики причины падения:"
        echo "--------------------------------------------------------"
        docker compose -f docker-compose.prod.yaml logs nginx
        echo "--------------------------------------------------------"
        echo "Ошибка: Nginx не готов. Отмена инициализации."

        # Очистка
        docker compose -f docker-compose.prod.yaml down
        rm -f ./nginx.conf
        exit 1
    fi
done

# 4. Запускаем Certbot для получения сертификата
docker compose run --rm \
  -v certbot_vol:/etc/ssl \
  -v certbot_vol_www:/var/www/certbot \
  certbot \
  certonly --webroot -w /var/www/certbot \
  -d $DOMAIN -d www.$DOMAIN \
  --email $EMAIL \
  $STAGING \
  --agree-tos -n || {
    echo "Ошибка Certbot. Выводим логи Nginx для проверки Certbot Challenge."
    docker compose -f docker-compose.prod.yaml logs nginx
    docker compose -f docker-compose.prod.yaml down
    rm -f ./nginx.conf
    exit 1
}


# 5. Выключаем временные сервисы и возвращаем Prod-конфиг
echo "Сертификат получен. Выключаем временные сервисы и восстанавливаем конфиг."
docker compose -f docker-compose.prod.yaml down

# Восстанавливаем продакшен-конфиг Nginx
echo "Копируем nginx.prod.conf обратно в nginx.conf"
cp ./nginx.prod.conf ./nginx.conf

echo "Инициализация SSL завершена. Теперь запускайте продакшен: docker compose -f docker-compose.prod.yaml up -d"
