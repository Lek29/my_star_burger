#!/bin/bash
set -euo pipefail # Строгий режим: завершение при любой ошибке

# --- НАСТРОЙКИ ---
EMAIL="ligioner29@mail.ru" # Ваш email для Certbot
DOMAIN="lek29.ru"
DOCKER_COMPOSE_FILE="docker-compose.prod.yaml" # Используем prod-файл
INIT_NGINX_CONF="docker/nginx.init.conf"
PROD_NGINX_CONF="docker/nginx.prod.conf"

# --------------------------------------------------------
# 0. Подготовка
# --------------------------------------------------------
echo "--- 0. Подготовка Certbot ---"

# Убедитесь, что временный nginx.init.conf существует
if [ ! -f "$INIT_NGINX_CONF" ]; then
    echo "⛔ ОШИБКА: Файл $INIT_NGINX_CONF не найден. Создайте его."
    exit 1
fi

# Убедитесь, что финальный nginx.prod.conf существует
if [ ! -f "$PROD_NGINX_CONF" ]; then
    echo "⛔ ОШИБКА: Файл $PROD_NGINX_CONF не найден. Создайте его."
    exit 1
fi

# --------------------------------------------------------
# 1. Запуск временного Nginx и Certbot
# --------------------------------------------------------
echo "--- 1. Запуск временной конфигурации Nginx (только порт 80)... ---"

# Запускаем Nginx (используя nginx.init.conf) и сервис web
# Предполагается, что вы заменили в docker-compose.prod.yaml монтирование Nginx
# на временный конфиг: ./docker/nginx.init.conf:/etc/nginx/nginx.conf
docker compose -f "$DOCKER_COMPOSE_FILE" up -d nginx web

# --------------------------------------------------------
# 2. Получение сертификата
# --------------------------------------------------------
echo "--- 2. Запуск Certbot для получения сертификата... ---"

# certonly: только получить сертификат, не устанавливать
# --webroot -w /var/www/certbot: использовать webroot-метод
docker compose -f "$DOCKER_COMPOSE_FILE" run --rm certbot \
    certonly --webroot -w /var/www/certbot \
    --email "$EMAIL" \
    -d "$DOMAIN" -d "www.$DOMAIN" \
    --rsa-key-size 4096 \
    --agree-tos \
    --noninteractive || {
        echo -e "\n--------------------------------------------------------"
        echo -e "⛔ КРИТИЧЕСКАЯ ОШИБКА CERTBOT ⛔"
        echo -e "Проверьте DNS (A и CNAME записи) и файрволл (открыт ли порт 80)."
        docker compose -f "$DOCKER_COMPOSE_FILE" down
        exit 1
    }

# --------------------------------------------------------
# 3. Переключение на Production-конфиг
# --------------------------------------------------------
echo "--- 3. Переключение Nginx на Production-конфигурацию (HTTPS)... ---"

# Остановка временных контейнеров
docker compose -f "$DOCKER_COMPOSE_FILE" down

echo -e "\n--------------------------------------------------------"
echo -e "✅ Инициализация Certbot завершена."
echo -e "Следующий шаг: запустить 'docker compose -f $DOCKER_COMPOSE_FILE up -d' для продакшена."
echo -e "--------------------------------------------------------"
