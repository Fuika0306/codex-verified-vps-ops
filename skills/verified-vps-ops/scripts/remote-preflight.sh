#!/usr/bin/env bash
set -u

service_b64='__SERVICE_B64__'
compose_b64='__COMPOSE_B64__'
health_b64='__HEALTH_B64__'
journal_b64='__JOURNAL_B64__'

decode_b64() {
    printf '%s' "$1" | base64 -d
}

if ! command -v base64 >/dev/null 2>&1; then
    printf 'ERROR base64_not_found\n' >&2
    exit 2
fi

SERVICE="$(decode_b64 "$service_b64")"
COMPOSE_DIR="$(decode_b64 "$compose_b64")"
HEALTH_URL="$(decode_b64 "$health_b64")"
INCLUDE_JOURNAL="$(decode_b64 "$journal_b64")"

section() {
    printf '\n=== %s ===\n' "$1"
}

run_check() {
    label="$1"
    shift
    printf -- '-- %s --\n' "$label"
    "$@" 2>&1 || printf 'check_exit=%s\n' "$?"
}

section host
run_check hostname hostname
run_check kernel uname -a
if [ -r /etc/os-release ]; then
    run_check os_release cat /etc/os-release
fi
run_check uptime uptime
run_check root_disk df -hT /
if command -v free >/dev/null 2>&1; then
    run_check memory free -h
fi

section listening_ports
if command -v ss >/dev/null 2>&1; then
    ss -lntup 2>&1 | sed -n '1,100p'
else
    printf 'ss_not_found\n'
fi

if [ -n "$SERVICE" ]; then
    section systemd_service
    systemctl show "$SERVICE" --no-pager \
        -p LoadState -p ActiveState -p SubState -p UnitFileState \
        -p MainPID -p NRestarts -p ExecMainStatus 2>&1 \
        || printf 'systemctl_show_exit=%s\n' "$?"
    if [ "$INCLUDE_JOURNAL" = "1" ]; then
        journalctl -u "$SERVICE" --since '-10 min' --no-pager -n 80 2>&1 \
            || printf 'journal_exit=%s\n' "$?"
    else
        printf 'journal_skipped=use_IncludeJournal_only_when_needed\n'
    fi
fi

section docker
if command -v docker >/dev/null 2>&1; then
    docker info --format 'server_version={{.ServerVersion}}' 2>&1 \
        || printf 'docker_info_exit=%s\n' "$?"
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>&1 \
        || printf 'docker_ps_exit=%s\n' "$?"

    if [ -n "$COMPOSE_DIR" ]; then
        if [ -d "$COMPOSE_DIR" ]; then
            (
                cd -- "$COMPOSE_DIR" || exit
                docker compose config --quiet
                docker compose ps
            ) 2>&1 || printf 'compose_check_exit=%s\n' "$?"
        else
            printf 'compose_dir_missing=%s\n' "$COMPOSE_DIR"
        fi
    fi
else
    printf 'docker_not_found\n'
fi

section caddy
if command -v caddy >/dev/null 2>&1; then
    caddy version 2>&1 || printf 'caddy_version_exit=%s\n' "$?"
    systemctl show caddy --no-pager \
        -p ActiveState -p SubState -p UnitFileState -p MainPID -p NRestarts \
        2>&1 || printf 'caddy_show_exit=%s\n' "$?"
else
    printf 'caddy_not_found\n'
fi

if [ -n "$HEALTH_URL" ]; then
    section health
    if command -v curl >/dev/null 2>&1; then
        curl --proto '=http,https' \
            --fail --silent --show-error --output /dev/null \
            --max-time 10 \
            --write-out 'http_status=%{http_code} remote_ip=%{remote_ip} total_seconds=%{time_total}\n' \
            "$HEALTH_URL" 2>&1 || printf 'health_exit=%s\n' "$?"
    else
        printf 'curl_not_found\n'
    fi
fi

exit 0