pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.utils

QtObject {
    id: root

    // Logical places (not filesystem names). Special root: ThisPC (Windows-style 此电脑)
    property list<string> cwd: ["ThisPC"]
    property list<string> selection: []
    property string clipboardMode: "" // "copy" | "cut" | ""
    property list<string> clipboardPaths: []
    property string statusText: qsTr("就绪")
    property string nameFilter: ""
    property int refreshNonce: 0

    // View prefs
    property string viewMode: "grid" // "grid" | "list"
    property bool showHidden: false
    property bool showExtensions: true
    // favorites: [{ path: string, name: string }]
    property var favorites: []

    readonly property bool isThisPC: cwd.length === 1 && cwd[0] === "ThisPC"
    readonly property bool isPhone: cwd.length >= 1 && cwd[0] === "Phone"

    function gvfsDir(): string {
        const runtime = Quickshell.env("XDG_RUNTIME_DIR") || "";
        return runtime ? (runtime + "/gvfs") : "";
    }

    readonly property var placeFolders: ({
        Downloads: ["下载", "Downloads"],
        Desktop: ["桌面", "Desktop"],
        Documents: ["文档", "Documents"],
        Music: ["音乐", "Music"],
        Pictures: ["图片", "Pictures"],
        Videos: ["视频", "Videos"],
        Templates: ["模板", "Templates"],
        Public: ["公共", "Public"],
        Projects: ["项目", "Projects"]
    })

    readonly property var placeLabels: ({
        ThisPC: qsTr("此电脑"),
        Home: qsTr("主目录"),
        Trash: qsTr("回收站"),
        Phone: qsTr("手机"),
        Downloads: qsTr("下载"),
        Desktop: qsTr("桌面"),
        Documents: qsTr("文档"),
        Music: qsTr("音乐"),
        Pictures: qsTr("图片"),
        Videos: qsTr("视频")
    })

    function trashPath(): string {
        // XDG trash files dir
        return Paths.home + "/.local/share/Trash/files";
    }

    function isTrash(): bool {
        const p = cwdPath();
        return p === trashPath();
    }

    signal settingsChanged

    function isPlaceId(name: string): bool {
        return name === "Home" || name === "ThisPC" || name === "Trash" || name === "Phone" || !!placeFolders[name];
    }

    function placeSelected(place: string): bool {
        if (place === "ThisPC")
            return isThisPC;
        if (place === "Trash")
            return isTrash();
        if (place === "Home")
            return !isThisPC && !isTrash() && !isPhone && cwd.length >= 1 && cwd[0] === "Home" && (cwd.length === 1 || !placeFolders[cwd[1]]);
        // place folders under Home
        return !isThisPC && !isTrash() && !isPhone && cwd.length >= 2 && cwd[0] === "Home" && cwd[1] === place;
    }

    function prettyMtpHost(seg: string): string {
        let s = seg || "";
        if (s.startsWith("mtp:host="))
            s = s.slice("mtp:host=".length);
        // Xiaomi_Redmi_K90_9c073b13 → Redmi K90 (drop vendor + serial when possible)
        s = s.replace(/_/g, " ");
        s = s.replace(/^Xiaomi\s+/i, "");
        // drop trailing hex-ish serial token
        s = s.replace(/\s+[0-9a-fA-F]{6,}$/, "");
        return s.trim() || qsTr("手机");
    }

    function labelForSegment(name: string): string {
        if (placeLabels[name])
            return placeLabels[name];
        if (name && (name.startsWith("mtp:host=") || name.startsWith("gphoto2:host=") || name.startsWith("afc:")))
            return prettyMtpHost(name);
        for (const key of Object.keys(placeFolders)) {
            const list = placeFolders[key];
            if (list.indexOf(name) >= 0)
                return placeLabels[key] || name;
        }
        return name === "" ? "/" : name;
    }

    // Friendly bar text (not raw /run/user/.../gvfs/...)
    function displayPath(): string {
        if (isThisPC)
            return qsTr("此电脑");
        if (isPhone) {
            const parts = [];
            for (let i = 0; i < cwd.length; i++)
                parts.push(labelForSegment(cwd[i]));
            return parts.join(" / ");
        }
        if (isTrash())
            return qsTr("回收站");
        const p = cwdPath();
        if (!p)
            return qsTr("此电脑");
        return Paths.shortenHome(p);
    }

    function preferredFolderName(place: string): string {
        const candidates = placeFolders[place];
        if (candidates && candidates.length)
            return candidates[0];
        return place;
    }

    function cwdPath(): string {
        if (cwd.length === 0 || cwd[0] === "ThisPC")
            return "";
        if (cwd[0] === "Phone") {
            const base = gvfsDir();
            if (!base)
                return "";
            if (cwd.length === 1)
                return base;
            return base + "/" + cwd.slice(1).join("/");
        }
        if (cwd[0] === "Home") {
            if (cwd.length === 1)
                return Paths.home;
            let path = Paths.home;
            for (let i = 1; i < cwd.length; i++) {
                let seg = cwd[i];
                if (i === 1 && placeFolders[seg])
                    seg = preferredFolderName(seg);
                path = path + "/" + seg;
            }
            return path;
        }
        if (cwd[0] === "")
            return "/" + cwd.slice(1).join("/");
        return cwd.join("/");
    }

    function navigateToThisPC(): void {
        cwd = ["ThisPC"];
        selection = [];
        statusText = qsTr("此电脑");
        bumpRefresh();
    }

    function navigateToPlace(place: string): void {
        if (place === "ThisPC") {
            navigateToThisPC();
            return;
        }
        if (place === "Trash") {
            navigateToTrash();
            return;
        }
        if (place === "Home")
            cwd = ["Home"];
        else
            cwd = ["Home", place];
        selection = [];
        statusText = displayPath();
        bumpRefresh();
    }

    function navigateToTrash(): void {
        const t = trashPath();
        // Ensure trash dirs exist
        Quickshell.execDetached(["mkdir", "-p", t, Paths.home + "/.local/share/Trash/info"]);
        openAbsolutePath(t);
        statusText = qsTr("回收站");
    }

    function pushDir(name: string): void {
        if (isThisPC)
            return;
        cwd = cwd.concat([name]);
        selection = [];
        statusText = displayPath();
    }

    function popDir(): void {
        if (isThisPC)
            return;
        if (cwd.length > 1) {
            cwd = cwd.slice(0, cwd.length - 1);
            // Phone root (only "Phone") → back to This PC
            if (cwd.length === 1 && cwd[0] === "Phone")
                cwd = ["ThisPC"];
        } else {
            // From Home or / go back to This PC
            cwd = ["ThisPC"];
        }
        selection = [];
        statusText = isThisPC ? qsTr("此电脑") : displayPath();
        bumpRefresh();
    }

    function sliceCwd(toIndex: int): void {
        if (toIndex < 0 || toIndex >= cwd.length)
            return;
        cwd = cwd.slice(0, toIndex + 1);
        // Phone root alone → This PC
        if (cwd.length === 1 && cwd[0] === "Phone")
            cwd = ["ThisPC"];
        selection = [];
        statusText = isThisPC ? qsTr("此电脑") : displayPath();
        bumpRefresh();
    }

    function openAbsolutePath(path: string): void {
        if (!path || path.length === 0) {
            navigateToThisPC();
            return;
        }
        // expand ~
        if (path === "~")
            path = Paths.home;
        else if (path.startsWith("~/"))
            path = Paths.home + path.slice(1);
        while (path.length > 1 && path.endsWith("/"))
            path = path.slice(0, -1);

        const home = Paths.home;
        const gvfs = gvfsDir();
        // MTP / gphoto fuse mounts: /run/user/UID/gvfs/mtp:host=...
        if (gvfs && (path === gvfs || path.startsWith(gvfs + "/"))) {
            if (path === gvfs) {
                cwd = ["Phone"];
            } else {
                const rel = path.slice(gvfs.length + 1).split("/").filter(s => s.length > 0);
                cwd = ["Phone"].concat(rel);
            }
        } else if (path === home) {
            cwd = ["Home"];
        } else if (path.startsWith(home + "/")) {
            const rel = path.slice(home.length + 1).split("/").filter(s => s.length > 0);
            if (rel.length > 0) {
                let first = rel[0];
                for (const key of Object.keys(placeFolders)) {
                    if (placeFolders[key].indexOf(first) >= 0) {
                        first = key;
                        break;
                    }
                }
                cwd = ["Home", first].concat(rel.slice(1));
            } else {
                cwd = ["Home"];
            }
        } else if (path.startsWith("/")) {
            if (path === "/")
                cwd = [""];
            else
                cwd = [""].concat(path.split("/").filter(s => s.length > 0));
        } else {
            // relative or bare name → try under home
            cwd = ["Home"].concat(path.split("/").filter(s => s.length > 0));
        }
        selection = [];
        statusText = displayPath();
        bumpRefresh();
    }

    function setSelection(paths: list<string>): void {
        selection = paths;
        if (paths.length === 0)
            statusText = qsTr("%1 · 已取消选择").arg(Paths.shortenHome(cwdPath()));
        else if (paths.length === 1)
            statusText = qsTr("已选 1 项");
        else
            statusText = qsTr("已选 %1 项").arg(paths.length);
    }

    function toggleSelection(path: string): void {
        const idx = selection.indexOf(path);
        let next = selection.slice();
        if (idx >= 0)
            next.splice(idx, 1);
        else
            next.push(path);
        setSelection(next);
    }

    function bumpRefresh(): void {
        refreshNonce = refreshNonce + 1;
    }

    function displayName(entry: var): string {
        if (!entry)
            return "";
        if (entry.isDir || showExtensions)
            return entry.name || "";
        const base = entry.baseName;
        if (base && base.length)
            return base;
        // fallback strip last .ext
        const n = entry.name || "";
        const i = n.lastIndexOf(".");
        if (i > 0)
            return n.slice(0, i);
        return n;
    }

    function isFavorite(path: string): bool {
        if (!path)
            return false;
        for (let i = 0; i < favorites.length; i++) {
            if (favorites[i].path === path)
                return true;
        }
        return false;
    }

    function pinPath(path: string, name: string): void {
        if (!path)
            return;
        while (path.length > 1 && path.endsWith("/"))
            path = path.slice(0, -1);
        if (isFavorite(path)) {
            statusText = qsTr("已在侧栏快捷中");
            return;
        }
        const n = name || path.split("/").pop() || path;
        favorites = favorites.concat([{
                path: path,
                name: n
            }]);
        statusText = qsTr("已固定：%1").arg(n);
        settingsChanged();
    }

    function unpinPath(path: string): void {
        favorites = favorites.filter(f => f.path !== path);
        statusText = qsTr("已取消固定");
        settingsChanged();
    }

    function setViewMode(mode: string): void {
        if (mode !== "grid" && mode !== "list")
            return;
        if (viewMode === mode)
            return;
        viewMode = mode;
        settingsChanged();
    }

    function toggleShowHidden(): void {
        showHidden = !showHidden;
        statusText = showHidden ? qsTr("显示隐藏文件") : qsTr("隐藏点文件");
        bumpRefresh();
        settingsChanged();
    }

    function toggleShowExtensions(): void {
        showExtensions = !showExtensions;
        statusText = showExtensions ? qsTr("显示扩展名") : qsTr("隐藏扩展名");
        settingsChanged();
    }

    function applySettings(data: var): void {
        if (!data)
            return;
        if (data.viewMode === "grid" || data.viewMode === "list")
            viewMode = data.viewMode;
        if (typeof data.showHidden === "boolean")
            showHidden = data.showHidden;
        if (typeof data.showExtensions === "boolean")
            showExtensions = data.showExtensions;
        if (Array.isArray(data.favorites)) {
            const next = [];
            for (let i = 0; i < data.favorites.length; i++) {
                const f = data.favorites[i];
                if (f && f.path)
                    next.push({
                        path: String(f.path),
                        name: String(f.name || f.path.split("/").pop() || f.path)
                    });
            }
            favorites = next;
        }
    }

    function settingsJson(): string {
        return JSON.stringify({
            viewMode: viewMode,
            showHidden: showHidden,
            showExtensions: showExtensions,
            favorites: favorites
        }, null, 2);
    }
}
