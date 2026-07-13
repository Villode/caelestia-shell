#!/usr/bin/env bash
# Install Villode cursor shake-to-find (user-local).
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
no_start=false
no_hyprland=false

while (($#)); do
    case "$1" in
        --no-start) no_start=true ;;
        --no-hyprland) no_hyprland=true ;;
        -h|--help)
            echo "用法：./install.sh [--no-start] [--no-hyprland]"
            exit 0
            ;;
        *) echo "未知选项：$1" >&2; exit 64 ;;
    esac
    shift
done

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
state_home="${XDG_STATE_HOME:-$HOME/.local/state}/villode-cursor"

install -Dm755 "$repo_dir/villode-cursor-shake" "$HOME/.local/bin/villode-cursor-shake"
install -Dm644 "$repo_dir/shake.conf" "$config_home/villode-cursor/shake.conf"
if [[ -f "$repo_dir/assets/left_ptr.svg" ]]; then
    install -Dm644 "$repo_dir/assets/left_ptr.svg" "$data_home/villode-cursor/left_ptr.svg"
fi

# Rewrite theme_svg path in shake.conf to the installed location
if [[ -f "$data_home/villode-cursor/left_ptr.svg" ]]; then
    if grep -q '^theme_svg' "$config_home/villode-cursor/shake.conf"; then
        sed -i "s|^theme_svg = .*|theme_svg = $data_home/villode-cursor/left_ptr.svg|" \
            "$config_home/villode-cursor/shake.conf"
    else
        printf '\ntheme_svg = %s\n' "$data_home/villode-cursor/left_ptr.svg" \
            >> "$config_home/villode-cursor/shake.conf"
    fi
fi

install -d -m700 "$state_home"
printf '%s\n' "$(date -Iseconds 2>/dev/null || date)" > "$state_home/installed-at"
if git -C "$(cd "$repo_dir/../.." && pwd)" rev-parse HEAD >/dev/null 2>&1; then
    git -C "$(cd "$repo_dir/../.." && pwd)" rev-parse HEAD > "$state_home/revision" || true
fi

wire_hyprland_conf() {
    local conf="$1"
    local cursor_conf="$2"
    local conf_dir
    conf_dir="$(dirname -- "$conf")"
    [[ -f "$conf" ]] || return 0
    mkdir -p "$conf_dir"
    install -Dm644 "$repo_dir/cursor.conf" "$cursor_conf"
    if ! grep -Fq 'villode-cursor' "$conf" 2>/dev/null &&
       ! grep -Fq "$cursor_conf" "$conf" 2>/dev/null; then
        {
            printf '\n# Villode cursor shake-to-find\n'
            printf 'source = %s\n' "$cursor_conf"
        } >> "$conf"
    fi
}

if ! $no_hyprland; then
    # Independent Villode session
    if [[ -f "$config_home/villode-hyprland/hyprland.conf" ]]; then
        wire_hyprland_conf \
            "$config_home/villode-hyprland/hyprland.conf" \
            "$config_home/villode-hyprland/cursor.conf"
    fi
    # Legacy ~/.config/hypr conf.d drop-in
    if [[ -d "$config_home/hypr/conf.d" || -f "$config_home/hypr/hyprland.conf" ]]; then
        mkdir -p "$config_home/hypr/conf.d"
        install -Dm644 "$repo_dir/cursor.conf" "$config_home/hypr/conf.d/villode-cursor.conf"
        if [[ -f "$config_home/hypr/hyprland.conf" ]] &&
           ! grep -Fq 'villode-cursor.conf' "$config_home/hypr/hyprland.conf" 2>/dev/null; then
            printf '\n# Villode cursor shake-to-find\nsource = %s\n' \
                "$config_home/hypr/conf.d/villode-cursor.conf" \
                >> "$config_home/hypr/hyprland.conf"
        fi
    fi
fi

# Restart daemon
if [[ -f "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/villode-cursor-shake.pid" ]]; then
    old="$(cat "${XDG_RUNTIME_DIR}/villode-cursor-shake.pid" 2>/dev/null || true)"
    if [[ -n "$old" ]]; then
        kill "$old" 2>/dev/null || true
    fi
fi
if ! $no_start; then
    nohup "$HOME/.local/bin/villode-cursor-shake" \
        >/tmp/villode-cursor-shake.stdout 2>&1 &
    disown || true
fi

echo "Villode 指针放大已安装：villode-cursor-shake"
echo "  快捷键 Super+Shift+C 可手动放大；用力左右晃动指针可定位。"
