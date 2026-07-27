# VPS Operations Runbooks

Use only the section that matches the current task.

## Contents

1. [PowerShell and SSH](#powershell-and-ssh)
2. [Read-only inventory](#read-only-inventory)
3. [Configuration replacement](#configuration-replacement)
4. [systemd](#systemd)
5. [Docker Compose](#docker-compose)
6. [Caddy](#caddy)
7. [Secrets and permissions](#secrets-and-permissions)
8. [Verification and rollback](#verification-and-rollback)

## PowerShell and SSH

Prefer small, independent commands. PowerShell parses locally before SSH sends
the remote command, and then the remote shell parses it again.

Use these patterns in order of preference:

1. A simple remote command with no nested substitutions.
2. A local file transferred with `scp`, followed by a simple install command.
3. A local Bash script piped to `ssh HOST bash -s`.
4. Base64-encoded parameter values when a generated remote script needs dynamic
   text.

Avoid embedding JSON, regular expressions, command substitutions, heredocs, or
multiple shell languages inside one PowerShell string.

Run independent checks separately so one quoting failure does not hide the
actual service state:

```powershell
ssh -i SSH_KEY USER@HOST "systemctl is-active SERVICE"
ssh -i SSH_KEY USER@HOST "systemctl is-enabled SERVICE"
ssh -i SSH_KEY USER@HOST "systemctl show SERVICE -p MainPID -p NRestarts -p SubState"
```

Do not place secrets directly in the command line. Transfer a protected file or
read an already-protected remote file without printing it.

The preflight helper uses `BatchMode=yes` and `StrictHostKeyChecking=yes`. Verify
the host fingerprint and establish its `known_hosts` entry separately; never accept
a changed host key blindly.

## Read-only inventory

Gather a narrow snapshot:

```bash
hostname
uname -a
cat /etc/os-release
uptime
df -hT /
free -h
ss -lntup
systemctl show SERVICE \
  -p LoadState -p ActiveState -p SubState -p UnitFileState \
  -p MainPID -p NRestarts -p ExecMainStatus
journalctl -u SERVICE --since "-10 min" --no-pager
```

Request only a narrow, recent journal slice when it changes the diagnosis. Logs
may contain credentials or request data; avoid broad dumps and redact secret
values from any retained output. Do not save complete raw journals to local evidence
folders.

For configuration, inspect metadata and hashes without printing secret content:

```bash
stat -c '%n %U:%G %a %s bytes' CONFIG
sha256sum CONFIG
```

Use `systemctl cat SERVICE` only when the unit does not contain secrets in
inline environment values. Otherwise inspect specific safe fields.

## Configuration replacement

Stage and validate before installation:

```bash
set -euo pipefail
install -m 600 -o OWNER -g GROUP SOURCE CONFIG.next
CHECK_COMMAND CONFIG.next
cp -a CONFIG CONFIG.bak-before-CHANGE
install -m 600 -o OWNER -g GROUP CONFIG.next CONFIG
sha256sum CONFIG CONFIG.bak-before-CHANGE
```

Adapt mode and ownership to the existing file rather than always using `600`.
Use `600` for secret environment files.

For JSON:

```bash
python3 -m json.tool CONFIG.next >/dev/null
```

For a systemd unit:

```bash
systemd-analyze verify UNIT.next
```

For Compose:

```bash
docker compose -f COMPOSE.next.yaml config --quiet
```

For Caddy:

```bash
caddy validate --config CADDYFILE.next
```

Keep the backup on the target host until the new state has passed its stability
window.

## systemd

Inspect before changing:

```bash
systemctl cat SERVICE
systemctl show SERVICE \
  -p LoadState -p ActiveState -p SubState -p UnitFileState \
  -p MainPID -p NRestarts -p ExecMainStatus
```

Apply only the needed transition:

```bash
# Unit file changed
systemctl daemon-reload

# Runtime/config changed and restart is required
systemctl restart SERVICE

# Explicit pause/stop request
systemctl disable --now SERVICE
```

After start or restart:

```bash
systemctl is-active SERVICE
systemctl is-enabled SERVICE
systemctl show SERVICE -p MainPID -p NRestarts -p SubState -p ExecMainStatus
journalctl -u SERVICE --since "-5 min" --no-pager
```

After stop/disable:

```bash
systemctl show SERVICE \
  -p ActiveState -p SubState -p UnitFileState -p MainPID
```

Expected explicit pause state:

```text
ActiveState=inactive
SubState=dead
UnitFileState=disabled
MainPID=0
```

Do not automatically enable a service that was disabled before the task unless
the user requested activation.

## Docker Compose

Identify the actual project before operating:

```bash
docker info --format '{{json .ServerVersion}}'
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
cd COMPOSE_DIR
docker compose config --quiet
docker compose ps
```

Prefer service-scoped operations:

```bash
docker compose up -d --no-deps SERVICE
docker compose restart SERVICE
docker compose logs --since 10m --tail 100 SERVICE
```

Before and after the change, record:

- Container name and image.
- Health and restart count.
- Published ports.
- Named volumes and bind mounts.
- State of shared database, proxy, and monitoring containers.

Do not use `docker compose down -v`, prune commands, or broad container removal
when a service-scoped operation is sufficient.

## Caddy

Confirm ownership of the route before editing:

```bash
systemctl show caddy -p ActiveState -p MainPID -p NRestarts
caddy validate --config /etc/caddy/Caddyfile
journalctl -u caddy --since "-10 min" --no-pager
```

Stage and validate a candidate config before replacing the live file. Prefer a
reload when Caddy supports the change:

```bash
caddy reload --config /etc/caddy/Caddyfile
```

Verify:

- Caddy remains active with stable restart count.
- The intended domain resolves to the expected target.
- TLS and HTTP status are correct.
- Unrelated routes still answer.

## Secrets and permissions

- Store credentials in an environment or credential file, not in the unit,
  command line, Git repository, transcript, or durable memory.
- Preserve existing owner and mode unless the task explicitly corrects them.
- Use `chmod 600` for secret environment files where the service account can
  still read them.
- When inspecting a config, prefer key names, metadata, validation, and hashes
  over full content.
- If a credential is exposed, stop echoing it and report rotation/revocation as
  a separate required action.

## Verification and rollback

Define the postcondition before mutation. A complete verification normally
checks:

1. Unit or container state.
2. PID and restart count.
3. Fresh logs.
4. Listening address and port.
5. Health endpoint or protocol probe.
6. Live config hash and permissions.
7. Named unrelated services and data.
8. Backup existence.

Use a short stability interval when restart loops are possible, then repeat the
state and health checks.

Write rollback before applying:

```bash
install -m MODE -o OWNER -g GROUP CONFIG.bak-before-CHANGE CONFIG
CHECK_COMMAND CONFIG
systemctl restart SERVICE
```

Rollback is complete only after the restored state passes the same external
checks used for the new state.