#!/bin/bash
set -euo pipefail

# -----------------------------
# CONFIG
# -----------------------------
EMAIL="ligioner29@mail.ru"
DOMAIN="lek29.ru"
DOCKER_COMPOSE_FILE="docker-compose.prod.yaml"
COMPOSE_CMD="sudo docker compose --file \"$DOCKER_COMPOSE_FILE\""

# Тайминги
WAIT_NGINX_INIT_READY=8    # сколько ждать после поднятия nginx-init (сек)
WAIT_SOCK_CLOSE=2          # подождать после убийства контейнера, чтобы сокет отпустили (сек)
RETRY_CHECK_PORTS=10       # сколько раз проверять освобождение 80-го
SLEEP_BETWEEN_RETRIES=1

# -----------------------------
# HELPERS
# -----------------------------
log()   { printf "%s %s\n" "$(date -Iseconds)" "$*"; }
err()   { printf "%s ERROR: %s\n" "$(date -Iseconds)" "$*" >&2; }

# Выполнить docker compose через функцию (чтобы было удобно менять)
compose() { eval "$COMPOSE_CMD \"\$@\""; }

# Найти контейнеры Docker, которые публикуют 80 или 0.0.0.0:80
containers_using_port80() {
    # Выбираем контейнеры с :80 в списке портов
    sudo docker ps --format '{{.ID}} {{.Names}} {{.Ports}}' | awk '/:80/{print $1}'
}

# Найти контейнеры, у которых в имени есть 'nginx' (nginx или nginx-init)
containers_named_nginx() {
    sudo docker ps --format '{{.ID}} {{.Names}}' | awk '/nginx/{print $1}'
}

# Проверить, занят ли порт 80 на хосте (не только в Docker)
is_port80_in_use_on_host() {
    sudo ss -tuln 2>/dev/null | awk '{print $5}' | grep -E '(:|\\.)80$' >/dev/null 2>&1
}

