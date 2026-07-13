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

for path in assets components modules services utils shell.qml LICENSE UPSTREAM_VERSION; do
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
for directory in assets components modules services utils; do
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
    "$HOME/.local/bin/caelestia" shell -k >/dev/null 2>&1 || true
    LANG="${LANG:-zh_CN.UTF-8}" "$HOME/.local/bin/caelestia" shell -d \
        >/tmp/villode-caelestia-shell.log 2>&1 || {
            echo "安装完成，但 Caelestia 自动启动失败。" >&2
            echo "日志：/tmp/villode-caelestia-shell.log" >&2
            exit 70
        }
fi

echo "Villode Caelestia Shell 已安装。"
echo "源码版本：$(<"$repo_dir/UPSTREAM_VERSION")"
echo "用户副本：$config_dir"
