#!/usr/bin/env python3

import argparse
import json
import re
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path


QSTR_RE = re.compile(r'qsTr\("((?:\\.|[^"\\])*)"\)')


def decoded(value: str) -> str:
    return json.loads(f'"{value}"')


def patch_translations(path: Path) -> dict[str, str]:
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


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lupdate", required=True)
    parser.add_argument("--lrelease", required=True)
    parser.add_argument(
        "--legacy-patch",
        type=Path,
        help="Optional one-time source for importing translations from the retired QML patch",
    )
    parser.add_argument("--root", default=Path(__file__).resolve().parents[1], type=Path)
    args = parser.parse_args()

    root = args.root.resolve()
    i18n = root / "i18n"
    i18n.mkdir(exist_ok=True)
    ts_file = i18n / "qml_zh_CN.ts"
    qm_file = i18n / "qml_zh_CN.qm"
    qml_files = sorted(str(path.relative_to(root)) for path in root.rglob("*.qml") if ".git" not in path.parts)

    subprocess.run([
        args.lupdate,
        *qml_files,
        "-source-language", "en_US",
        "-target-language", "zh_CN",
        "-locations", "relative",
        "-no-obsolete",
        "-ts", str(ts_file),
    ], cwd=root, check=True)

    translations = patch_translations(args.legacy_patch) if args.legacy_patch else {}
    translations.update({
        "Follow system": "跟随系统",
        "Simplified Chinese": "简体中文",
        "English": "English",
        "24-hour": "24 小时",
        "12-hour": "12 小时",
        "Language and region": "语言和地区",
        "Language": "语言",
        "Display language": "显示语言",
        "Change the Shell language immediately": "立即切换 Shell 的界面语言",
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
    })
    translations.update(json.loads((i18n / "zh_CN.json").read_text(encoding="utf-8")))

    tree = ET.parse(ts_file)
    finished = 0
    for message in tree.findall(".//message"):
        source = message.findtext("source", "")
        translation = message.find("translation")
        if translation is None or source not in translations:
            continue
        translation.attrib.pop("type", None)
        translation.text = translations[source]
        finished += 1
    ET.indent(tree, space="    ")
    tree.write(ts_file, encoding="utf-8", xml_declaration=True)

    subprocess.run([args.lrelease, str(ts_file), "-qm", str(qm_file)], check=True)
    print(f"Updated {ts_file} with {finished} translated messages")


if __name__ == "__main__":
    main()
