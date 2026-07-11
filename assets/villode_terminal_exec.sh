#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: villode_terminal_exec.sh COUNT [TERMINAL_ARG ...] -- COMMAND [ARG ...]" >&2
    exit 64
}

[[ $# -ge 3 && "$1" =~ ^[0-9]+$ ]] || usage
terminal_count="$1"
shift
((terminal_count <= $#)) || usage

terminal=("${@:1:terminal_count}")
shift "$terminal_count"
[[ "${1:-}" == "--" ]] || usage
shift
(($#)) || usage
payload=("$@")

if ((${#terminal[@]} == 0)) || ! command -v "${terminal[0]}" >/dev/null 2>&1; then
    terminal=()
    for candidate in alacritty foot kitty konsole wezterm gnome-terminal kgx xfce4-terminal xterm; do
        if command -v "$candidate" >/dev/null 2>&1; then
            terminal=("$candidate")
            break
        fi
    done
fi

((${#terminal[@]})) || {
    echo "No supported terminal emulator is installed." >&2
    exit 69
}

has_arg() {
    local expected="$1" arg
    for arg in "${terminal[@]}"; do
        [[ "$arg" == "$expected" ]] && return 0
    done
    return 1
}

name="$(basename -- "${terminal[0]}")"
case "$name" in
    alacritty)
        has_arg -e || has_arg --command || terminal+=(--command)
        ;;
    konsole|xterm)
        has_arg -e || terminal+=(-e)
        ;;
    gnome-terminal|kgx)
        has_arg -- || terminal+=(--)
        ;;
    wezterm)
        has_arg start || terminal+=(start --)
        ;;
    xfce4-terminal)
        has_arg -x || terminal+=(-x)
        ;;
    # foot and kitty accept the command as positional arguments. Unknown
    # terminals retain the configured command unchanged for compatibility.
esac

exec "${terminal[@]}" "${payload[@]}"
