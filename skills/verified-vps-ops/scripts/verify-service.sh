#!/usr/bin/env bash
set -u

service=""
health_url=""
compose_dir=""
expect_active="active"
expect_enabled="any"
include_journal=0
dry_run=0

usage() {
    cat <<'EOF'
Usage:
  verify-service.sh --service SERVICE [options]

Options:
  --expect-active active|inactive|failed|any
  --expect-enabled enabled|disabled|masked|static|any
  --health-url URL
  --compose-dir PATH
  --include-journal
  --dry-run
  -h, --help
EOF
}

fail() {
    printf 'ERROR %s\n' "$*" >&2
    exit 2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --service)
            [ "$#" -ge 2 ] || fail "--service requires a value"
            service="$2"
            shift 2
            ;;
        --expect-active)
            [ "$#" -ge 2 ] || fail "--expect-active requires a value"
            expect_active="$2"
            shift 2
            ;;
        --expect-enabled)
            [ "$#" -ge 2 ] || fail "--expect-enabled requires a value"
            expect_enabled="$2"
            shift 2
            ;;
        --health-url)
            [ "$#" -ge 2 ] || fail "--health-url requires a value"
            health_url="$2"
            shift 2
            ;;
        --compose-dir)
            [ "$#" -ge 2 ] || fail "--compose-dir requires a value"
            compose_dir="$2"
            shift 2
            ;;
        --include-journal)
            include_journal=1
            shift
            ;;
        --dry-run)
            dry_run=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "unknown argument: $1"
            ;;
    esac
done

[ -n "$service" ] || fail "--service is required"

case "$service" in
    *[!A-Za-z0-9_.@-]*)
        fail "service contains unsupported characters"
        ;;
esac

case "$expect_active" in
    active|inactive|failed|any) ;;
    *) fail "invalid --expect-active value: $expect_active" ;;
esac

case "$expect_enabled" in
    enabled|disabled|masked|static|any) ;;
    *) fail "invalid --expect-enabled value: $expect_enabled" ;;
esac

if [ -n "$health_url" ]; then
    case "$health_url" in
        http://*|https://*) ;;
        *) fail "health URL must use http or https" ;;
    esac

    health_authority="${health_url#*://}"
    health_authority="${health_authority%%/*}"
    [ -n "$health_authority" ] || fail "health URL must include a host"
    case "$health_authority" in
        *@*) fail "health URL must not contain embedded credentials" ;;
    esac
    case "$health_url" in
        *\?*) fail "health URL must not contain a query string" ;;
    esac
    case "$health_url" in
        *\#*) fail "health URL must not contain a fragment" ;;
    esac
fi

if [ "$dry_run" -eq 1 ]; then
    printf 'mode=dry-run\n'
    printf 'service=%q\n' "$service"
    printf 'expect_active=%q\n' "$expect_active"
    printf 'expect_enabled=%q\n' "$expect_enabled"
    printf 'health_url=%q\n' "$health_url"
    printf 'compose_dir=%q\n' "$compose_dir"
    printf 'include_journal=%s\n' "$include_journal"
    printf 'checks=systemd_state,systemd_metadata,journal,docker_compose,health\n'
    exit 0
fi

command -v systemctl >/dev/null 2>&1 || fail "systemctl not found"

failures=0

active_state="$(systemctl is-active "$service" 2>&1)"
active_rc=$?
enabled_state="$(systemctl is-enabled "$service" 2>&1)"
enabled_rc=$?

if [ "$expect_active" = "any" ] || [ "$active_state" = "$expect_active" ]; then
    printf 'CHECK active actual=%s expected=%s status=pass rc=%s\n' \
        "$active_state" "$expect_active" "$active_rc"
else
    printf 'CHECK active actual=%s expected=%s status=fail rc=%s\n' \
        "$active_state" "$expect_active" "$active_rc"
    failures=$((failures + 1))
fi

if [ "$expect_enabled" = "any" ] || [ "$enabled_state" = "$expect_enabled" ]; then
    printf 'CHECK enabled actual=%s expected=%s status=pass rc=%s\n' \
        "$enabled_state" "$expect_enabled" "$enabled_rc"
else
    printf 'CHECK enabled actual=%s expected=%s status=fail rc=%s\n' \
        "$enabled_state" "$expect_enabled" "$enabled_rc"
    failures=$((failures + 1))
fi

printf '%s\n' '--- systemd metadata ---'
systemctl show "$service" --no-pager \
    -p LoadState -p ActiveState -p SubState -p UnitFileState \
    -p MainPID -p NRestarts -p ExecMainStatus 2>&1
show_rc=$?
if [ "$show_rc" -ne 0 ]; then
    printf 'CHECK systemd_metadata status=fail rc=%s\n' "$show_rc"
    failures=$((failures + 1))
else
    printf 'CHECK systemd_metadata status=pass rc=0\n'
fi

if [ "$include_journal" -eq 1 ]; then
    printf '%s\n' '--- recent journal ---'
    journalctl -u "$service" --since '-10 min' --no-pager -n 80 2>&1
    journal_rc=$?
    if [ "$journal_rc" -eq 0 ]; then
        printf 'CHECK journal status=pass rc=0\n'
    else
        printf 'CHECK journal status=warn rc=%s\n' "$journal_rc"
    fi
else
    printf 'CHECK journal status=skipped reason=use_--include-journal_only_when_needed\n'
fi

if [ -n "$compose_dir" ]; then
    if ! command -v docker >/dev/null 2>&1; then
        printf 'CHECK docker_compose status=fail reason=docker_not_found\n'
        failures=$((failures + 1))
    elif [ ! -d "$compose_dir" ]; then
        printf 'CHECK docker_compose status=fail reason=compose_dir_missing path=%q\n' \
            "$compose_dir"
        failures=$((failures + 1))
    else
        (
            cd -- "$compose_dir" || exit 1
            docker compose config --quiet &&
                docker compose ps
        )
        compose_rc=$?
        if [ "$compose_rc" -eq 0 ]; then
            printf 'CHECK docker_compose status=pass rc=0\n'
        else
            printf 'CHECK docker_compose status=fail rc=%s\n' "$compose_rc"
            failures=$((failures + 1))
        fi
    fi
fi

if [ -n "$health_url" ]; then
    if ! command -v curl >/dev/null 2>&1; then
        printf 'CHECK health status=fail reason=curl_not_found\n'
        failures=$((failures + 1))
    else
        health_result="$(
            curl --proto '=http,https' \
                --fail --silent --show-error --output /dev/null \
                --max-time 10 \
                --write-out 'http_status=%{http_code} remote_ip=%{remote_ip} total_seconds=%{time_total}' \
                "$health_url" 2>&1
        )"
        health_rc=$?
        if [ "$health_rc" -eq 0 ]; then
            printf 'CHECK health status=pass rc=0 %s\n' "$health_result"
        else
            printf 'CHECK health status=fail rc=%s result=%s\n' \
                "$health_rc" "$health_result"
            failures=$((failures + 1))
        fi
    fi
fi

if [ "$failures" -gt 0 ]; then
    printf 'RESULT status=fail failures=%s\n' "$failures"
    exit 1
fi

printf 'RESULT status=pass failures=0\n'