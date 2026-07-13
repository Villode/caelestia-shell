#!/usr/bin/env bash
# Remove Villode cursor shake-to-find (user-local).
set -euo pipefail

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
state_home="${XDG_STATE_HOME:-$HOME/.local/state}/villode-cursor"
runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

if [[ -f "$runtime/villode-cursor-shake.pid" ]]; then
    old="$(cat "$runtime/villode-cursor-shake.pid" 2>/dev/null || true)"
    [[ -n "$old" ]] && kill "$old" 2>/dev/null || true
    rm -f "$runtime/villode-cursor-shake.pid" "$runtime/villode-cursor-shake.force"
fi
# Best-effort kill by name without self-matching the uninstaller
python3 - <<'PY' 2>/dev/null || true
import os, signal
from pathlib import Path
for p in Path("/proc").iterdir():
    if not p.name.isdigit():
        continue
    try:
        args = (p / "cmdline").read_bytes().split(b"\0")
    except Exception:
        continue
    if args and args[0].startswith(b"python") and any(
        Path(a.decode(errors="ignore")).name == "villode-cursor-shake" for a in args if a
    ):
        try:
            os.kill(int(p.name), signal.SIGTERM)
        except ProcessLookupError:
            pass
PY

rm -f "$HOME/.local/bin/villode-cursor-shake"
rm -rf "$config_home/villode-cursor"
rm -rf "$data_home/villode-cursor"
rm -rf "$state_home"
rm -f "$config_home/villode-hyprland/cursor.conf"
rm -f "$config_home/hypr/conf.d/villode-cursor.conf"

# Leave hyprland source lines in place (harmless if file missing); strip if present
for conf in \
    "$config_home/villode-hyprland/hyprland.conf" \
    "$config_home/hypr/hyprland.conf"; do
    [[ -f "$conf" ]] || continue
    # Remove our block comments + source lines
    tmp="$(mktemp)"
    awk '
        /# Villode cursor shake-to-find/ { skip=1; next }
        skip && /^source = .*cursor/ { skip=0; next }
        skip && NF==0 { skip=0; next }
        skip { next }
        { print }
    ' "$conf" > "$tmp" && mv "$tmp" "$conf"
done

hyprctl keyword cursor:invisible false >/dev/null 2>&1 || true
hyprctl keyword cursor:zoom_factor 1 >/dev/null 2>&1 || true

echo "Villode 指针放大已卸载。"
