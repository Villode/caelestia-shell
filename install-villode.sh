#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_home="${XDG_CACHE_HOME:-$HOME/.cache}"
state_home="${XDG_STATE_HOME:-$HOME/.local/state}/villode-caelestia-shell"
config_dir="$config_home/quickshell/caelestia"
build_dir="$cache_home/villode-caelestia-shell/build"
with_deps=false
build_native=true
restart=true

usage() {
    cat <<'EOF'
用法：./install-villode.sh [选项]

选项：
  --with-deps         使用 Arch/AUR 包管理器安装缺失依赖
  --no-native-build   只部署 QML，使用系统现有 Caelestia 原生模块
  --no-restart        安装后不重启 Caelestia
  -h, --help          显示帮助
EOF
}

while (($#)); do
    case "$1" in
        --with-deps) with_deps=true ;;
        --no-native-build) build_native=false ;;
        --no-restart) restart=false ;;
        -h|--help) usage; exit 0 ;;
        *) echo "未知选项：$1" >&2; usage >&2; exit 64 ;;
    esac
    shift
done

install_dependencies() {
    local packages=(
        caelestia-shell caelestia-cli cmake ninja
        adwaita-icon-theme hicolor-icon-theme
    )
    local missing=()
    local repo_missing=()
    local aur_missing=()
    local pkg

    # Already-installed packages must not force an AUR RPC round-trip.
    # yay still queries aur.archlinux.org for --needed targets, and that can
    # fail on broken IPv6 even when every package is already present.
    if command -v pacman >/dev/null 2>&1; then
        for pkg in "${packages[@]}"; do
            if ! pacman -Q "$pkg" &>/dev/null; then
                missing+=("$pkg")
            fi
        done
    else
        missing=("${packages[@]}")
    fi

    if ((${#missing[@]} == 0)); then
        echo "系统依赖已齐全，跳过包管理器安装。"
        return 0
    fi

    # Prefer pacman for official-repo packages; only hit AUR for the rest.
    for pkg in "${missing[@]}"; do
        case "$pkg" in
            caelestia-shell|caelestia-cli) aur_missing+=("$pkg") ;;
            *) repo_missing+=("$pkg") ;;
        esac
    done

    if ((${#repo_missing[@]})) && command -v pacman >/dev/null 2>&1; then
        echo "通过 pacman 安装：${repo_missing[*]}"
        sudo pacman -S --needed --noconfirm "${repo_missing[@]}"
    fi

    # Recompute AUR targets after pacman in case a package was satisfied.
    aur_missing=()
    for pkg in caelestia-shell caelestia-cli; do
        if ! pacman -Q "$pkg" &>/dev/null; then
            aur_missing+=("$pkg")
        fi
    done

    if ((${#aur_missing[@]} == 0)); then
        echo "AUR 依赖已齐全，跳过 yay/paru。"
        return 0
    fi

    if ! command -v yay >/dev/null 2>&1 &&
       ! command -v paru >/dev/null 2>&1 &&
       command -v pacman >/dev/null 2>&1; then
        local bootstrap_dir
        echo "未检测到 yay 或 paru，正在安装 yay-bin……"
        sudo pacman -S --needed --noconfirm base-devel git
        bootstrap_dir="$(mktemp -d)"
        git clone --depth=1 https://aur.archlinux.org/yay-bin.git "$bootstrap_dir/yay-bin"
        (
            cd "$bootstrap_dir/yay-bin"
            makepkg -si --needed --noconfirm
        )
        rm -rf "$bootstrap_dir"
    fi

    echo "通过 AUR 安装：${aur_missing[*]}"
    if command -v yay >/dev/null 2>&1; then
        yay -S --needed "${aur_missing[@]}"
    elif command -v paru >/dev/null 2>&1; then
        paru -S --needed "${aur_missing[@]}"
    else
        echo "未找到 yay 或 paru，无法自动安装：${aur_missing[*]}" >&2
        return 1
    fi
}

if $with_deps; then
    echo "正在检查并补齐 Caelestia 构建与运行依赖……"
    install_dependencies
fi

if [[ ! -x /usr/bin/caelestia ]] || ! command -v qs >/dev/null 2>&1; then
    if $with_deps; then
        install_dependencies
    else
        echo "缺少 caelestia-cli 或 Quickshell。请先安装依赖，或使用 --with-deps。" >&2
        exit 69
    fi
fi

if $build_native; then
    for command_name in cmake ninja git; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            if $with_deps; then
                install_dependencies
                break
            fi
            echo "构建原生模块需要：$command_name" >&2
            exit 69
        fi
    done
fi

for path in assets components i18n modules services utils bin/caelestia-villode \
    bin/qs-villode shell.qml LICENSE UPSTREAM_VERSION; do
    [[ -e "$repo_dir/$path" ]] || { echo "源码不完整，缺少：$path" >&2; exit 66; }
done

mkdir -p "$state_home/backups" "$(dirname "$config_dir")"
if [[ -e "$config_dir" ]]; then
    backup_dir="$state_home/backups/caelestia-$(date +%Y%m%d-%H%M%S-%N)"
    mv "$config_dir" "$backup_dir"
    if [[ ! -f "$state_home/original-backup" ]]; then
        printf '%s\n' "$backup_dir" > "$state_home/original-backup"
    fi
    echo "现有 Caelestia 用户副本已备份到：$backup_dir"
fi

mkdir -p "$config_dir"
for directory in assets components i18n modules services utils; do
    cp -a "$repo_dir/$directory" "$config_dir/"
done
install -m644 "$repo_dir/shell.qml" "$config_dir/shell.qml"
install -m644 "$repo_dir/LICENSE" "$config_dir/LICENSE"
printf 'Villode Caelestia Shell\nUpstream: %s\nRevision: %s\n' \
    "$(<"$repo_dir/UPSTREAM_VERSION")" \
    "$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || echo unknown)" \
    > "$config_dir/.villode-managed"

mkdir -p "$HOME/.local/bin"
install -m755 "$repo_dir/bin/caelestia-villode" "$HOME/.local/bin/caelestia"
install -Dm755 "$repo_dir/bin/qs-villode" "$HOME/.local/lib/caelestia/bin/qs"
# Villode screenshot editor (replaces Swappy for region/fullscreen annotation).
if [[ -f "$repo_dir/bin/villode-screenshot-editor" ]]; then
    install -m755 "$repo_dir/bin/villode-screenshot-editor" \
        "$HOME/.local/bin/villode-screenshot-editor"
fi
if [[ -f "$repo_dir/bin/swappy-villode" ]]; then
    # PATH shim so any remaining `swappy` calls open the Villode editor.
    install -m755 "$repo_dir/bin/swappy-villode" "$HOME/.local/bin/swappy"
fi

# Pointer shake-to-find (Mac-style). Safe to re-run; wires Hyprland when present.
if [[ -x "$repo_dir/contrib/villode-cursor/install.sh" ]]; then
    cursor_args=()
    $restart || cursor_args+=(--no-start)
    bash "$repo_dir/contrib/villode-cursor/install.sh" "${cursor_args[@]}" || {
        echo "警告：指针放大组件安装失败，Shell 本体已部署。" >&2
    }
fi

if $build_native; then
    version="$(<"$repo_dir/UPSTREAM_VERSION")"
    revision="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || echo villode)"
    cmake --fresh -S "$repo_dir" -B "$build_dir" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$HOME/.local" \
        -DVERSION="${version#v}" \
        -DGIT_REVISION="$revision" \
        -DDISTRIBUTOR=Villode \
        -DENABLE_MODULES='extras;plugin;m3shapes' \
        -DINSTALL_LIBDIR=lib/caelestia \
        -DINSTALL_QMLDIR=lib/qt6/qml
    cmake --build "$build_dir"
    cmake --install "$build_dir"
    install -m644 "$build_dir/install_manifest.txt" "$state_home/install-manifest.txt"
fi

printf '%s\n' "$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || echo unknown)" > "$state_home/revision"

if $restart; then
    # Keep the direct shell installer aligned with villode-caelestia: kill by the
    # real quickshell process, wait out races with -n, and verify a live process.
    if [[ -x "$HOME/.local/bin/caelestia" ]]; then
        caelestia_bin="$HOME/.local/bin/caelestia"
    else
        caelestia_bin=caelestia
    fi
    if [[ -x "$HOME/.local/lib/caelestia/bin/qs" ]]; then
        qs_bin="$HOME/.local/lib/caelestia/bin/qs"
    else
        qs_bin="$(command -v qs || true)"
    fi

    shell_running() {
        local out pid cmdline
        if [[ -n "$qs_bin" ]]; then
            out="$("$qs_bin" -c caelestia list --json --any-display 2>/dev/null || true)"
            if [[ "$out" == \[* && "$out" != "[]" ]] && grep -q '"pid"[[:space:]]*:' <<<"$out"; then
                return 0
            fi
        fi
        while IFS= read -r pid; do
            [[ -r "/proc/$pid/cmdline" ]] || continue
            cmdline="$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)"
            if [[ "$cmdline" == *'-c caelestia'* ||
                  "$cmdline" == *'--config caelestia'* ||
                  "$cmdline" == *'/quickshell/caelestia'* ]]; then
                return 0
            fi
        done < <(pgrep -u "$UID" -x quickshell 2>/dev/null || true; pgrep -u "$UID" -x qs 2>/dev/null || true)
        return 1
    }

    "$caelestia_bin" shell -k >/dev/null 2>&1 || true
    if [[ -n "$qs_bin" ]]; then
        "$qs_bin" -c caelestia kill --any-display >/dev/null 2>&1 || true
        "$qs_bin" -c caelestia kill --any-display --newest >/dev/null 2>&1 || true
    fi
    pkill -u "$UID" -f '(^|/)qs[[:space:]]+-c[[:space:]]*caelestia([[:space:]]|$)' >/dev/null 2>&1 || true
    pkill -u "$UID" -f '(^|/)quickshell[[:space:]].*-c[[:space:]]*caelestia([[:space:]]|$)' >/dev/null 2>&1 || true
    pkill -u "$UID" -f '(^|/)quickshell[[:space:]].*/quickshell/caelestia' >/dev/null 2>&1 || true

    started=false
    for attempt in 1 2 3; do
        : >/tmp/villode-caelestia-shell.log
        LANG="${LANG:-zh_CN.UTF-8}" LC_ALL="${LC_ALL:-$LANG}" \
            "$caelestia_bin" shell -d >/tmp/villode-caelestia-shell.log 2>&1 || true
        if grep -Fq 'An instance of this configuration is already running.' \
            /tmp/villode-caelestia-shell.log; then
            sleep 0.2
            continue
        fi
        deadline=$((SECONDS + 5))
        while ! shell_running && (( SECONDS < deadline )); do
            sleep 0.1
        done
        if shell_running; then
            started=true
            break
        fi
        sleep 0.2
    done
    if ! $started; then
        echo "安装完成，但 Caelestia 自动启动失败。" >&2
        echo "日志：/tmp/villode-caelestia-shell.log" >&2
        exit 70
    fi
fi

echo "Villode Caelestia Shell 已安装。"
echo "源码版本：$(<"$repo_dir/UPSTREAM_VERSION")"
echo "用户副本：$config_dir"
