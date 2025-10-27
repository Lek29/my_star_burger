#!/bin/bash
set -euo pipefail

# -----------------------------
# CONFIG
# -----------------------------
EMAIL="ligioner29@mail.ru"
DOMAIN="lek29.ru"
DOCKER_COMPOSE_FILE="docker-compose.prod.yaml"
WAIT_NGINX_INIT_READY=8    # время ожидания после поднятия nginx-init (сек)
WAIT_SOCK_CLOSE=2          # время ожидания после убийства процессов (сек)
MAX_PORT_FREE_CHECKS=10
SLEEP_BETWEEN_CHECKS=1

log() { printf "%s %s\n" "$(date -Iseconds)" "$*"; }
err() { printf "%s ERROR: %s\n" "$(date -Iseconds)" "$*" >&2; }

compose() { sudo docker compose --file "$DOCKER_COMPOSE_FILE" "$@"; }

is_port80_in_use_on_host() {
    sudo ss -tuln 2>/dev/null | awk '{print $5}' | grep -E '(:|\.|)80$' >/dev/null 2>&1
}

stop_system_nginx() {
    log "Stopping system nginx..."
    sudo systemctl stop nginx >/dev/null 2>&1 || true
    sudo systemctl disable nginx >/dev/null 2>&1 || true
}

kill_any_process_on_port80() {
    log "Killing any host process using TCP/80..."
    sudo fuser -k 80/tcp >/dev/null 2>&1 || true

    if command -v lsof >/dev/null 2>&1; then
        PIDS=$(sudo lsof -t -i :80 || true)
        if [ -n "$PIDS" ]; then
            log "Killing PIDs from lsof: $PIDS"
            sudo kill -9 $PIDS >/dev/null 2>&1 || true
        fi
    fi

    PIDS_SS=$(sudo ss -ltnp 2>/dev/null | awk '/:80/ && /pid=/{gsub(/.*pid=/,"",$0); gsub(/,.*$/,"",$0); print $NF}' | sort -u || true)
    if [ -n "$PIDS_SS" ]; then
        log "Killing PIDs from ss: $PIDS_SS"
        sudo kill -9 $PIDS_SS >/dev/null 2>&1 || true
    fi
}

docker_containers_publishing_80() {
    sudo docker ps --format '{{.ID}} {{.Names}} {{.Ports}}' | awk '/:80/{print $1}' || true
}

docker_containers_named_nginx() {
    sudo docker ps --format '{{.ID}} {{.Names}}' | awk '/nginx/{print $1}' || true
}

kill_docker_candidates() {
    local ids=("$@")
    if [ ${#ids[@]} -eq 0 ]; then return 0; fi
    log "Killing docker containers: ${ids[*]}"
    sudo docker kill "${ids[@]}" >/dev/null 2>&1 || true
    sudo docker rm -f "${ids[@]}" >/dev/null 2>&1 || true
}

wait_port80_free_or_exit() {
    local i=0
    while [ $i -lt $MAX_PORT_FREE_CHECKS ]; do
        if ! is_port80_in_use_on_host; then
            log "Port 80 is free."
            return 0
        fi
        i=$((i+1))
        log "Port 80 still in use, waiting $SLEEP_BETWEEN_CHECKS s (attempt $i/$MAX_PORT_FREE_CHECKS)..."
        sleep "$SLEEP_BETWEEN_CHECKS"
    done
    err "Port 80 is still in use after waiting. Aborting."
    ss -tuln | grep ':80' || true
    sudo docker ps --format '{{.ID}} {{.Names}} {{.Ports}}' | sed -n '1,200p' || true
    exit 1
}

# -----------------------------
# MAIN
# -----------------------------
log "=== DEPLOY START for $DOMAIN ==="

# 0) Stop system nginx and free port 80
stop_system_nginx
sleep 1

compose down --remove-orphans || true
kill_any_process_on_port80
sleep "$WAIT_SOCK_CLOSE"

mapfile -t DOCKER80 < <(docker_containers_publishing_80)
kill_docker_candidates "${DOCKER80[@]}"
sleep "$WAIT_SOCK_CLOSE"

mapfile -t DOCKER_NGX < <(docker_containers_named_nginx)
kill_docker_candidates "${DOCKER_NGX[@]}"
sleep "$WAIT_SOCK_CLOSE"

wait_port80_free_or_exit

git pull || true
compose build

# 1) Certbot initialization if missing
if [ ! -f "./certbot/conf/live/$DOMAIN/fullchain.pem" ]; then
    log "No certificate found — performing one-time certbot initialization."

    wait_port80_free_or_exit

    log "Bringing up nginx-init..."
    compose up -d nginx-init
    sleep "$WAIT_NGINX_INIT_READY"

    log "Running certbot..."
    set +e
    compose run --rm --no-deps certbot certonly --webroot -w /var/www/certbot \
        --email "$EMAIL" -d "$DOMAIN" -d "www.$DOMAIN" \
        --rsa-key-size 4096 --agree-tos --noninteractive
    CERTBOT_EXIT=$?
    set -e

    if [ "$CERTBOT_EXIT" -ne 0 ]; then
        err "Certbot failed (exit=$CERTBOT_EXIT). Dumping nginx-init logs..."
        sudo docker logs --tail 200 nginx-init || true
        compose down || true
        exit 1
    fi

    log "Certbot succeeded — removing nginx-init..."
    compose stop nginx-init || true
    compose rm -f nginx-init || true
    sleep "$WAIT_SOCK_CLOSE"

    wait_port80_free_or_exit
else
    log "Certificate exists — skipping certbot."
fi

# 2) Start production stack
log "Bringing up production stack..."
compose up -d --remove-orphans

# 3) Build frontend
log "Building frontend..."
compose run --rm frontend npx parcel build bundles-src/index.js --public-url /bundles/ --dist-dir dist --no-source-maps

# 4) Migrations + collectstatic
log "Running migrations and collectstatic..."
compose exec -T web python manage.py migrate --noinput
compose exec -T web python manage.py collectstatic --noinput

# 5) Reload nginx
log "Reloading nginx..."
compose kill -s HUP nginx || true

log "=== DEPLOY FINISHED: https://$DOMAIN ==="
exit 0
