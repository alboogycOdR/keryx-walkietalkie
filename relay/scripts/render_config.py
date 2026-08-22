#!/usr/bin/env python3
"""Render relay config templates from a dotenv file.

LiveKit and coturn do not interpolate ${VAR} in their own config files.
Caddy does (Caddyfile), so it is left as-is. This script is the single
substitution step before `docker compose up`.

Usage:
    python scripts/render_config.py --env .env
    python scripts/render_config.py --env .env.example --out generated
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

PLACEHOLDER = re.compile(r"\$\{([A-Z][A-Z0-9_]*)\}")


def parse_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip()
        if (value.startswith('"') and value.endswith('"')) or (
            value.startswith("'") and value.endswith("'")
        ):
            value = value[1:-1]
        values[key] = value
    return values


def render(template: str, values: dict[str, str], source: Path) -> str:
    missing: list[str] = []

    def repl(match: re.Match[str]) -> str:
        key = match.group(1)
        if key not in values:
            missing.append(key)
            return match.group(0)
        return values[key]

    rendered = PLACEHOLDER.sub(repl, template)
    if missing:
        uniq = ", ".join(sorted(set(missing)))
        raise SystemExit(f"[render] {source}: missing env vars: {uniq}")
    leftover = PLACEHOLDER.findall(rendered)
    if leftover:
        raise SystemExit(f"[render] {source}: unsubstituted placeholders: {leftover}")
    return rendered


def display_write_path(dest: Path, root: Path) -> str:
    """Human-readable dest for the write log.

    `validate.ps1` / `validate.sh` render into $TEMP / $TMPDIR so they cannot
    clobber `relay/generated/`. `Path.relative_to` raises ValueError when dest
    is outside `root`; fall back to the absolute path instead of crashing.
    """
    try:
        return str(dest.relative_to(root))
    except ValueError:
        return str(dest)


def main() -> int:
    here = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--env",
        type=Path,
        default=here / ".env.example",
        help="dotenv file (default: relay/.env.example)",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=here / "generated",
        help="output directory (default: relay/generated)",
    )
    args = parser.parse_args()

    env_path = args.env if args.env.is_absolute() else here / args.env
    out_dir = args.out if args.out.is_absolute() else here / args.out
    if not env_path.is_file():
        print(f"[render] env file not found: {env_path}", file=sys.stderr)
        return 1

    values = parse_env(env_path)
    # Allow the process environment to override the file (CI / systemd).
    for key in list(values):
        if key in os.environ and os.environ[key]:
            values[key] = os.environ[key]

    out_dir.mkdir(parents=True, exist_ok=True)
    mapping = {
        here / "livekit.yaml.tmpl": out_dir / "livekit.yaml",
        here / "turnserver.conf.tmpl": out_dir / "turnserver.conf",
    }
    for src, dest in mapping.items():
        dest.write_text(render(src.read_text(encoding="utf-8"), values, src), encoding="utf-8")
        print(f"[render] wrote {display_write_path(dest, here)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
