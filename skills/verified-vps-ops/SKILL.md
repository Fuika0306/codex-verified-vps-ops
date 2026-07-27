---
name: verified-vps-ops
description: Operate and troubleshoot user-controlled Ubuntu VPS services from Windows or PowerShell over SSH with minimal reversible changes, backups, secret-safe transfers, systemd, Docker Compose, Caddy, port and log checks, rollback, and evidence-based postconditions. Use whenever the user asks to deploy, update, configure, restart, stop, disable, delete, migrate, inspect, or debug a VPS or remote service involving SSH, systemd, Docker, Docker Compose, Caddy, live configuration, health checks, or production verification; also trigger on Chinese requests mentioning VPS、遠端主機、部署、更新、重啟、停止、停用、刪除、除錯、服務狀態、日誌、回滾 or 保留其他服務.
---

# Verified VPS Ops

Operate the named VPS as an evidence-driven state transition. Inspect the exact
runtime first, change the smallest possible surface, preserve unrelated
services and data, and prove the requested end state.

## Operating contract

- Treat the user's named host, service, file, stack, and desired state as the
  authority boundary. Never infer a different target from nearby context.
- Start read-only. Inspect the live artifact, service definition, process,
  container, port, log, and endpoint relevant to the request.
- Separate observation from mutation. A successful inspection does not grant
  permission for an unrelated change.
- Make one independently verifiable change at a time. Back up before replacing
  configuration or persistent data.
- Preserve named shared services, containers, volumes, databases, certificates,
  and unrelated ports.
- Keep secrets in protected files. Do not print or place tokens, passwords,
  private keys, webhook URLs, or complete environment files in chat, command
  lines, repositories, task state, or durable memory. When transfer is required,
  use a protected file and verify its metadata without displaying its content.
- Treat a direct stop, disable, pause, or cancel request as final. Do not
  restart, enable, install, or continue rollout work without a new request.
- Do not report completion from an exit code alone. Verify the external state.

## Workflow

### 1. Freeze the target and postcondition

Record:

- Target host and SSH identity source.
- Exact service, compose project, config file, port, or endpoint in scope.
- Requested final state, such as `active/enabled`, `inactive/disabled`, a
  particular config hash, or an HTTP success response.
- Named services and data that must remain unchanged.
- A rollback artifact and the commands that will restore it.

Ask one concise question only when the target or intended final state cannot be
discovered safely. Otherwise inspect and proceed.

### 2. Run a read-only preflight

Inspect only what changes the decision:

- Host identity, OS/version, uptime, disk, memory, and listening ports.
- `systemctl cat/show/status` for the named unit, including `ActiveState`,
  `SubState`, `UnitFileState`, `MainPID`, `NRestarts`, and `ExecMainStatus`.
- A narrow fresh journal slice for the named service only when needed; treat
  journal output as potentially secret-bearing.
  Keep it ephemeral unless a redacted excerpt is required as evidence.
- Docker engine state, named compose project, containers, mounts, and health.
- Caddy config and service state when it owns the route.
- Current config syntax, permissions, owner, hash, and the public health probe.

Use `scripts/remote-preflight.ps1` from Windows when a repeatable snapshot is
useful. Run it with `-DryRun` first if argument construction needs review. The
script is read-only and sends a Base64-encoded Bash body over standard input to avoid nested
PowerShell/SSH quoting.

### 3. Choose the smallest reversible change

Before mutation, state:

1. The evidence-supported cause or operational need.
2. The exact files, units, containers, or packages that will change.
3. The backup path and restoration command.
4. The validation command that must pass before activation.
5. The checks that will prove unrelated services remained healthy.

Prefer:

- `config.next` or a temporary file on the same filesystem.
- Syntax validation before installation.
- A timestamped or purpose-named backup with preserved permissions.
- Atomic replacement or an install command with explicit owner/mode.
- `systemctl daemon-reload` only when the unit definition changed.
- Restarting only the affected service.

For complex remote edits, create a small local script or staged file, inspect
it, transfer it with `scp`, and run a simple remote command. Avoid multi-layer
PowerShell strings containing shell substitutions, regexes, JSON, or heredocs.

### 4. Execute with checkpoints

- Re-read the current file or state immediately before applying the change.
- Stop if it differs from the inspected version unless the new state is
  understood and the plan remains valid.
- Validate the staged artifact.
- Create and confirm the backup.
- Apply the single scoped change.
- Capture command output and exit status without exposing secrets.
- Stop the rollout on the first failed activation gate. Do not stack speculative
  fixes.

For new continuous services, prefer:

1. Install without activation.
2. Install protected environment/config files.
3. Test the external delivery or dependency.
4. Run a one-shot or baseline execution.
5. Enable and start the service.
6. Inspect the fresh PID, restart count, logs, endpoint, and dependencies.

### 5. Verify the requested end state

Use direct checks rather than narrative confidence:

- systemd state and enablement match the requested state.
- `MainPID`, `SubState`, `ExecMainStatus`, and `NRestarts` are plausible.
- Fresh logs contain no new fatal loop or credential disclosure.
- The expected port is listening on the intended address only.
- HTTP or protocol probes return the expected status and content shape.
- Docker containers, health, mounts, and unrelated shared services remain
  intact.
- The live config hash and permissions match the staged artifact.
- The rollback backup exists and is readable only as intended.

Use `scripts/verify-service.sh` on an Ubuntu host for a compact pass/fail check.
Pass the expected active and enabled states explicitly. Add
`--include-journal` only when log content is required and safe to display.

For a stop or pause request, verify at minimum:

```text
ActiveState=inactive
SubState=dead
UnitFileState=disabled
MainPID=0
```

Do not treat an upstream billing, rate-limit, authentication, DNS, or provider
failure as a successful application deployment. Report it as a separate
activation gate with the exact non-secret evidence.

### 6. Report with evidence

Return:

1. Final state in one line.
2. Target and scope actually changed.
3. Backup path and rollback command.
4. Commands or probes run and their relevant results.
5. Preservation checks for unrelated services/data.
6. Remaining gate or uncertainty.

Say `not verified` for any postcondition that was not directly checked.

## Failure discipline

- After three failures in the same stage, stop repeating the same command.
- Reduce the command, change the quoting/transfer strategy, or run one minimal
  diagnostic experiment.
- Distinguish transport, authentication, syntax, service, dependency, and
  provider failures.
- Never broaden permissions, delete data, rotate credentials, or rebuild an
  unrelated stack as a speculative fix.

## Resources

- Read [references/runbooks.md](references/runbooks.md) for systemd, Docker
  Compose, Caddy, PowerShell/SSH, backup, rollback, and verification patterns.
- Run `scripts/remote-preflight.ps1` for a read-only Windows-to-Ubuntu snapshot.
- Run `scripts/verify-service.sh` on the remote Ubuntu host to evaluate explicit
  service postconditions.

The helper scripts provide observation and verification only. They do not
authorize or perform deployment mutations.