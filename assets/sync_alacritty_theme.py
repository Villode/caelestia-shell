#!/usr/bin/env python3
"""Keep Alacritty colours + glass opacity in sync with Caelestia scheme/transparency."""

from __future__ import annotations

import fcntl
import glob
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path


def hex_color(value: str) -> str:
    """Normalize to Alacritty #RRGGBB form."""
    v = value.strip().removeprefix("0x").removeprefix("0X").removeprefix("#")
    if re.fullmatch(r"[0-9A-Fa-f]{6}", v):
        return f"#{v.upper()}"
    return value


PALETTES = {
    "light": {
        "primary": {"background": "#F7F9FC", "foreground": "#1F2937"},
        "normal": {
            "black": "#374151",
            "red": "#B42318",
            "green": "#16794A",
            "yellow": "#8A5700",
            "blue": "#175CD3",
            "magenta": "#7A3E9D",
            "cyan": "#0E7490",
            "white": "#D0D5DD",
        },
        "bright": {
            "black": "#667085",
            "red": "#D92D20",
            "green": "#039855",
            "yellow": "#B54708",
            "blue": "#1570EF",
            "magenta": "#9333EA",
            "cyan": "#0891B2",
            "white": "#FFFFFF",
        },
    },
    "dark": {
        "primary": {"background": "#2E3440", "foreground": "#D8DEE9"},
        "normal": {
            "black": "#3B4252",
            "red": "#BF616A",
            "green": "#A3BE8C",
            "yellow": "#EBCB8B",
            "blue": "#81A1C1",
            "magenta": "#B48EAD",
            "cyan": "#88C0D0",
            "white": "#E5E9F0",
        },
        "bright": {
            "black": "#4C566A",
            "red": "#BF616A",
            "green": "#A3BE8C",
            "yellow": "#EBCB8B",
            "blue": "#81A1C1",
            "magenta": "#B48EAD",
            "cyan": "#8FBCBB",
            "white": "#ECEFF4",
        },
    },
}

ASSIGNMENT = re.compile(
    r"^(\s*)([A-Za-z0-9_-]+)(\s*=\s*)"
    r'(?:(?:"(?:\\.|[^"])*")|(?:\'(?:\\.|[^\'])*\')|(?:[^#]*?))'
    r"(\s*(?:#.*)?)$"
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

DEFAULT_TOML = """\
# Managed by Villode / Caelestia (sync_alacritty_theme.py).
# Colours and window.opacity follow scheme + Settings transparency.

[general]
live_config_reload = true

[window]
opacity = 1.0
blur = false
padding.x = 10
padding.y = 8

[font]
size = 11.0

[colors.primary]
background = "#2E3440"
foreground = "#D8DEE9"

[colors.normal]
black = "#3B4252"
red = "#BF616A"
green = "#A3BE8C"
yellow = "#EBCB8B"
blue = "#81A1C1"
magenta = "#B48EAD"
cyan = "#88C0D0"
white = "#E5E9F0"

[colors.bright]
black = "#4C566A"
red = "#BF616A"
green = "#A3BE8C"
yellow = "#EBCB8B"
blue = "#81A1C1"
magenta = "#B48EAD"
cyan = "#8FBCBB"
white = "#ECEFF4"
"""


def update_line(line: str, value: str) -> str:
    match = ASSIGNMENT.match(line)
    if match is None:
        return line
    indent, key, separator, suffix = match.groups()
    if re.fullmatch(r"-?\d+(\.\d+)?", value) or value in ("true", "false"):
        return f"{indent}{key}{separator}{value}{suffix}"
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


def config_home() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))


def state_home() -> Path:
    return Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state"))


def runtime_dir() -> Path:
    return Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))


def load_json(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError, TypeError, ValueError):
        return {}


def resolve_mode(cli_mode: str) -> str:
    if cli_mode in PALETTES:
        return cli_mode
    scheme = load_json(state_home() / "caelestia" / "scheme.json")
    mode = str(scheme.get("mode") or "").lower()
    return mode if mode in PALETTES else "dark"


def resolve_opacity() -> float:
    """Match shell surface alpha: appearance.transparency.base when enabled."""
    shell = load_json(config_home() / "caelestia" / "shell.json")
    appearance = shell.get("appearance") if isinstance(shell.get("appearance"), dict) else {}
    transparency = appearance.get("transparency") if isinstance(appearance.get("transparency"), dict) else {}
    enabled = bool(transparency.get("enabled", False))
    if not enabled:
        return 1.0
    try:
        base = float(transparency.get("base", 0.85))
    except (TypeError, ValueError):
        base = 0.85
    # Same clamp as Colours.qml surface layer.
    return max(0.25, min(1.0, base))


def scheme_primary_override(mode: str) -> dict[str, str]:
    scheme = load_json(state_home() / "caelestia" / "scheme.json")
    colours = scheme.get("colours") if isinstance(scheme.get("colours"), dict) else {}
    out: dict[str, str] = {}
    bg = colours.get("surface") or colours.get("background")
    fg = colours.get("onSurface") or colours.get("onBackground")
    if isinstance(bg, str) and re.fullmatch(r"[0-9A-Fa-f]{6}", bg):
        out["background"] = hex_color(bg)
    if isinstance(fg, str) and re.fullmatch(r"[0-9A-Fa-f]{6}", fg):
        out["foreground"] = hex_color(fg)
    if not out:
        return {}
    base = {k: hex_color(v) for k, v in PALETTES[mode]["primary"].items()}
    base.update(out)
    return base


