#!/usr/bin/env python3
"""Keep Alacritty's ANSI palette readable in Caelestia light and dark modes."""

import os
import sys
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


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode not in PALETTES:
        return 2
    path = Path.home() / ".config" / "alacritty" / "alacritty.toml"
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return 0

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
                replacement = f'{key} = "{value}"'
                changed |= stripped != replacement
                line = replacement
        output.append(line)

    if changed:
        temporary = path.with_suffix(".toml.tmp")
        temporary.write_text("\n".join(output) + "\n", encoding="utf-8")
        os.replace(temporary, path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
