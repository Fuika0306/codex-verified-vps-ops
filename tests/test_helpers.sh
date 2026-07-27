#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFY_SCRIPT="$ROOT_DIR/skills/verified-vps-ops/scripts/verify-service.sh"
PREFLIGHT_SCRIPT="$ROOT_DIR/skills/verified-vps-ops/scripts/remote-preflight.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

expect_rejected() {
    label="$1"
    expected="$2"
    shift 2

    set +e
    output="$("$@" 2>&1)"
    rc=$?
    set -e

    [ "$rc" -ne 0 ] || fail "$label was accepted"
    printf '%s\n' "$output" | grep -F -- "$expected" >/dev/null ||
        fail "$label failed without the expected message: $output"
}

expect_rejected \
    'non-HTTP health URL' \
    'health URL must use http or https' \
    bash "$VERIFY_SCRIPT" --service app.service \
        --health-url 'file:///etc/passwd' --dry-run

expect_rejected \
    'health URL without a host' \
    'health URL must include a host' \
    bash "$VERIFY_SCRIPT" --service app.service \
        --health-url 'https:///health' --dry-run

expect_rejected \
    'health URL with embedded credentials' \
    'health URL must not contain embedded credentials' \
    bash "$VERIFY_SCRIPT" --service app.service \
        --health-url 'https://user:pass@example.invalid/health' --dry-run

expect_rejected \
    'health URL with a query string' \
    'health URL must not contain a query string' \
    bash "$VERIFY_SCRIPT" --service app.service \
        --health-url 'https://example.invalid/health?token=PLACEHOLDER' --dry-run

expect_rejected \
    'health URL with a fragment' \
    'health URL must not contain a fragment' \
    bash "$VERIFY_SCRIPT" --service app.service \
        --health-url 'https://example.invalid/health#fragment' --dry-run

for script in "$VERIFY_SCRIPT" "$PREFLIGHT_SCRIPT"; do
    grep -F -- "--proto '=http,https'" "$script" >/dev/null ||
        fail "curl protocol allowlist missing from ${script##*/}"
done

printf 'PASS: Bash helper security boundaries\n'
