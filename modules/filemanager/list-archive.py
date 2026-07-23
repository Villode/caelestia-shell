#!/usr/bin/env python3
"""List archive members as JSON for QML file manager (7z l -ba)."""
from __future__ import annotations

import json
import re
import subprocess
import sys

LINE_RE = re.compile(
    r"^(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s+([D.][\w.]+)\s+(\d+)\s+(\d+)\s+(.+)$"
)


def list_archive(path: str) -> list[dict]:
    try:
        raw = subprocess.check_output(
            ["7z", "l", "-ba", "--", path],
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
        )
    except FileNotFoundError:
        print(json.dumps({"ok": False, "error": "7z not found", "items": []}, ensure_ascii=False))
        return []
    except subprocess.CalledProcessError as e:
        msg = (e.output or str(e))[:200]
        print(json.dumps({"ok": False, "error": msg, "items": []}, ensure_ascii=False))
        return []

    items: list[dict] = []
    for line in raw.splitlines():
        line = line.rstrip("\r")
        m = LINE_RE.match(line)
        if not m:
            continue
        attr = m.group(2) or ""
        size = int(m.group(3) or 0)
        name = (m.group(5) or "").strip()
        if not name:
            continue
        is_dir = attr.startswith("D")
        items.append({"path": name, "name": name, "isDir": is_dir, "size": size})

    print(json.dumps({"ok": True, "error": "", "items": items}, ensure_ascii=False))
    return items


def main() -> int:
    if len(sys.argv) < 2:
        print(json.dumps({"ok": False, "error": "usage: list-archive.py <archive>", "items": []}))
        return 2
    list_archive(sys.argv[1])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