# Убить контейнеры по списку id (без фатала если пусто)
kill_containers() {
    local ids=("$@")
    if [ ${#ids[@]} -eq 0 ]; then
        return 0
    fi
    log "KILL docker containers: ${ids[*]}"
    sudo docker kill "${ids[@]}" >/dev/null 2>&1 || true
    # удалить контейнеры (не обязательно, но очищает)
    sudo docker rm -f "${ids[@]}" >/dev/null 2>&1 || true
}

# Ждем пока порт 80 освободится (локально)
wait_for_port80_free_or_fail() {
    local attempt=0
    while [ $attempt -lt $RETRY_CHECK_PORTS ]; do
        if ! is_port80_in_use_on_host; then
            return 0
        fi
        attempt=$((attempt+1))
        log "Порт 80 всё ещё занят, ждём $SLEEP_BETWEEN_RETRIES s (попытка $attempt/$RETRY_CHECK_PORTS)..."
        sleep "$SLEEP_BETWEEN_RETRIES"
    done
    return 1
}

# -----------------------------
# START
# -----------------------------
log "=== START DEPLOY for $DOMAIN ==="

# 0) остановить системный nginx (освобождает порт 80 на хосте)
log "Stopping system nginx (if running)..."
sudo systemctl stop nginx >/dev/null 2>&1 || true
sleep 1

# 0.1) docker compose down — приводим в чистое состояние
log "Bringing down any existing compose stacks (remove orphans)..."
sudo docker compose --file "$DOCKER_COMPOSE_FILE" down --remove-orphans || true

# 0.2) Убедиться, что порт 80 не занят хостом (еще раз)
if is_port80_in_use_on_host; then
    err "Порт 80 занят на хосте после остановки systemd nginx. Проверьте какие процессы:"
    ss -tuln | grep ':80' || true
    err "Прерываем деплой — освободите порт 80 вручную и запустите снова."
    exit 1
fi

# 0.3) Дополнительная очистка docker-контейнеров, которые могли держать 80
log "Ищем docker-контейнеры, которые публикуют порт 80..."
mapfile -t PKS < <(containers_using_port80 || true)
if [ ${#PKS[@]} -gt 0 ]; then
    log "Найдено контейнеров, публикующих :80 -> ${PKS[*]}"
    kill_containers "${PKS[@]}"
    sleep "$WAIT_SOCK_CLOSE"
fi

# 1) Pull latest code
log "Pulling latest git changes..."
git pull || true

# 2) Build images
log "Building images..."
sudo docker compose --file "$DOCKER_COMPOSE_FILE" build

# 3) Certbot one-time initialization (если сертификатов нет)
if [ ! -f "./certbot/conf/live/$DOMAIN/fullchain.pem" ]; then
    log "Certificates NOT found — запускаем инициализацию certbot..."

    # ЕЩЕ РАЗ: гарантированно убрать все nginx-контейнеры (nginx-init или nginx)
    mapfile -t NGX < <(containers_named_nginx || true)
    if [ ${#NGX[@]} -gt 0 ]; then
        log "Найдены nginx-подобные контейнеры -> ${NGX[*]}. Убиваем..."
        kill_containers "${NGX[@]}"
        sleep "$WAIT_SOCK_CLOSE"
    fi

    # ЕЩЕ РАЗ: проверяем нет ли контейнеров с портом 80
    mapfile -t PKS2 < <(containers_using_port80 || true)
    if [ ${#PKS2[@]} -gt 0 ]; then
        log "После очистки всё ещё есть контейнеры с :80 -> ${PKS2[*]}. Убиваем..."
        kill_containers "${PKS2[@]}"
        sleep "$WAIT_SOCK_CLOSE"
    fi

    # Проверяем порт 80 на хосте
    if is_port80_in_use_on_host; then
        err "Порт 80 занят на хосте — остановите процесс (ps/ss) и повторите."
        ss -tuln | grep ':80' || true
        exit 1
    fi

    # Поднимаем nginx-init в background
    log "Поднимаем nginx-init (compose up -d nginx-init)..."
    sudo docker compose --file "$DOCKER_COMPOSE_FILE" up -d nginx-init

    # Ждём контейнер и проверяем состояние: сначала небольшой sleep, затем проверка портов/логов
    log "Ожидаем $WAIT_NGINX_INIT_READY сек для nginx-init..."
    sleep "$WAIT_NGINX_INIT_READY"

    # Проверяем, действительно ли nginx-init слушает порт 80 внутри контейнера
    if ! containers_using_port80 >/dev/null 2>&1; then
        log "Проверяем: контейнеры, публикующие :80:"
        sudo docker ps --format '{{.ID}} {{.Names}} {{.Ports}}' | sed -n '1,200p'
    fi

    # Запуск certbot (внутри docker-compose)
    log "Запускаем certbot: certonly --webroot for $DOMAIN ..."
    set +e
    sudo docker compose --file "$DOCKER_COMPOSE_FILE" run --rm certbot \
        certonly --webroot -w /var/www/certbot \
        --email "$EMAIL" \
        -d "$DOMAIN" -d "www.$DOMAIN" \
        --rsa-key-size 4096 \
        --agree-tos \
        --noninteractive
    CERTBOT_EXIT=$?
    set -e

    if [ "$CERTBOT_EXIT" -ne 0 ]; then
        err "Certbot failed (exit=$CERTBOT_EXIT). Собираем логи nginx-init и прерываем."
        log "=== Логи nginx-init (последние 200 строк) ==="
        sudo docker logs --tail 200 nginx-init || true
        log "Опускаем все compose и выходим с ошибкой."
        sudo docker compose --file "$DOCKER_COMPOSE_FILE" down || true
        exit 1
    fi

    log "Certbot успешно выдал/обновил сертификаты."

    # Останавливаем и удаляем nginx-init
    log "Останавливаем и удаляем nginx-init..."
    sudo docker compose --file "$DOCKER_COMPOSE_FILE" stop nginx-init || true
    sudo docker compose --file "$DOCKER_COMPOSE_FILE" rm -f nginx-init || true
    sleep "$WAIT_SOCK_CLOSE"

    # Доп. проверка: порт 80 свободен после удаления nginx-init
    if ! wait_for_port80_free_or_fail; then
        err "Порт 80 не освободился после удаления nginx-init. Смотрим состояние:"
        ss -tuln | grep ':80' || true
        sudo docker ps --format '{{.ID}} {{.Names}} {{.Ports}}' | sed -n '1,200p'
        exit 1
    fi
else
    log "Certificates exist — пропускаем one-time certbot step."
fi

# 4) Теперь запускаем production stack (включая основной nginx)
log "Поднимаем production-стек (compose up -d --remove-orphans)..."
sudo docker compose --file "$DOCKER_COMPOSE_FILE" up -d --remove-orphans

# 5) Сборка фронтенда (Parcel)
log "Сборка фронтенда (Parcel) внутри контейнера frontend..."
sudo docker compose --file "$DOCKER_COMPOSE_FILE" run --rm frontend \
    npx parcel build bundles-src/index.js --public-url /bundles/ --dist-dir dist --no-source-maps

# 6) Миграции и collectstatic
log "Выполняем миграции и сбор статики..."
sudo docker compose --file "$DOCKER_COMPOSE_FILE" exec -T web python manage.py migrate --noinput
sudo docker compose --file "$DOCKER_COMPOSE_FILE" exec -T web python manage.py collectstatic --noinput

# 7) Применяем HUP к nginx (если нужно)
log "Применяем HUP к nginx (если есть)..."
sudo docker compose --file "$DOCKER_COMPOSE_FILE" kill -s HUP nginx || true

log "=== DEPLOY COMPLETE ==="
log "Site should be available at: https://$DOMAIN"
exit 0
