#!/bin/bash
set -euo pipefail

# --- Настройки ---
DOMAIN="lek29.ru"
EMAIL="your_email@example.com" # Укажите ваш реальный email
# Для тестирования используйте --staging. Для продакшена установите STAGING=""
STAGING="--staging"
# STAGING="" # <-- Используйте эту строку, когда будете готовы к продакшену

# Переходим в директорию скрипта
cd "$(dirname "$0")"

# КРИТИЧЕСКОЕ ИЗМЕНЕНИЕ: Определяем имя файла compose
COMPOSE_FILE="docker-compose.prod.yaml"

echo "Начало получения сертификата для $DOMAIN..."

# 1. Поднимаем Nginx (он запустится с nginx.init.conf)
echo "Запускаем Nginx..."
# Используем -f $COMPOSE_FILE для явного указания файла
docker compose -f $COMPOSE_FILE up -d --build nginx || {
    echo "Ошибка запуска Nginx. Проверьте $COMPOSE_FILE."
    exit 1
}

# 2. Проверяем, не упал ли Nginx сразу после запуска (Самый частый сценарий крэша)
echo "Проверяем статус Nginx..."
sleep 1 # Даем 1 секунду на завершение старта/крэша
CONTAINER_STATUS=$(docker compose -f $COMPOSE_FILE ps -q nginx-1)

# Проверяем, запущен ли контейнер (должен быть не пустой вывод)
if [ -z "$CONTAINER_STATUS" ]; then
    echo "--------------------------------------------------------"
    echo "⛔ КРИТИЧЕСКАЯ ОШИБКА: Контейнер Nginx упал при старте."
    echo "Выводим логи для диагностики:"
    echo "--------------------------------------------------------"
    docker compose -f $COMPOSE_FILE logs nginx-1
    echo "--------------------------------------------------------"
    docker compose -f $COMPOSE_FILE down
    exit 1
fi

# 3. Ожидание готовности Nginx
echo "Ожидаем HTTP-ответ от Nginx (до 30 секунд)..."
MAX_ATTEMPTS=30
i=0
# Используем 127.0.0.1 для более надежной проверки
while ! docker compose -f $COMPOSE_FILE exec nginx-1 curl -k -s http://127.0.0.1:80 >/dev/null 2>&1 && [ "$i" -lt "$MAX_ATTEMPTS" ]; do
    sleep 1
    i=$((i+1))
done

if [ "$i" -ge "$MAX_ATTEMPTS" ]; then
    echo "--------------------------------------------------------"
    echo "ТАЙМАУТ: Nginx запущен, но не отвечает на 80 порту."
    echo "Проверьте логи Nginx: docker compose -f $COMPOSE_FILE logs nginx-1"
    echo "--------------------------------------------------------"
    docker compose -f $COMPOSE_FILE down
    exit 1
fi

echo "Nginx готов. Запускаем Certbot..."

# 4. Запускаем Certbot для получения сертификата
if ! docker compose -f $COMPOSE_FILE run --rm certbot \
  certonly --webroot -w /var/www/certbot \
  -d $DOMAIN -d www.$DOMAIN \
  --email $EMAIL \
  $STAGING \
  --agree-tos -n; then
    echo "--------------------------------------------------------"
    echo "⛔ КРИТИЧЕСКАЯ ОШИБКА CERTBOT ⛔"
    echo "Certbot не смог получить сертификат. Вывод выше должен содержать подробности."
    echo "--------------------------------------------------------"

    # Очистка
    docker compose -f $COMPOSE_FILE down
    exit 1
fi


# 5. Выключаем временные сервисы
echo "Сертификат получен. Выключаем временные сервисы."
docker compose -f $COMPOSE_FILE down

# 6. Замена конфига Nginx на продакшен
echo "Копируем nginx.prod.conf поверх nginx.init.conf (для включения SSL)."
# ВНИМАНИЕ: Скрипт предполагает, что оба файла находятся в папке ./nginx
cp ./nginx/nginx.prod.conf ./nginx/nginx.init.conf

echo "Инициализация SSL завершена. Теперь РАСКОММЕНТИРУЙТЕ строку 'command' в certbot-сервисе."
echo "Запускайте продакшен: docker compose -f $COMPOSE_FILE up -d"
