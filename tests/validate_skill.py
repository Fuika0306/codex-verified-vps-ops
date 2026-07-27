#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / "skills" / "verified-vps-ops"

REQUIRED_FILES = {
    "SKILL.md",
    "agents/openai.yaml",
    "references/runbooks.md",
    "scripts/remote-preflight.ps1",
    "scripts/remote-preflight.sh",
    "scripts/verify-service.sh",
}


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


def read_utf8(path: Path) -> str:
    data = path.read_bytes()
    if data.startswith(b"\xef\xbb\xbf"):
        fail(f"UTF-8 BOM is not allowed: {path.relative_to(ROOT)}")
    if b"\r\n" in data:
        fail(f"CRLF is not allowed: {path.relative_to(ROOT)}")
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError as exc:
        fail(f"invalid UTF-8 in {path.relative_to(ROOT)}: {exc}")


def parse_frontmatter(text: str) -> dict[str, str]:
    if not text.startswith("---\n"):
        fail("SKILL.md must start with YAML frontmatter")
    marker = "\n---\n"
    end = text.find(marker, 4)
    if end < 0:
        fail("SKILL.md frontmatter is not closed")
    frontmatter = text[4:end]
    body = text[end + len(marker) :]
    if not body.strip():
        fail("SKILL.md body is empty")

    result: dict[str, str] = {}
    for line in frontmatter.splitlines():
        if not line.strip():
            continue
        key, separator, value = line.partition(":")
        if not separator or not key.strip() or not value.strip():
            fail(f"unsupported frontmatter line: {line!r}")
        key = key.strip()
        if key in result:
            fail(f"duplicate frontmatter key: {key}")
        result[key] = value.strip()
    return result


def scan_text(path: Path, text: str) -> None:
    checks = {
        "template residue": r"\[TODO|TODO:|FIXME|Structuring This Skill",
        "private key": r"BEGIN (?:RSA|OPENSSH|EC) PRIVATE KEY",
        "AWS access key": r"AKIA[0-9A-Z]{16}",
        "GitHub token": r"ghp_[A-Za-z0-9]{20,}",
        "Slack token": r"xox[baprs]-",
        "Discord webhook": r"discord(?:app)?\.com/api/webhooks/[0-9]+/",
        "literal IPv4": r"\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b",
        "personal Windows home": r"[A-Za-z]:\\Users\\[^\\\s]+",
        "personal Unix home": r"(?:/home|/Users)/[^/\s]+",
        "trailing whitespace": r"[ \t]+$",
    }
    for label, pattern in checks.items():
        if re.search(pattern, text, flags=re.IGNORECASE | re.MULTILINE):
            fail(f"{label} found in {path.relative_to(ROOT)}")


def main() -> int:
    if not SKILL.is_dir():
        fail("skills/verified-vps-ops is missing")

    for path in SKILL.rglob("*"):
        if path.is_symlink():
            fail(f"symlinks are not allowed: {path.relative_to(ROOT)}")

    actual_files = {
        path.relative_to(SKILL).as_posix()
        for path in SKILL.rglob("*")
        if path.is_file()
    }
    missing = sorted(REQUIRED_FILES - actual_files)
    extra = sorted(actual_files - REQUIRED_FILES)
    if missing:
        fail(f"missing required files: {', '.join(missing)}")
    if extra:
        fail(f"unexpected files in installable Skill: {', '.join(extra)}")

    texts: dict[str, str] = {}
    for relative in sorted(REQUIRED_FILES):
        path = SKILL / relative
        text = read_utf8(path)
        texts[relative] = text
        scan_text(path, text)

    frontmatter = parse_frontmatter(texts["SKILL.md"])
    if set(frontmatter) != {"name", "description"}:
        fail("SKILL.md frontmatter must contain only name and description")
    if frontmatter["name"] != "verified-vps-ops":
        fail("frontmatter name must be verified-vps-ops")
    if len(frontmatter["description"]) < 120:
        fail("frontmatter description is too short for reliable triggering")
    if len(texts["SKILL.md"].splitlines()) >= 500:
        fail("SKILL.md must remain under 500 lines")

    ui = texts["agents/openai.yaml"]
    if not re.search(r'^interface:\s*$', ui, flags=re.MULTILINE):
        fail("agents/openai.yaml lacks interface")
    short_match = re.search(
        r'^\s{2}short_description:\s+"([^"]+)"\s*$',
        ui,
        flags=re.MULTILINE,
    )
    if not short_match or not 25 <= len(short_match.group(1)) <= 64:
        fail("short_description must contain 25-64 characters")
    if "$verified-vps-ops" not in ui:
        fail("default_prompt must explicitly mention $verified-vps-ops")

    if "## Contents" not in texts["references/runbooks.md"]:
        fail("long runbook must include a table of contents")
    if "StrictHostKeyChecking=yes" not in texts["references/runbooks.md"]:
        fail("runbook must preserve strict SSH host-key checking")
    if "--include-journal" not in texts["scripts/verify-service.sh"]:
        fail("journal output must remain explicit opt-in")
    if "StrictHostKeyChecking=yes" not in texts["scripts/remote-preflight.ps1"]:
        fail("preflight must require strict SSH host-key checking")
    if "--ignore-garbage" not in texts["scripts/remote-preflight.ps1"]:
        fail("PowerShell native-pipe CRLF handling is missing")

    public_text_paths = [
        ROOT / "README.md",
        ROOT / "LICENSE",
        ROOT / ".gitignore",
        ROOT / ".gitattributes",
        ROOT / ".github" / "workflows" / "validate.yml",
        ROOT / "tests" / "test_helpers.sh",
        ROOT / "tests" / "test_remote_preflight.ps1",
    ]
    for path in public_text_paths:
        if not path.is_file():
            fail(f"missing repository file: {path.relative_to(ROOT)}")
        scan_text(path, read_utf8(path))

    workflow = read_utf8(ROOT / ".github" / "workflows" / "validate.yml")
    pinned_actions = {
        "actions/checkout": "d23441a48e516b6c34aea4fa41551a30e30af803",
        "actions/setup-python": "ece7cb06caefa5fff74198d8649806c4678c61a1",
    }
    for action, commit in pinned_actions.items():
        if f"uses: {action}@{commit}" not in workflow:
            fail(f"GitHub Action must be pinned to the reviewed commit: {action}")
    readme = read_utf8(ROOT / "README.md")
    if "Fuika0306/codex-verified-vps-ops" not in readme:
        fail("README lacks the published GitHub repository name")
    if "OWNER/codex-verified-vps-ops" in readme:
        fail("README still contains the unpublished OWNER placeholder")
    if "skills/verified-vps-ops" not in readme:
        fail("README lacks the GitHub install path")

    print("PASS: public Skill structure and safety checks")
    for relative in sorted(REQUIRED_FILES):
        digest = hashlib.sha256((SKILL / relative).read_bytes()).hexdigest()
        print(f"{digest}  skills/verified-vps-ops/{relative}")
    return 0


if __name__ == "__main__":
    sys.exit(main())