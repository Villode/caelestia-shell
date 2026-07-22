#!/usr/bin/env python3
"""Pick one real $HOME folder per ZH/EN place pair (more content wins)."""
from pathlib import Path

home = Path.home()
pairs = {
    "Downloads": ["下载", "Downloads"],
    "Desktop": ["桌面", "Desktop"],
    "Documents": ["文档", "Documents"],
    "Music": ["音乐", "Music"],
    "Pictures": ["图片", "Pictures"],
    "Videos": ["视频", "Videos"],
    "Templates": ["模板", "Templates"],
    "Public": ["公共", "Public"],
    "Projects": ["项目", "Projects"],
}


def content_score(d: Path) -> int:
    """Higher = more real content. Count files under tree (cap depth)."""
    if not d.is_dir():
        return -1
    n = 0
    try:
        for p in d.rglob("*"):
            try:
                if p.is_file():
                    n += 2
                elif p.is_dir():
                    n += 1
            except OSError:
                pass
            if n > 5000:
                break
    except OSError:
        return 0
    return n


for key, cands in pairs.items():
    best = None
    bestn = -1
    first = cands[0]
    for name in cands:
        score = content_score(home / name)
        if score > bestn:
            bestn = score
            best = name
    if not best:
        best = first
    print(f"{key}|{best}")
