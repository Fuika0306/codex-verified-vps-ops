# Codex 多功能 VPS 維運與驗證工具

這是一個從 Windows／PowerShell 管理 Ubuntu VPS 的 Codex Skill，涵蓋
SSH、systemd、Docker Compose、Caddy、備份、回滾與操作後驗證，並以
最小範圍變更保留其他服務與資料。

A Codex Skill for operating user-controlled Ubuntu VPS services from Windows or
PowerShell over SSH with small reversible changes, protected secrets, explicit
rollback, and independently verifiable end states.

## What it covers

- Read-only host, port, systemd, Docker Compose, Caddy, and health preflight.
- Staged configuration validation, backup, scoped activation, and rollback.
- Explicit service start, restart, stop, disable, and pause postconditions.
- Preservation checks for shared containers, volumes, databases, proxies, and
  unrelated services.
- PowerShell-to-SSH transport that avoids nested quoting and preserves Bash LF
  bytes with a Base64 payload.
- Opt-in journal output so raw logs are not retained by default.
- Clear separation between inspection, mutation, and verification.

The bundled helper scripts are read-only. They do not deploy, restart, disable,
or delete services.

## Requirements

- Codex with Skill support.
- Windows PowerShell 5.1+ or PowerShell 7 for `remote-preflight.ps1`.
- OpenSSH client configured with a verified `known_hosts` entry.
- Ubuntu or another systemd-based Linux host with Bash and GNU `base64`.
- Optional remote tools: Docker, Docker Compose, Caddy, and curl.

## Install from GitHub

### Windows PowerShell

```powershell
python -X utf8 "$env:USERPROFILE\.codex\skills\.system\skill-installer\scripts\install-skill-from-github.py" `
  --repo Fuika0306/codex-verified-vps-ops `
  --path skills/verified-vps-ops
```

### Linux or macOS

```bash
python3 "$HOME/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py" \
  --repo Fuika0306/codex-verified-vps-ops \
  --path skills/verified-vps-ops
```

The Skill becomes available on the next Codex turn.

## Example prompts

```text
Use $verified-vps-ops to inspect HOST, update SERVICE with the smallest
reversible change, preserve Docker and Caddy, and verify the end state.
```

```text
請用 $verified-vps-ops 暫停 HOST 上的 SERVICE，保留其他服務與資料，並驗證
inactive、disabled、MainPID=0；不要稍後自動重啟。
```

## Helper scripts

Preview a Windows-to-Ubuntu preflight without connecting:

```powershell
.\skills\verified-vps-ops\scripts\remote-preflight.ps1 `
  -HostName HOST `
  -User SSH_USER `
  -Service SERVICE `
  -HealthUrl https://example.invalid/health `
  -DryRun
```

Run the read-only preflight after verifying the host fingerprint and arguments:

```powershell
.\skills\verified-vps-ops\scripts\remote-preflight.ps1 `
  -HostName HOST `
  -User SSH_USER `
  -IdentityFile C:\PATH\SSH_KEY `
  -Service SERVICE
```

Journal output is disabled by default. Add `-IncludeJournal` only when a narrow
recent slice is necessary and safe to display.

On the Linux host, verify explicit service postconditions:

```bash
bash skills/verified-vps-ops/scripts/verify-service.sh \
  --service SERVICE \
  --expect-active inactive \
  --expect-enabled disabled \
  --dry-run
```

Remove `--dry-run` only on the intended host. Add `--include-journal` only when
needed; do not store complete raw journals.

## Safety contract

- Supply the target host and SSH user explicitly.
- Require a known SSH host key; the helper never disables host-key checking.
- Restrict health checks to HTTP(S) URLs without embedded credentials, query
  strings, or fragments.
- Dry-run output reports whether an SSH identity file was supplied without
  printing its local path.
- Do not print or retain credentials, complete environment files, or raw logs.
- Back up before replacing configuration or persistent data.
- Restart only the named service and verify unrelated shared services.
- Treat stop, disable, pause, and cancel requests as final.
- Mark unchecked postconditions as `not verified`.

## Repository layout

```text
skills/verified-vps-ops/   Installable Skill directory
  SKILL.md
  agents/openai.yaml
  references/runbooks.md
  scripts/
tests/validate_skill.py    Dependency-free structural and secret scan
tests/test_helpers.sh      Bash security-boundary tests
tests/test_remote_preflight.ps1
                           PowerShell security-boundary tests
.github/workflows/         Cross-platform validation
```

Auxiliary repo documentation stays outside the installable Skill directory.

## Validate locally

```powershell
python -X utf8 .\tests\validate_skill.py
```

```bash
python3 tests/validate_skill.py
bash -n skills/verified-vps-ops/scripts/remote-preflight.sh
bash -n skills/verified-vps-ops/scripts/verify-service.sh
bash skills/verified-vps-ops/scripts/verify-service.sh \
  --service app.service --expect-active inactive \
  --expect-enabled disabled --dry-run
```

The GitHub Actions workflow runs equivalent checks on Windows and Ubuntu.

## 中文摘要

這個 Skill 用於從 Windows／PowerShell 維運 Ubuntu VPS。流程固定先唯讀盤點、
再做最小可回滾變更，最後用 systemd、容器、Port、Health Check、檔案雜湊與
保留面證據驗收。任何停止或取消指令都視為最終狀態；完整原始 Journal 與憑證
不會預設輸出或保存。

## Release status

This repository is ready for an initial `v0.1.0` release after the validation
workflow passes in GitHub. Validate against a named non-production VPS before
declaring `v1.0.0` operational coverage.

## License

MIT. See [LICENSE](LICENSE).
