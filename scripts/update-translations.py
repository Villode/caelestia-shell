#!/usr/bin/env python3
"""Extract qsTr strings and build qml_zh_CN.ts / .qm for Villode Caelestia Shell.

Source of truth:
  - QML qsTr() sources (lupdate)
  - i18n/zh_CN.json  (English source → Simplified Chinese)

Chinese source strings (qsTr("打开")) are left as-is by lupdate; no mapping needed.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

QSTR_RE = re.compile(r'qsTr\("((?:\\.|[^"\\])*)"\)')

# Built-in fallbacks for Settings strings if zh_CN.json is thin.
BUILTIN: dict[str, str] = {
    "Follow system": "跟随系统",
    "Simplified Chinese": "简体中文",
    "English": "English",
    "24-hour": "24 小时",
    "12-hour": "12 小时",
    "Language and region": "语言和地区",
    "Language": "语言",
    "Display language": "显示语言",
    "Change the Shell language immediately": "立即切换 Shell 的界面语言",
    "Translation status": "翻译状态",
    "Checking translation…": "正在检查翻译…",
    "Loaded · %1": "已加载 · %1",
    "Plugin OK, catalog not loaded · %1": "插件正常，目录未加载 · %1",
    "Catalog missing for %1 — run caelestia-zh-apply": "缺少 %1 的翻译目录 — 请运行 caelestia-zh-apply",
    "Translation plugin missing — reinstall Shell with native modules": "翻译插件缺失 — 请用原生模块重装 Shell",
    "Weather": "天气",
    "Weather location": "天气位置",
    "City or latitude,longitude": "城市或纬度,经度",
    "Leave empty to locate automatically by IP address": "留空则按 IP 地址自动定位",
    "Use IP": "使用 IP",
    "Save": "保存",
    "Units": "单位",
    "Weather temperature": "天气温度",
    "Temperature unit used by weather forecasts": "天气预报使用的温度单位",
    "System temperature": "系统温度",
    "Temperature unit used by the CPU and GPU": "CPU 和 GPU 使用的温度单位",
    "Time and date": "时间和日期",
    "Date and time": "日期和时间",
    "Clock format": "时钟格式",
    "How time is displayed in the Shell": "Shell 中时间的显示方式",
    "Resolution, UI scale, display scaling": "分辨率、界面缩放、显示缩放",
    "Mouse & touchpad": "鼠标和触摸板",
    "Touchpad and pointer controls": "触摸板和指针控制",
    "Villode updates": "Villode 更新",
    "Sync Shell, translations and desktop components": "同步 Shell、翻译与桌面组件",
    "Lock screen & power": "锁屏与电源",
    "Lock, display off, sleep and idle timeouts": "锁屏、关屏、睡眠与空闲超时",
    "Dashboard": "仪表盘",
    "Media": "媒体",
    "Performance": "性能",
    "Log out": "注销",
    "Shut down": "关机",
    "Hibernate": "休眠",
    "Reboot": "重启",
    "Refresh": "刷新",
    "Reading system time…": "正在读取系统时间…",
    "Network time on · synced": "网络时间 开 · 已同步",
    "Network time on · syncing…": "网络时间 开 · 同步中…",
    "Network time off · manual": "网络时间 关 · 手动",
    "Could not read system time settings.": "无法读取系统时间设置。",
}


def decoded(value: str) -> str:
    return json.loads(f'"{value}"')


def patch_translations(path: Path) -> dict[str, str]:
    """Import translations from a retired QML-diff patch (optional)."""
    translations: dict[str, str] = {}
    removed: list[str] = []
    added: list[str] = []

    def flush() -> None:
        nonlocal removed, added
        old = [decoded(value) for line in removed for value in QSTR_RE.findall(line)]
        new = [decoded(value) for line in added for value in QSTR_RE.findall(line)]
        if len(old) == len(new):
            for source, translation in zip(old, new):
                translations.setdefault(source, translation)
        removed = []
        added = []

    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("@@") or line.startswith("diff --git") or line.startswith(" "):
            flush()
        if line.startswith("-") and not line.startswith("---"):
            removed.append(line[1:])
        elif line.startswith("+") and not line.startswith("+++"):
            added.append(line[1:])
    flush()
    return translations


def looks_chinese(text: str) -> bool:
    return any("\u4e00" <= ch <= "\u9fff" for ch in text)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lupdate", required=True)
    parser.add_argument("--lrelease", required=True)
    parser.add_argument(
        "--legacy-patch",
        type=Path,
        help="Optional one-time source for importing translations from a retired QML patch",
    )
    parser.add_argument("--root", default=Path(__file__).resolve().parents[1], type=Path)
    parser.add_argument(
        "--fail-unfinished",
        action="store_true",
        help="Exit non-zero if any message remains unfinished after merge",
    )
    args = parser.parse_args()

    root = args.root.resolve()
    i18n = root / "i18n"
    i18n.mkdir(exist_ok=True)
    ts_file = i18n / "qml_zh_CN.ts"
    qm_file = i18n / "qml_zh_CN.qm"
    json_file = i18n / "zh_CN.json"

    qml_files = sorted(
        str(path.relative_to(root))
        for path in root.rglob("*.qml")
        if ".git" not in path.parts and "node_modules" not in path.parts
    )
    if not qml_files:
        print("No QML files found", file=sys.stderr)
        return 66

    subprocess.run(
        [
            args.lupdate,
            *qml_files,
            "-source-language",
            "en_US",
            "-target-language",
            "zh_CN",
            "-locations",
            "relative",
            "-no-obsolete",
            "-ts",
            str(ts_file),
        ],
        cwd=root,
        check=True,
    )

    translations: dict[str, str] = {}
    if args.legacy_patch:
        translations.update(patch_translations(args.legacy_patch))
    translations.update(BUILTIN)
    if json_file.is_file():
        translations.update(json.loads(json_file.read_text(encoding="utf-8")))

    tree = ET.parse(ts_file)
    finished = 0
    auto_chinese = 0
    unfinished = 0
    for message in tree.findall(".//message"):
        source = message.findtext("source", "") or ""
        translation = message.find("translation")
        if translation is None:
            translation = ET.SubElement(message, "translation")
        if source in translations and translations[source]:
            translation.attrib.pop("type", None)
            translation.text = translations[source]
            finished += 1
        elif looks_chinese(source):
            # Chinese source strings need no catalog entry for zh_CN UI.
            translation.attrib.pop("type", None)
            translation.text = source
            auto_chinese += 1
        else:
            # Keep existing finished text; count unfinished.
            ttype = translation.attrib.get("type", "")
            if ttype == "unfinished" or not (translation.text or "").strip():
                unfinished += 1
            else:
                finished += 1

    ET.indent(tree, space="    ")
    tree.write(ts_file, encoding="utf-8", xml_declaration=True)

    subprocess.run([args.lrelease, str(ts_file), "-qm", str(qm_file)], check=True)
    print(
        f"Updated {ts_file.name}: finished={finished} auto_zh={auto_chinese} "
        f"unfinished={unfinished} → {qm_file.name}"
    )
    if args.fail_unfinished and unfinished:
        print(f"{unfinished} unfinished message(s)", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
