#!/usr/bin/env python3
"""Keep Alacritty's ANSI palette readable in Caelestia light and dark modes."""

import fcntl
import os
import re
import shutil
import stat
import sys
import tempfile
from pathlib import Path


PALETTES = {
    "light": {
        "primary": {"background": "0xF7F9FC", "foreground": "0x1F2937"},
        "normal": {
            "black": "0x374151", "red": "0xB42318", "green": "0x16794A",
            "yellow": "0x8A5700", "blue": "0x175CD3", "magenta": "0x7A3E9D",
            "cyan": "0x0E7490", "white": "0xD0D5DD",
        },
        "bright": {
            "black": "0x667085", "red": "0xD92D20", "green": "0x039855",
            "yellow": "0xB54708", "blue": "0x1570EF", "magenta": "0x9333EA",
            "cyan": "0x0891B2", "white": "0xFFFFFF",
        },
    },
    "dark": {
        "primary": {"background": "0x2E3440", "foreground": "0xD8DEE9"},
        "normal": {
            "black": "0x3B4252", "red": "0xBF616A", "green": "0xA3BE8C",
            "yellow": "0xEBCB8B", "blue": "0x81A1C1", "magenta": "0xB48EAD",
            "cyan": "0x88C0D0", "white": "0xE5E9F0",
        },
        "bright": {
            "black": "0x4C566A", "red": "0xBF616A", "green": "0xA3BE8C",
            "yellow": "0xEBCB8B", "blue": "0x81A1C1", "magenta": "0xB48EAD",
            "cyan": "0x8FBCBB", "white": "0xECEFF4",
        },
    },
}

ASSIGNMENT = re.compile(
    r'^(\s*)([A-Za-z0-9_-]+)(\s*=\s*)'
    r'(?:(?:"(?:\\.|[^"])*")|(?:\'(?:\\.|[^\'])*\')|(?:[^#]*?))'
    r'(\s*(?:#.*)?)$'
)
TERMINAL_FALLBACKS = (
    "alacritty",
    "foot",
    "kitty",
    "konsole",
    "wezterm",
    "gnome-terminal",
    "kgx",
    "xfce4-terminal",
    "xterm",
)


def update_line(line: str, value: str) -> str:
    match = ASSIGNMENT.match(line)
    if match is None:
        return line
    indent, key, separator, suffix = match.groups()
    return f'{indent}{key}{separator}"{value}"{suffix}'


def selected_terminal(preferred: list[str]) -> str:
    for item in preferred:
        name = Path(item).name
        if name in TERMINAL_FALLBACKS and shutil.which(name):
            return name
    if preferred and shutil.which(preferred[0]):
        return Path(preferred[0]).name
    for candidate in TERMINAL_FALLBACKS:
        if shutil.which(candidate):
            return candidate
    return ""


def update_config(path: Path, mode: str) -> None:
    lock_path = path.parent / ".villode-alacritty-theme.lock"
    lock_fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
    with os.fdopen(lock_fd, "r+", encoding="utf-8") as lock_file:
        fcntl.flock(lock_file, fcntl.LOCK_EX)

        # Replace the symlink target rather than the link itself. This keeps
        # dotfile-managed Alacritty configurations connected to their source.
        target = path.resolve() if path.is_symlink() else path
        try:
            original_mode = stat.S_IMODE(target.stat().st_mode)
            lines = target.read_text(encoding="utf-8").splitlines()
        except OSError:
            return

        section = ""
        palette = PALETTES[mode]
        changed = False
        output = []
        for line in lines:
            stripped = line.strip()
            if stripped.startswith("[") and stripped.endswith("]"):
                section = stripped[1:-1]
            group = section.removeprefix("colors.") if section.startswith("colors.") else ""
            if group in palette and "=" in line:
                key = line.split("=", 1)[0].strip()
                value = palette[group].get(key)
                if value is not None:
                    replacement = update_line(line, value)
                    changed |= replacement != line
                    line = replacement
            output.append(line)

        if not changed:
            return

        temporary_name = ""
        try:
            with tempfile.NamedTemporaryFile(
                mode="w",
                encoding="utf-8",
                dir=target.parent,
                prefix=f".{target.name}.",
                suffix=".tmp",
                delete=False,
            ) as temporary:
                temporary_name = temporary.name
                temporary.write("\n".join(output) + "\n")
                temporary.flush()
                os.fsync(temporary.fileno())
            os.chmod(temporary_name, original_mode)
            os.replace(temporary_name, target)
        finally:
            if temporary_name:
                Path(temporary_name).unlink(missing_ok=True)


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode not in PALETTES:
        return 2
    if selected_terminal(sys.argv[2:]) != "alacritty":
        return 0
    path = Path.home() / ".config" / "alacritty" / "alacritty.toml"
    if not path.exists():
        return 0
    update_config(path, mode)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
