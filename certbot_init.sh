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
echo "Запускаем временные сервисы (Nginx, Web, Frontend)..."
docker compose -f docker-compose.prod.yaml up -d --build nginx web frontend || {
    echo "Ошибка запуска сервисов. Удаляем временный конфиг и прерываем."
    rm -f ./nginx.conf
    exit 1
}

# 3. Ожидание готовности Nginx (более мягкая проверка)
echo "Ожидаем Nginx (до 30 секунд)..."
MAX_ATTEMPTS=30
i=0
# Используем команду curl с опцией --fail, чтобы считать 301/404 ошибкой, но это не критично.
while ! docker compose -f docker-compose.prod.yaml exec nginx curl -s http://localhost >/dev/null 2>&1 && [ "$i" -lt "$MAX_ATTEMPTS" ]; do
    sleep 1
    i=$((i+1))
done

if [ "$i" -ge "$MAX_ATTEMPTS" ]; then
    echo "--------------------------------------------------------"
    echo "ТАЙМАУТ: Nginx не запустился или не отвечает на 80 порту."
    echo "Логи Nginx:"
    docker compose -f docker-compose.prod.yaml logs nginx
    echo "--------------------------------------------------------"
    docker compose -f docker-compose.prod.yaml down
    rm -f ./nginx.conf
    exit 1
fi

echo "Nginx готов. Запускаем Certbot..."

# 4. Запускаем Certbot для получения сертификата
# ИСПРАВЛЕНИЕ: Используем стандартный путь /etc/letsencrypt для тома Certbot
if ! docker compose run --rm \
  -v certbot_vol:/etc/letsencrypt \
  -v certbot_vol_www:/var/www/certbot \
  certbot \
  certonly --webroot -w /var/www/certbot \
  -d $DOMAIN -d www.$DOMAIN \
  --email $EMAIL \
  $STAGING \
  --agree-tos -n; then
    echo "--------------------------------------------------------"
    echo "⛔ КРИТИЧЕСКАЯ ОШИБКА CERTBOT ⛔"
    echo "Certbot не смог получить сертификат. Если ошибка 'no configuration file provided: not found' сохраняется,"
    echo "проверьте определение службы 'certbot' и корректность томов в docker-compose.prod.yaml."
    echo "--------------------------------------------------------"

    # Очистка
    docker compose -f docker-compose.prod.yaml down
    rm -f ./nginx.conf
    exit 1
fi


# 5. Выключаем временные сервисы и возвращаем Prod-конфиг
echo "Сертификат получен. Выключаем временные сервисы."
docker compose -f docker-compose.prod.yaml down

# Восстанавливаем продакшен-конфиг Nginx
echo "Копируем nginx.prod.conf обратно в nginx.conf"
cp ./nginx.prod.conf ./nginx.conf

echo "Инициализация SSL завершена. Теперь запускайте продакшен: docker compose -f docker-compose.prod.yaml up -d"
