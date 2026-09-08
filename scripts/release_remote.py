#!/usr/bin/env python3
"""release_remote.py — upload a build artefact to Gofile and post the
download link to Telegram via a bot.

Same three-call flow as scripts/notify.py's telegram channel, extended to
carry a file rather than just a status line: no CI artefact storage needed
for shipping something like a debug/release APK to a phone. See
docs/gofile-telegram-delivery.md for the full spec and pitfalls (notably:
never set parse_mode, and Gofile links expire in ~10 days -- this is a
handoff channel, not a release channel).

Credentials come ONLY from environment variables (TELEGRAM_BOT_TOKEN,
TELEGRAM_CHAT_ID) -- same convention as scripts/notify.py. Never hardcode,
never write to a file in this repo (the secret-scan pre-commit hook will
refuse it, and should).

Usage:
    python scripts/release_remote.py [path-to-file]

Defaults to build/app/outputs/flutter-apk/app-release.apk if no path given.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

DEFAULT_FILE = "build/app/outputs/flutter-apk/app-release.apk"


def safe(fn):
    try:
        return fn()
    except Exception:
        return None


def git_short_sha() -> str | None:
    return safe(
        lambda: subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    )


def git_last_subject() -> str | None:
    return safe(
        lambda: subprocess.run(
            ["git", "log", "-1", "--pretty=%s"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    )


def pick_gofile_server() -> str:
    with urllib.request.urlopen("https://api.gofile.io/servers", timeout=15) as resp:
        data = json.loads(resp.read())
    return data["data"]["servers"][0]["name"]


def upload_to_gofile(server: str, file_path: Path) -> str:
    boundary = "----release-remote-boundary"
    with open(file_path, "rb") as f:
        file_bytes = f.read()
    body = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="file"; filename="{file_path.name}"\r\n'
        f"Content-Type: application/octet-stream\r\n\r\n"
    ).encode() + file_bytes + f"\r\n--{boundary}--\r\n".encode()
    req = urllib.request.Request(
        f"https://{server}.gofile.io/contents/uploadfile",
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=180) as resp:
        data = json.loads(resp.read())
    if data.get("status") != "ok":
        raise RuntimeError(f"Gofile upload failed: {data}")
    return data["data"]["downloadPage"]


def send_telegram_message(token: str, chat_id: str, text: str) -> None:
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{token}/sendMessage",
        data=json.dumps(
            {"chat_id": chat_id, "text": text, "disable_web_page_preview": False}
        ).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    # Deliberately no parse_mode -- Telegram legacy Markdown chokes on any
    # unmatched _ / * / backtick in a commit subject and aborts the send
    # ("Can't find end of the entity"); plain text auto-links URLs anyway.
    with urllib.request.urlopen(req, timeout=15) as resp:
        result = json.loads(resp.read())
    if not result.get("ok"):
        raise RuntimeError(f"Telegram send failed: {result}")


def main(argv: list[str]) -> int:
    file_path = Path(argv[1] if len(argv) > 1 else DEFAULT_FILE)
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    chat_id = os.environ.get("TELEGRAM_CHAT_ID")

    if not token or not chat_id:
        print(
            "TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID not set in the environment. "
            "Set them for this session and re-run -- never hardcode them into a file.",
            file=sys.stderr,
        )
        return 1
    if not file_path.exists():
        print(f"File not found: {file_path}", file=sys.stderr)
        return 1

    server = pick_gofile_server()
    url = upload_to_gofile(server, file_path)

    sha = git_short_sha()
    subject = git_last_subject()
    size_mb = file_path.stat().st_size / 1024 / 1024

    lines = [f"Build ready: {file_path.name}"]
    if subject:
        lines.append(subject)
    lines.append(f"Size: {size_mb:.1f} MB")
    if sha:
        lines.append(f"Commit: {sha}")
    lines.append(url)
    lines.append("Link expires in ~10 days.")
    text = "\n\n".join(lines)

    send_telegram_message(token, chat_id, text)
    print(f"Sent: {url}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
