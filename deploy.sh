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

# Проверяем занят ли порт 80 на хосте (любой процесс)
is_port80_in_use_on_host() {
    sudo ss -tuln 2>/dev/null | awk '{print $5}' | grep -E '(:|\.|)80$' >/dev/null 2>&1
}

# Убить системный nginx если есть (stop + disable)
stop_system_nginx() {
    log "Stopping system nginx (systemctl stop nginx)..."
    sudo systemctl stop nginx >/dev/null 2>&1 || true
    sudo systemctl disable nginx >/dev/null 2>&1 || true
}

# Убить процессы, слушающие на порту 80 (fuser -> lsof -> ss-> grep + kill)
kill_any_process_on_port80() {
    log "Killing any process using TCP/80 (fuser/lsof)..."
    # fuser -k will kill processes using port 80
    sudo fuser -k 80/tcp >/dev/null 2>&1 || true

    # fallback: lsof
    if command -v lsof >/dev/null 2>&1; then
        PIDS=$(sudo lsof -t -i :80 || true)
        if [ -n "$PIDS" ]; then
            log "Killing PIDs from lsof: $PIDS"
            sudo kill -9 $PIDS >/dev/null 2>&1 || true
        fi
    fi

    # generic ss -> pidmap
    PIDS_SS=$(sudo ss -ltnp 2>/dev/null | awk '/:80/ && /pid=/{gsub(/.*pid=/,"",$0); gsub(/,.*$/,"",$0); print $NF}' | sort -u || true)
    if [ -n "$PIDS_SS" ]; then
        log "Killing PIDs from ss: $PIDS_SS"
        sudo kill -9 $PIDS_SS >/dev/null 2>&1 || true
    fi
}

# Найти docker-контейнеры, которые публикуют порт 80 (в .Ports)
docker_containers_publishing_80() {
    sudo docker ps --format '{{.ID}} {{.Names}} {{.Ports}}' | awk '/:80/{print $1}' || true
}

# Найти docker-контейнеры с 'nginx' в имени
docker_containers_named_nginx() {
    sudo docker ps --format '{{.ID}} {{.Names}}' | awk '/nginx/{print $1}' || true
}

kill_docker_candidates() {
    local ids=("$@")
    if [ ${#ids[@]} -eq 0 ]; then
        return 0
    fi
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

# 0) Stop system nginx and try to free port 80
stop_system_nginx
sleep 1

# 0.1) docker-compose down to reduce leftovers
log "docker compose down --remove-orphans (best-effort)..."
compose down --remove-orphans || true

# 0.2) Kill any host process using port 80
kill_any_process_on_port80
sleep "$WAIT_SOCK_CLOSE"

# 0.3) Kill docker containers publishing 80 or named nginx/nginx-init
mapfile -t DOCKER80 < <(docker_containers_publishing_80)
if [ ${#DOCKER80[@]} -gt 0 ]; then
    log "Found docker containers publishing :80 -> ${DOCKER80[*]}"
    kill_docker_candidates "${DOCKER80[@]}"
    sleep "$WAIT_SOCK_CLOSE"
fi

mapfile -t DOCKER_NGX < <(docker_containers_named_nginx)
if [ ${#DOCKER_NGX[@]} -gt 0 ]; then
    log "Found nginx-like docker containers -> ${DOCKER_NGX[*]}"
    kill_docker_candidates "${DOCKER_NGX[@]}"
    sleep "$WAIT_SOCK_CLOSE"
fi

# 0.4) Final host-level check for port 80
wait_port80_free_or_exit

# Pull latest code (best-effort)
log "git pull (best-effort)..."
git pull || true

# Build images
log "Building docker images..."
compose build

# 1) Certbot one-time initialization if no certificate present
if [ ! -f "./certbot/conf/live/$DOMAIN/fullchain.pem" ]; then
    log "No certificate found — performing one-time certbot initialization."

    # Ensure any possible leftover nginx containers are gone
    mapfile -t DOCKER_NGX2 < <(docker_containers_named_nginx)
    if [ ${#DOCKER_NGX2[@]} -gt 0 ]; then
        log "Killing leftover nginx containers -> ${DOCKER_NGX2[*]}"
        kill_docker_candidates "${DOCKER_NGX2[@]}"
        sleep "$WAIT_SOCK_CLOSE"
    fi

    # Double-check docker containers publishing :80
    mapfile -t DOCKER80B < <(docker_containers_publishing_80)
    if [ ${#DOCKER80B[@]} -gt 0 ]; then
        log "Killing leftover 80-publishing containers -> ${DOCKER80B[*]}"
        kill_docker_candidates "${DOCKER80B[@]}"
        sleep "$WAIT_SOCK_CLOSE"
    fi

    # Final host-level check
    wait_port80_free_or_exit

    # Bring up nginx-init only
    log "Bringing up nginx-init (detached)..."
    compose up -d nginx-init

    # wait for nginx-init to start and bind 80 inside container
    log "Waiting $WAIT_NGINX_INIT_READY seconds for nginx-init..."
    sleep "$WAIT_NGINX_INIT_READY"

    # show container status and last logs to help diagnose quickly if fails
    log "docker ps (nginx/init related):"
    sudo docker ps --format '{{.ID}} {{.Names}} {{.Status}} {{.Ports}}' | sed -n '1,200p'

    # Run certbot
    log "Running certbot (docker compose run --rm certbot certonly ...)"
    set +e
    compose run --rm certbot certonly --webroot -w /var/www/certbot \
        --email "$EMAIL" -d "$DOMAIN" -d "www.$DOMAIN" \
        --rsa-key-size 4096 --agree-tos --noninteractive
    CERTBOT_EXIT=$?
    set -e

    if [ "$CERTBOT_EXIT" -ne 0 ]; then
        err "Certbot failed (exit=$CERTBOT_EXIT). Gathering nginx-init logs and aborting."
        log "=== nginx-init logs (tail 200) ==="
        sudo docker logs --tail 200 nginx-init || true
        log "Tearing down compose and exiting."
        compose down || true
        exit 1
    fi

    log "Certbot succeeded — certificates created/renewed."

    # Stop and remove nginx-init, ensure port freed
    log "Stopping and removing nginx-init..."
    compose stop nginx-init || true
    compose rm -f nginx-init || true
    sleep "$WAIT_SOCK_CLOSE"

    wait_port80_free_or_exit
else
    log "Certificate exists — skipping certbot initialization."
fi

# 2) Start full production stack
log "Bringing up full production stack (compose up -d --remove-orphans)..."
compose up -d --remove-orphans

# 3) Build frontend assets
log "Building frontend (Parcel) inside container..."
compose run --rm frontend npx parcel build bundles-src/index.js --public-url /bundles/ --dist-dir dist --no-source-maps

# 4) Migrations and collectstatic
log "Running Django migrations and collectstatic..."
compose exec -T web python manage.py migrate --noinput
compose exec -T web python manage.py collectstatic --noinput

# 5) Reload nginx
log "Reloading nginx (HUP)..."
compose kill -s HUP nginx || true

log "=== DEPLOY FINISHED: https://$DOMAIN ==="
exit 0
