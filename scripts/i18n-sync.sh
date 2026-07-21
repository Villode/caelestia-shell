#!/usr/bin/env bash
# Sync Qt Linguist catalogs for Villode Caelestia Shell.
# Source of truth: this repo's i18n/ (zh_CN.json + lupdate from QML).
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
check_only=false
strict=false
lupdate_bin=""
lrelease_bin=""

usage() {
    cat <<'EOF'
用法：scripts/i18n-sync.sh [选项]

从 QML 提取 qsTr 字符串，合并 i18n/zh_CN.json，生成 qml_zh_CN.ts / .qm。

选项：
  --check     仅检查：不写文件；存在 unfinished 或目录过旧则失败
  --strict    同步后若仍有 unfinished 则失败（CI 门禁）
  -h, --help  显示帮助
EOF
}

while (($#)); do
    case "$1" in
        --check) check_only=true ;;
        --strict) strict=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "未知选项：$1" >&2; usage >&2; exit 64 ;;
    esac
    shift
done

find_qt_tool() {
    local name="$1"
    local c
    for c in \
        "/usr/lib/qt6/bin/$name" \
        "/usr/lib64/qt6/bin/$name" \
        "$name" \
        "${name}-qt6"; do
        if command -v "$c" >/dev/null 2>&1; then
            command -v "$c"
            return 0
        fi
        if [[ -x "$c" ]]; then
            printf '%s\n' "$c"
            return 0
        fi
    done
    return 1
}

lupdate_bin="$(find_qt_tool lupdate)" || {
    echo "未找到 lupdate（需要 qt6-tools）" >&2
    exit 69
}
lrelease_bin="$(find_qt_tool lrelease)" || {
    echo "未找到 lrelease（需要 qt6-tools）" >&2
    exit 69
}

ts_file="$repo_dir/i18n/qml_zh_CN.ts"
qm_file="$repo_dir/i18n/qml_zh_CN.qm"
json_file="$repo_dir/i18n/zh_CN.json"

[[ -f "$json_file" ]] || {
    echo "缺少 $json_file" >&2
    exit 66
}

if $check_only; then
    unfinished=0
    if [[ -f "$ts_file" ]]; then
        unfinished="$(grep -c 'type="unfinished"' "$ts_file" || true)"
    else
        echo "缺少 $ts_file" >&2
        exit 1
    fi
    if (( unfinished > 0 )); then
        echo "i18n 检查失败：${unfinished} 条 unfinished 翻译" >&2
        exit 1
    fi
    if [[ ! -f "$qm_file" ]]; then
        echo "缺少 $qm_file" >&2
        exit 1
    fi
    # qm should not be older than zh_CN.json by a long margin without rebuild
    if [[ "$json_file" -nt "$qm_file" ]]; then
        echo "警告：zh_CN.json 新于 qml_zh_CN.qm，请运行 scripts/i18n-sync.sh" >&2
        exit 1
    fi
    echo "i18n 检查通过（unfinished=0，qm 存在）。"
    exit 0
fi

python3 "$repo_dir/scripts/update-translations.py" \
    --lupdate "$lupdate_bin" \
    --lrelease "$lrelease_bin" \
    --root "$repo_dir"

unfinished="$(grep -c 'type="unfinished"' "$ts_file" || true)"
messages="$(grep -c '<message>' "$ts_file" || true)"
echo "消息 ${messages} 条，unfinished ${unfinished} 条"
echo "已更新：$ts_file"
echo "已更新：$qm_file"

if $strict && (( unfinished > 0 )); then
    echo "strict：仍有 unfinished 翻译，失败。" >&2
    exit 1
fi