def ensure_config(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        return
    path.write_text(DEFAULT_TOML, encoding="utf-8")


def write_atomic(target: Path, text: str, file_mode: int) -> None:
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
            temporary.write(text)
            temporary.flush()
            os.fsync(temporary.fileno())
        os.chmod(temporary_name, file_mode)
        os.replace(temporary_name, target)
    finally:
        if temporary_name:
            Path(temporary_name).unlink(missing_ok=True)


def normalize_palette(mode: str) -> dict[str, dict[str, str]]:
    palette: dict[str, dict[str, str]] = {}
    for group, colors in PALETTES[mode].items():
        palette[group] = {k: hex_color(v) for k, v in colors.items()}
    primary_override = scheme_primary_override(mode)
    if primary_override:
        palette["primary"] = primary_override
    return palette


def update_config(path: Path, mode: str, opacity: float) -> dict[str, str]:
    """Rewrite alacritty.toml; return IPC option strings to push live."""
    blur = opacity < 0.999
    lock_path = path.parent / ".villode-alacritty-theme.lock"
    lock_fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
    with os.fdopen(lock_fd, "r+", encoding="utf-8") as lock_file:
        fcntl.flock(lock_file, fcntl.LOCK_EX)

        target = path.resolve() if path.is_symlink() else path
        try:
            original_mode = stat.S_IMODE(target.stat().st_mode)
            lines = target.read_text(encoding="utf-8").splitlines()
        except OSError:
            return {}

        palette = normalize_palette(mode)
        section = ""
        output: list[str] = []
        saw = {
            "window": False,
            "opacity": False,
            "blur": False,
            "general": False,
            "live_config_reload": False,
        }

        def flush_window_defaults() -> None:
            if not saw["opacity"]:
                output.append(f"opacity = {opacity:.2f}")
                saw["opacity"] = True
            if not saw["blur"]:
                output.append(f"blur = {'true' if blur else 'false'}")
                saw["blur"] = True

        for line in lines:
            stripped = line.strip()
            if stripped.startswith("[") and stripped.endswith("]"):
                if section == "window":
                    flush_window_defaults()
                section = stripped[1:-1]
                if section == "window":
                    saw["window"] = True
                elif section == "general":
                    saw["general"] = True
                output.append(line)
                continue

            key = line.split("=", 1)[0].strip() if "=" in line else ""
            if section == "window" and key == "opacity":
                line = update_line(line, f"{opacity:.2f}")
                saw["opacity"] = True
            elif section == "window" and key == "blur":
                line = update_line(line, "true" if blur else "false")
                saw["blur"] = True
            elif section == "general" and key == "live_config_reload":
                line = update_line(line, "true")
                saw["live_config_reload"] = True
            else:
                group = section.removeprefix("colors.") if section.startswith("colors.") else ""
                if group in palette and key in palette[group]:
                    line = update_line(line, palette[group][key])
            output.append(line)

        if section == "window":
            flush_window_defaults()

        if not saw["window"]:
            output.extend(
                [
                    "",
                    "[window]",
                    f"opacity = {opacity:.2f}",
                    f"blur = {'true' if blur else 'false'}",
                    "padding.x = 10",
                    "padding.y = 8",
                ]
            )
            saw["opacity"] = True
            saw["blur"] = True

        if not saw["general"]:
            output = ["[general]", "live_config_reload = true", ""] + output
        elif not saw["live_config_reload"]:
            # Insert after [general] header if present.
            fixed: list[str] = []
            inserted = False
            for line in output:
                fixed.append(line)
                if not inserted and line.strip() == "[general]":
                    fixed.append("live_config_reload = true")
                    inserted = True
            output = fixed

        write_atomic(target, "\n".join(output) + "\n", original_mode)

    primary = palette["primary"]
    ipc = {
        "window.opacity": f"{opacity:.2f}",
        "window.blur": "true" if blur else "false",
        "colors.primary.background": f'"{primary["background"]}"',
        "colors.primary.foreground": f'"{primary["foreground"]}"',
    }
    for group in ("normal", "bright"):
        for key, value in palette[group].items():
            ipc[f"colors.{group}.{key}"] = f'"{value}"'
    return ipc


def apply_live(ipc: dict[str, str]) -> None:
    """Push config into every running Alacritty (file reload is unreliable for existing windows)."""
    if not ipc or not shutil.which("alacritty"):
        return
    socks = sorted(glob.glob(str(runtime_dir() / "Alacritty*.sock")))
    if not socks:
        return
    options = [f"{k}={v}" for k, v in ipc.items()]
    for sock in socks:
        try:
            subprocess.run(
                ["alacritty", "msg", "-s", sock, "config", "-w", "-1", *options],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=3,
            )
        except (OSError, subprocess.TimeoutExpired):
            continue


def main() -> int:
    cli_mode = sys.argv[1] if len(sys.argv) > 1 else ""
    preferred = list(sys.argv[2:])
    if cli_mode in ("--opacity", "opacity"):
        mode = resolve_mode("")
        preferred = list(sys.argv[2:])
    else:
        mode = resolve_mode(cli_mode)

    term = selected_terminal(preferred if preferred else ["alacritty"])
    if term != "alacritty":
        return 0

    path = config_home() / "alacritty" / "alacritty.toml"
    ensure_config(path)
    if not path.exists():
        return 0

    opacity = resolve_opacity()
    ipc = update_config(path, mode, opacity)
    apply_live(ipc)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
