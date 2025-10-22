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
docker compose -f $COMPOSE_FILE up -d --build nginx || {
    echo "Ошибка запуска Nginx. Проверьте $COMPOSE_FILE."
    exit 1
}

# 2. Ожидание готовности Nginx
echo "Ожидаем Nginx (до 30 секунд)..."
MAX_ATTEMPTS=30
i=0
while ! docker compose -f $COMPOSE_FILE exec nginx-1 curl -k -s http://localhost >/dev/null 2>&1 && [ "$i" -lt "$MAX_ATTEMPTS" ]; do
    sleep 1
    i=$((i+1))
done

if [ "$i" -ge "$MAX_ATTEMPTS" ]; then
    echo "--------------------------------------------------------"
    echo "ТАЙМАУТ: Nginx не запустился или не отвечает на 80 порту."
    docker compose -f $COMPOSE_FILE logs nginx
    echo "--------------------------------------------------------"
    docker compose -f $COMPOSE_FILE down
    exit 1
fi

echo "Nginx готов. Запускаем Certbot..."

# 3. Запускаем Certbot для получения сертификата
# КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Не дублируем тома через -v. Полагаемся на YAML.
if ! docker compose -f $COMPOSE_FILE run --rm certbot \
  certonly --webroot -w /var/www/certbot \
  -d $DOMAIN -d www.$DOMAIN \
  --email $EMAIL \
  $STAGING \
  --agree-tos -n; then
    echo "--------------------------------------------------------"
    echo "⛔ КРИТИЧЕСКАЯ ОШИБКА CERTBOT ⛔"
    echo "Certbot не смог получить сертификат. Вывод выше должен содержать подробности."
    echo "Убедитесь, что строка 'command' в секции 'certbot' в $COMPOSE_FILE ЗАКОММЕНТИРОВАНА!"
    echo "--------------------------------------------------------"

    # Очистка
    docker compose -f $COMPOSE_FILE down
    exit 1
fi


# 4. Выключаем временные сервисы
echo "Сертификат получен. Выключаем временные сервисы."
docker compose -f $COMPOSE_FILE down

# 5. Замена конфига Nginx на продакшен
echo "Копируем nginx.prod.conf поверх nginx.init.conf (для включения SSL)."
# ВНИМАНИЕ: Скрипт предполагает, что оба файла находятся в папке ./nginx
cp ./nginx/nginx.prod.conf ./nginx/nginx.init.conf

echo "Инициализация SSL завершена. Теперь РАСКОММЕНТИРУЙТЕ строку 'command' в certbot-сервисе."
echo "Запускайте продакшен: docker compose -f $COMPOSE_FILE up -d"
