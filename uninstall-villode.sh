#!/usr/bin/env bash
set -euo pipefail

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
state_home="${XDG_STATE_HOME:-$HOME/.local/state}/villode-caelestia-shell"
config_dir="$config_home/quickshell/caelestia"
purge=false

if [[ "${1:-}" == "--purge" ]]; then
    purge=true
elif (($#)); then
    echo "用法：./uninstall-villode.sh [--purge]" >&2
    exit 64
fi

"$HOME/.local/bin/caelestia" shell -k >/dev/null 2>&1 || true

if [[ -f "$state_home/install-manifest.txt" ]]; then
    while IFS= read -r installed_file; do
        case "$installed_file" in
            "$HOME/.local/lib/"*) rm -f -- "$installed_file" ;;
        esac
    done < "$state_home/install-manifest.txt"
fi

if [[ -f "$HOME/.local/bin/caelestia" ]] &&
   grep -q 'Managed by Villode Caelestia Shell' "$HOME/.local/bin/caelestia" 2>/dev/null; then
    rm -f "$HOME/.local/bin/caelestia"
fi
if [[ -f "$HOME/.local/lib/caelestia/bin/qs" ]] &&
   grep -q 'Run the binary by its full `quickshell` name' \
       "$HOME/.local/lib/caelestia/bin/qs" 2>/dev/null; then
    rm -f "$HOME/.local/lib/caelestia/bin/qs"
    rmdir "$HOME/.local/lib/caelestia/bin" 2>/dev/null || true
fi

if [[ -f "$config_dir/.villode-managed" ]]; then
    rm -rf "$config_dir"
fi

if ! $purge && [[ -f "$state_home/original-backup" ]]; then
    original_backup="$(<"$state_home/original-backup")"
    if [[ -d "$original_backup" && ! -e "$config_dir" ]]; then
        mv "$original_backup" "$config_dir"
        echo "已恢复安装前的 Caelestia 用户副本：$config_dir"
    fi
fi

rm -rf "$state_home"
echo "Villode Caelestia Shell 已卸载。"
