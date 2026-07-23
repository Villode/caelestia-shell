pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

Item {
    id: root
    // Item (not QtObject) so we can own a Process for place resolution

    // Logical places (not filesystem names). Special root: ThisPC (Windows-style 此电脑)
    property list<string> cwd: ["ThisPC"]
    property list<string> selection: []
    property string clipboardMode: "" // "copy" | "cut" | ""
    property list<string> clipboardPaths: []
    property string statusText: qsTr("就绪")
    property string nameFilter: ""
    // "local" = current folder filter; "global" = recursive find under home
    property string searchScope: "local"
    property bool globalSearchBusy: false
    property string globalSearchQuery: ""
    // [{ path, name, parent, isDir }]
    property var globalResults: []
    property int refreshNonce: 0
    // Binding-friendly filters for FileSystemModel.
    // Use ["*"] (not []) for "show all" so QML/C++ empty-list edge cases cannot stick.
    readonly property var nameFiltersActive: {
        const raw = nameFilter;
        const q = (raw || "").trim();
        if (!q.length)
            return ["*"];
        if (q.indexOf("*") >= 0 || q.indexOf("?") >= 0)
            return [q];
        let escaped = "";
        for (let i = 0; i < q.length; i++) {
            const c = q.charAt(i);
            if (c === "\\" || c === "*" || c === "?")
                escaped += "\\" + c;
            else
                escaped += c;
        }
        return ["*" + escaped + "*"];
    }

    // View prefs
    property string viewMode: "grid" // "grid" | "list"
    property bool showHidden: false
    property bool showExtensions: true
    // sortBy: name | size | type | mtime
    property string sortBy: "name"
    property bool sortReverse: false
    property bool foldersFirst: true
    // favorites: [{ path: string, name: string }]
    property var favorites: []

    // Virtual archive browse: open zip/7z/... as a navigable folder in the main view
    property string archiveRoot: ""          // host archive path
    property string archiveInner: ""         // "" or "subdir/" (trailing slash when non-empty)
    property var archiveEntries: []          // raw list from 7z [{name,isDir,size,...}]
    property bool archiveLoading: false
    property string archiveError: ""
    property int archiveNonce: 0

    readonly property bool isArchiveBrowse: archiveRoot.length > 0

    readonly property bool isThisPC: cwd.length === 1 && cwd[0] === "ThisPC"
    readonly property bool isPhone: cwd.length >= 1 && cwd[0] === "Phone"

    function clearArchiveBrowse(): void {
        archiveRoot = "";
        archiveInner = "";
        archiveEntries = [];
        archiveLoading = false;
        archiveError = "";
        archiveNonce = archiveNonce + 1;
    }

    function archiveCompoundExt(path: string): string {
        const n = ((path || "").split("/").pop() || "").toLowerCase();
        const multi = [".tar.gz", ".tar.xz", ".tar.bz2", ".tar.zst", ".tgz", ".txz", ".tbz2", ".tzst"];
        for (let i = 0; i < multi.length; i++) {
            if (n.endsWith(multi[i]))
                return multi[i].slice(1);
        }
        const i = n.lastIndexOf(".");
        if (i <= 0)
            return "";
        return n.slice(i + 1);
    }

    function isArchiveFile(path: string): bool {
        const e = archiveCompoundExt(path);
        const list = ["zip", "7z", "rar", "tar", "gz", "tgz", "xz", "txz", "bz2", "tbz2", "zst", "tzst", "lz", "lzma", "cab", "iso", "apk", "jar", "war", "tar.gz", "tar.xz", "tar.bz2", "tar.zst"];
        return list.indexOf(e) >= 0;
    }

    function isImageFile(path: string, flag: bool): bool {
        if (flag)
            return true;
        const e = archiveCompoundExt(path);
        const list = ["png", "jpg", "jpeg", "jpe", "jfif", "webp", "gif", "bmp", "tif", "tiff", "ico", "heic", "heif", "avif", "svg"];
        return list.indexOf(e) >= 0;
    }

    function isAudioFile(path: string): bool {
        const e = archiveCompoundExt(path);
        const list = ["mp3", "flac", "wav", "ogg", "oga", "opus", "m4a", "aac", "wma", "aiff", "ape", "alac"];
        return list.indexOf(e) >= 0;
    }

    function isVideoFile(path: string): bool {
        const e = archiveCompoundExt(path);
        const list = ["mp4", "mkv", "webm", "avi", "mov", "m4v", "wmv", "flv", "ts", "m2ts"];
        return list.indexOf(e) >= 0;
    }

    function enterArchive(path: string): void {
        if (!path || !path.length)
            return;
        archiveRoot = path;
        archiveInner = "";
        archiveEntries = [];
        archiveError = "";
        archiveLoading = true;
        selection = [];
        resetSearchOnNavigate();
        statusText = qsTr("正在打开压缩包…");
        archiveNonce = archiveNonce + 1;
        // JSON list via helper (reliable vs huge 7z text through collector)
        const script = Quickshell.shellPath("modules/filemanager/list-archive.py");
        archiveListProc.running = false;
        archiveListProc.command = ["python3", script, path];
        archiveListProc.running = true;
    }

    function setArchiveInner(rel: string): void {
        // rel without leading slash; folders end with /
        let r = rel || "";
        while (r.startsWith("/"))
            r = r.slice(1);
        if (r.length && !r.endsWith("/"))
            r += "/";
        archiveInner = r;
        selection = [];
        resetSearchOnNavigate();
        statusText = archiveDisplayPath();
        archiveNonce = archiveNonce + 1;
    }

    function pushArchiveDir(name: string): void {
        if (!name || !name.length)
            return;
        setArchiveInner(archiveInner + name + "/");
    }

    function popArchiveDir(): void {
        if (!isArchiveBrowse)
            return;
        if (!archiveInner.length) {
            // leave archive back to parent folder of archive file
            const parent = archiveRoot.substring(0, archiveRoot.lastIndexOf("/")) || "/";
            clearArchiveBrowse();
            openAbsolutePath(parent);
            return;
        }
        const parts = archiveInner.replace(/\/+$/, "").split("/").filter(s => s.length > 0);
        parts.pop();
        setArchiveInner(parts.length ? parts.join("/") + "/" : "");
    }

    function archiveDisplayPath(): string {
        if (!isArchiveBrowse)
            return displayPath();
        const base = (archiveRoot.split("/").pop() || archiveRoot);
        if (!archiveInner.length)
            return qsTr("%1（压缩包）").arg(base);
        return qsTr("%1 / %2").arg(base).arg(archiveInner.replace(/\/+$/, ""));
    }

    function pathSegments(): var {
        if (!isArchiveBrowse)
            return cwd;
        const segs = [];
        const base = (archiveRoot.split("/").pop() || archiveRoot);
        segs.push(base);
        let inner = archiveInner || "";
        while (inner.endsWith("/"))
            inner = inner.slice(0, -1);
        if (inner.length) {
            const parts = inner.split("/");
            for (let i = 0; i < parts.length; i++) {
                if (parts[i].length)
                    segs.push(parts[i]);
            }
        }
        return segs;
    }

    function slicePathSegment(toIndex: int): void {
        if (isArchiveBrowse) {
            if (toIndex < 0)
                return;
            if (toIndex === 0) {
                setArchiveInner("");
                return;
            }
            const segs = pathSegments();
            if (toIndex >= segs.length)
                return;
            const parts = [];
            for (let i = 1; i <= toIndex; i++)
                parts.push(segs[i]);
            setArchiveInner(parts.length ? (parts.join("/") + "/") : "");
            return;
        }
        sliceCwd(toIndex);
    }

    readonly property bool canNavigateUp: isArchiveBrowse || !isThisPC

    function canGoUp(): bool {
        return canNavigateUp;
    }


    function parseArchiveListing(raw: string): void {
        let items = [];
        let err = "";
        try {
            const data = JSON.parse(String(raw || "").trim() || "{}");
            if (data && Array.isArray(data.items))
                items = data.items;
            if (data && data.ok === false)
                err = String(data.error || qsTr("无法打开压缩包"));
            else if (data && data.error)
                err = String(data.error);
        } catch (e) {
            // Fallback: line-based 7z -ba parse
            const lines = String(raw || "").split("\n");
            const re = /^(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s+([D.][\w.]+)\s+(\d+)\s+(\d+)\s+(.+)$/;
            for (let i = 0; i < lines.length; i++) {
                let line = lines[i];
                if (!line || !line.length)
                    continue;
                line = line.replace(/\r$/, "");
                const mm = line.match(re);
                if (!mm)
                    continue;
                const attr = mm[2] || "";
                const size = Number(mm[3] || 0);
                const name = (mm[5] || "").trim();
                if (!name.length)
                    continue;
                items.push({
                    path: name,
                    name: name,
                    isDir: attr.indexOf("D") === 0,
                    size: size
                });
            }
            if (!items.length)
                err = qsTr("压缩包为空或无法列出内容");
        }
        archiveEntries = items;
        archiveLoading = false;
        if (!items.length)
            archiveError = err.length ? err : qsTr("压缩包为空或无法列出内容");
        else
            archiveError = "";
        statusText = archiveError.length ? archiveError : archiveDisplayPath();
        archiveNonce = archiveNonce + 1;
        console.log("[FM] archive listed", archiveRoot, "items=", items.length, "err=", archiveError);
    }

    // Children of archiveInner as folder-view entries
    function archiveViewEntries(): var {
        const out = [];
        const prefix = archiveInner || "";
        const seen = ({});
        for (let i = 0; i < archiveEntries.length; i++) {
            const e = archiveEntries[i];
            const full = e.path || e.name || "";
            if (!full.length)
                continue;
            if (prefix.length && !full.startsWith(prefix))
                continue;
            let rest = prefix.length ? full.slice(prefix.length) : full;
            if (!rest.length)
                continue;
            const slash = rest.indexOf("/");
            if (slash >= 0) {
                const dirName = rest.slice(0, slash);
                if (!dirName.length || seen[dirName])
                    continue;
                seen[dirName] = true;
                out.push({
                    path: "archive://" + archiveRoot + "!/" + prefix + dirName + "/",
                    name: dirName,
                    isDir: true,
                    isImage: false,
                    size: 0,
                    mimeType: "",
                    suffix: "",
                    baseName: dirName,
                    archiveMember: prefix + dirName + "/"
                });
            } else {
                // entry at this level (file or empty dir)
                if (seen[rest])
                    continue;
                seen[rest] = true;
                const base = rest;
                const isD = !!(e.isDir);
                const dot = base.lastIndexOf(".");
                const suf = (!isD && dot > 0) ? base.slice(dot + 1).toLowerCase() : "";
                const member = prefix + rest + (isD ? "/" : "");
                out.push({
                    path: "archive://" + archiveRoot + "!/" + member,
                    name: base,
                    isDir: isD,
                    isImage: !isD && isImageFile(base, false),
                    size: isD ? 0 : (e.size || 0),
                    mimeType: "",
                    suffix: suf,
                    baseName: (!isD && dot > 0) ? base.slice(0, dot) : base,
                    archiveMember: member
                });
            }
        }
        return out;
    }

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
        Videos: qsTr("视频"),
        Templates: qsTr("模板"),
        Public: qsTr("公共"),
        Projects: qsTr("项目")
    })

    // place key → real FS folder under $HOME (one name for each ZH/EN pair)
    property var placeResolved: ({})

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

    // "Pictures" / "图片" → place key "Pictures"; unknown → ""
    function placeKeyForFsName(name: string): string {
        if (!name)
            return "";
        if (placeFolders[name])
            return name;
        for (const key of Object.keys(placeFolders)) {
            if (placeFolders[key].indexOf(name) >= 0)
                return key;
        }
        return "";
    }

    function placeSelected(place: string): bool {
        if (place === "ThisPC")
            return isThisPC;
        if (place === "Trash")
            return isTrash();
        if (place === "Home")
            return !isThisPC && !isTrash() && !isPhone && cwd.length >= 1 && cwd[0] === "Home" && (cwd.length === 1 || !placeKeyForFsName(cwd[1]));
        if (isThisPC || isTrash() || isPhone || cwd.length < 2 || cwd[0] !== "Home")
            return false;
        return placeKeyForFsName(cwd[1]) === place;
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
        if (isArchiveBrowse)
            return archiveDisplayPath();
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
        // One real directory for side-bar place (merged ZH/EN pair).
        const resolved = placeResolved[place];
        if (resolved)
            return resolved;
        const candidates = placeFolders[place];
        if (!candidates || !candidates.length)
            return place;
        const home = Paths.home || "";
        const xdgMap = ({
            Pictures: Paths.pictures || "",
            Videos: Paths.videos || "",
            Downloads: Quickshell.env("XDG_DOWNLOAD_DIR") || "",
            Desktop: Quickshell.env("XDG_DESKTOP_DIR") || "",
            Documents: Quickshell.env("XDG_DOCUMENTS_DIR") || "",
            Music: Quickshell.env("XDG_MUSIC_DIR") || "",
            Templates: Quickshell.env("XDG_TEMPLATES_DIR") || "",
            Public: Quickshell.env("XDG_PUBLICSHARE_DIR") || "",
            Projects: Quickshell.env("XDG_PROJECTS_DIR") || ""
        });
        const xdg = xdgMap[place] || "";
        if (xdg && home && xdg.startsWith(home + "/")) {
            const name = xdg.slice(home.length + 1);
            if (name.length && name.indexOf("/") < 0 && candidates.indexOf(name) >= 0)
                return name;
        }
        return candidates[0];
    }

    // Home grid: hide the non-preferred sibling of a place pair (Pictures vs 图片).
    function isHiddenPlaceSibling(fsName: string): bool {
        const key = placeKeyForFsName(fsName);
        if (!key)
            return false;
        return fsName !== preferredFolderName(key);
    }

    // True when browsing a place folder root under Home (图片 or Pictures, not Screenshots).
    function isAtPlaceRoot(): bool {
        if (isThisPC || isPhone || isTrash())
            return false;
        if (cwd.length !== 2 || cwd[0] !== "Home")
            return false;
        return !!placeKeyForFsName(cwd[1]);
    }

    // Other ZH/EN twin directory path for current place root ("" if none / not at place root).
    function placeSiblingPath(): string {
        if (!isAtPlaceRoot())
            return "";
        const key = placeKeyForFsName(cwd[1]);
        if (!key)
            return "";
        const candidates = placeFolders[key];
        if (!candidates || candidates.length < 2)
            return "";
        const cur = cwd[1];
        const home = Paths.home || "";
        if (!home)
            return "";
        for (let i = 0; i < candidates.length; i++) {
            const name = candidates[i];
            if (name && name !== cur)
                return home + "/" + name;
        }
        return "";
    }

    function cwdPath(): string {
        if (isArchiveBrowse)
            return "";

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
            // Real FS names only under Home (never remap place keys).
            return Paths.home + "/" + cwd.slice(1).join("/");
        }
        if (cwd[0] === "")
            return "/" + cwd.slice(1).join("/");
        return cwd.join("/");
    }

    function navigateToThisPC(): void {
        clearArchiveBrowse();
        cwd = ["ThisPC"];
        selection = [];
        resetSearchOnNavigate();
        statusText = qsTr("此电脑");
    }

    function navigateToPlace(place: string): void {
        if (place === "ThisPC") {
            navigateToThisPC();
            return;
        }
        clearArchiveBrowse();
        if (place === "Trash") {
            navigateToTrash();
            return;
        }
        if (place === "Home")
            cwd = ["Home"];
        else
            cwd = ["Home", preferredFolderName(place)];
        selection = [];
        resetSearchOnNavigate();
        statusText = displayPath();
    }

    function navigateToTrash(): void {
        const t = trashPath();
        // Ensure trash dirs exist
        Quickshell.execDetached(["mkdir", "-p", t, Paths.home + "/.local/share/Trash/info"]);
        openAbsolutePath(t);
        statusText = qsTr("回收站");
    }

    function pushDir(name: string): void {
        if (isArchiveBrowse) {
            pushArchiveDir(name);
            return;
        }
        if (isThisPC)
            return;
        cwd = cwd.concat([name]);
        selection = [];
        resetSearchOnNavigate();
        statusText = displayPath();
    }

    function popDir(): void {
        if (isArchiveBrowse) {
            popArchiveDir();
            return;
        }
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
        resetSearchOnNavigate();
        statusText = isThisPC ? qsTr("此电脑") : displayPath();
    }

    function sliceCwd(toIndex: int): void {
        if (toIndex < 0 || toIndex >= cwd.length)
            return;
        cwd = cwd.slice(0, toIndex + 1);
        // Phone root alone → This PC
        if (cwd.length === 1 && cwd[0] === "Phone")
            cwd = ["ThisPC"];
        selection = [];
        resetSearchOnNavigate();
        statusText = isThisPC ? qsTr("此电脑") : displayPath();
    }

    function openAbsolutePath(path: string): void {
        if (!path || path.length === 0) {
            navigateToThisPC();
            return;
        }
        // Leaving virtual archive unless opening into it
        if (isArchiveBrowse && !(path.startsWith("archive://")))
            clearArchiveBrowse();
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
            // Keep real FS names (Pictures ≠ 图片). Never rewrite to place keys.
            const rel = path.slice(home.length + 1).split("/").filter(s => s.length > 0);
            if (rel.length > 0)
                cwd = ["Home"].concat(rel);
            else
                cwd = ["Home"];
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
        resetSearchOnNavigate();
        statusText = displayPath();
        // path binding updates FileSystemModel; skip bumpRefresh (empty-path race)
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
        // Home / place folders: always show Chinese place label (图片 not Pictures)
        if (entry.isDir && cwd.length === 1 && cwd[0] === "Home") {
            const key = placeKeyForFsName(entry.name || "");
            if (key && placeLabels[key])
                return placeLabels[key];
        }
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

    // Convert free-text search into QDir nameFilters (wildcard patterns).
    // Empty query → [] (no filter). Plain substring → *query*.
    // If user already types * or ?, pass through as a single pattern.
    function nameFiltersForSearch(): list<string> {
        const q = (nameFilter || "").trim();
        if (!q.length)
            return [];
        if (q.indexOf("*") >= 0 || q.indexOf("?") >= 0)
            return [q];
        // Escape QDir wildcard meta in literal search
        const escaped = q.replace(/\\/g, "\\\\").replace(/\*/g, "\\*").replace(/\?/g, "\\?");
        return ["*" + escaped + "*"];
    }

    function setSearchScope(scope: string): void {
        const s = scope === "global" ? "global" : "local";
        if (searchScope === s)
            return;
        searchScope = s;
        if (s === "local") {
            globalResults = [];
            globalSearchBusy = false;
            globalSearchQuery = "";
            if (nameFilter.length)
                statusText = qsTr("搜索：%1").arg(nameFilter);
            else
                statusText = qsTr("就绪");
            bumpRefresh();
        } else {
            // Entering global: clear local filter effect on folder view
            statusText = qsTr("全局搜索");
        }
    }

    function toggleSearchScope(): void {
        setSearchScope(searchScope === "global" ? "local" : "global");
    }

    function setGlobalResults(list: var, query: string, busy: bool): void {
        globalResults = list || [];
        globalSearchQuery = query || "";
        globalSearchBusy = !!busy;
        if (busy)
            statusText = qsTr("正在全局搜索…");
        else if ((query || "").length)
            statusText = qsTr("全局：%1 · %2 项").arg(query).arg(globalResults.length);
        else
            statusText = qsTr("全局搜索");
    }

    function setNameFilter(q: string): void {
        const next = q || "";
        const prev = nameFilter;
        nameFilter = next;
        if (searchScope === "global") {
            // Folder filter not applied; global search driven by toolbar
            if (!next.length) {
                globalResults = [];
                globalSearchQuery = "";
                globalSearchBusy = false;
                statusText = qsTr("全局搜索");
            }
            return;
        }
        if (nameFilter.length)
            statusText = qsTr("搜索：%1").arg(nameFilter);
        else
            statusText = qsTr("就绪");
        // Clearing search must always re-scan (nameFilters binding + model refresh)
        if (prev !== next && !next.length)
            bumpRefresh();
    }

    function resetSearchOnNavigate(): void {
        // Leaving folder context → drop global mode and filter
        if (searchScope === "global") {
            searchScope = "local";
            globalResults = [];
            globalSearchBusy = false;
            globalSearchQuery = "";
        }
        nameFilter = "";
    }

    function clearNameFilter(): void {
        nameFilter = "";
        if (searchScope === "global") {
            globalResults = [];
            globalSearchQuery = "";
            globalSearchBusy = false;
            statusText = qsTr("全局搜索");
            return;
        }
        statusText = qsTr("就绪");
        bumpRefresh();
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

    function setSortBy(key: string): void {
        const k = key || "name";
        if (["name", "size", "type", "mtime"].indexOf(k) < 0)
            return;
        if (sortBy === k) {
            // click same key → toggle direction (common FM UX)
            sortReverse = !sortReverse;
        } else {
            sortBy = k;
            sortReverse = false;
        }
        statusText = sortLabel();
        settingsChanged();
    }

    function setSortReverse(rev: bool): void {
        sortReverse = !!rev;
        statusText = sortLabel();
        settingsChanged();
    }

    function toggleSortReverse(): void {
        setSortReverse(!sortReverse);
    }

    function setFoldersFirst(on: bool): void {
        foldersFirst = !!on;
        statusText = foldersFirst ? qsTr("文件夹优先") : qsTr("不优先文件夹");
        settingsChanged();
    }

    function toggleFoldersFirst(): void {
        setFoldersFirst(!foldersFirst);
    }

    function sortLabel(): string {
        let key = qsTr("名称");
        if (sortBy === "size")
            key = qsTr("大小");
        else if (sortBy === "type")
            key = qsTr("类型");
        else if (sortBy === "mtime")
            key = qsTr("修改时间");
        const dir = sortReverse ? qsTr("降序") : qsTr("升序");
        return qsTr("排序：%1 · %2").arg(key).arg(dir);
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
        if (data.sortBy === "name" || data.sortBy === "size" || data.sortBy === "type" || data.sortBy === "mtime")
            sortBy = data.sortBy;
        if (typeof data.sortReverse === "boolean")
            sortReverse = data.sortReverse;
        if (typeof data.foldersFirst === "boolean")
            foldersFirst = data.foldersFirst;
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
            sortBy: sortBy,
            sortReverse: sortReverse,
            foldersFirst: foldersFirst,
            favorites: favorites
        }, null, 2);
    }
    // Resolve ZH/EN place pairs under $HOME: pick candidate with more children
    Process {
        id: resolvePlacesProc
        running: true
        command: ["python3", "/home/villode/.config/quickshell/caelestia/modules/filemanager/resolve-places.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                const lines = text.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    const line = (lines[i] || "").trim();
                    if (!line.length)
                        continue;
                    const bar = line.indexOf("|");
                    if (bar < 0)
                        continue;
                    const key = line.slice(0, bar);
                    const name = line.slice(bar + 1);
                    if (key.length && name.length)
                        map[key] = name;
                }
                root.placeResolved = map;
            }
        }
    }



    Process {
        id: archiveListProc
        command: ["true"]
        running: false
        stdout: StdioCollector {
            id: archiveListOut
            onStreamFinished: {
                // Prefer property access like other modules
                root.parseArchiveListing(text);
            }
        }
        stderr: StdioCollector {
            id: archiveListErr
        }
        onExited: code => {
            if (!root.isArchiveBrowse)
                return;
            // Ensure parse even if streamFinished order is weird
            if (root.archiveLoading) {
                let raw = "";
                try {
                    raw = archiveListOut.text || "";
                } catch (e) {
                    raw = "";
                }
                if (raw && raw.length)
                    root.parseArchiveListing(raw);
            }
            if (code !== 0 && !root.archiveEntries.length) {
                root.archiveLoading = false;
                let err = "";
                try {
                    err = (archiveListErr.text || "").trim();
                } catch (e2) {
                    err = "";
                }
                root.archiveError = err.length ? err.slice(0, 160) : qsTr("无法打开压缩包");
                root.statusText = root.archiveError;
                root.archiveNonce = root.archiveNonce + 1;
            }
        }
    }

}
