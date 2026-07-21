pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import qs.utils

// File ops + compress/extract with progress streaming
Item {
    id: root
    width: 0
    height: 0
    visible: false

    required property var state
    property var showProperties: null
    // Optional overlay: openJob/setProgress/finishOk/finishFail
    property var jobUi: null
    // Optional confirm: openTrash(paths) / openDelete(paths)
    property var confirmUi: null
    // Optional name dialog: openRename(path) / openMkdir()
    property var nameUi: null

    function requestTrash(paths: list<string>): void {
        if (!paths || !paths.length)
            return;
        if (confirmUi && typeof confirmUi.openTrash === "function")
            confirmUi.openTrash(paths);
        else
            trash(paths);
    }

    function requestDelete(paths: list<string>): void {
        if (!paths || !paths.length)
            return;
        if (confirmUi && typeof confirmUi.openDelete === "function")
            confirmUi.openDelete(paths);
        else
            deletePermanent(paths);
    }

    property bool busy: false
    property string jobKind: ""
    property real progress: -1
    property string jobTitle: ""
    property string jobDetail: ""

    readonly property var archiveExts: [
        ".zip", ".7z", ".rar", ".tar", ".tar.gz", ".tgz", ".tar.xz", ".txz",
        ".tar.bz2", ".tbz2", ".tar.zst", ".tzst", ".gz", ".xz", ".bz2", ".zst"
    ]

    function selectedOr(path: string): list<string> {
        if (root.state.selection.length > 0)
            return root.state.selection;
        if (path && path.length)
            return [path];
        return [];
    }

    function openPaths(paths: list<string>): void {
        for (let i = 0; i < paths.length; i++)
            Quickshell.execDetached(["xdg-open", paths[i]]);
        if (paths.length)
            root.state.statusText = qsTr("已打开 %1 项").arg(paths.length);
    }

    function openEntry(isDir: bool, name: string, path: string): void {
        if (isDir)
            root.state.pushDir(name);
        else
            Quickshell.execDetached(["xdg-open", path]);
    }

    function copy(paths: list<string>): void {
        if (!paths.length)
            return;
        root.state.clipboardMode = "copy";
        root.state.clipboardPaths = paths.slice();
        root.state.statusText = qsTr("已复制 %1 项").arg(paths.length);
    }

    function cut(paths: list<string>): void {
        if (!paths.length)
            return;
        root.state.clipboardMode = "cut";
        root.state.clipboardPaths = paths.slice();
        root.state.statusText = qsTr("已剪切 %1 项 · 粘贴后移走").arg(paths.length);
    }

    function paste(): void {
        const mode = root.state.clipboardMode;
        const paths = root.state.clipboardPaths;
        if (!mode || !paths.length) {
            root.state.statusText = qsTr("剪贴板为空");
            return;
        }
        const destDir = root.state.cwdPath();
        dropInto(paths, destDir, mode === "cut" ? "move" : "copy");
        if (mode === "cut") {
            root.state.clipboardMode = "";
            root.state.clipboardPaths = [];
        }
    }


    function parentDir(path: string): string {
        if (!path || path === "/")
            return "/";
        let p = path;
        while (p.length > 1 && p.endsWith("/"))
            p = p.slice(0, -1);
        const i = p.lastIndexOf("/");
        if (i <= 0)
            return "/";
        return p.slice(0, i) || "/";
    }

    function normalizeLocalPath(urlOrPath: string): string {
        if (!urlOrPath)
            return "";
        let p = String(urlOrPath).trim();
        if (p.startsWith("file://")) {
            // strip scheme; decode %XX
            p = decodeURIComponent(p.slice(7));
            // file:///path → /path ; file://localhost/path
            if (p.startsWith("localhost/"))
                p = p.slice("localhost".length);
        }
        while (p.length > 1 && p.endsWith("/"))
            p = p.slice(0, -1);
        return p;
    }

    function pathsFromDrop(drop: var): list<string> {
        const out = [];
        if (!drop)
            return out;
        if (drop.hasUrls && drop.urls && drop.urls.length) {
            for (let i = 0; i < drop.urls.length; i++) {
                const p = normalizeLocalPath(drop.urls[i].toString());
                if (p.length)
                    out.push(p);
            }
            return out;
        }
        if (drop.hasText && drop.text) {
            const lines = String(drop.text).split(/\r?\n/);
            for (let j = 0; j < lines.length; j++) {
                let line = lines[j].trim();
                if (!line.length)
                    continue;
                const p = normalizeLocalPath(line);
                if (p.length)
                    out.push(p);
            }
        }
        return out;
    }

    // mode: "copy" | "move". destDir absolute path (current folder or target folder).
    // Returns number of items scheduled.
    function dropInto(paths: list<string>, destDir: string, mode: string): int {
        if (!paths || !paths.length || !destDir || !destDir.length) {
            root.state.statusText = qsTr("无法放置");
            return 0;
        }
        if (root.state.isThisPC) {
            root.state.statusText = qsTr("请先进入文件夹再放置");
            return 0;
        }
        while (destDir.length > 1 && destDir.endsWith("/"))
            destDir = destDir.slice(0, -1);

        const op = (mode === "move") ? "move" : "copy";
        let n = 0;
        const jobs = [];
        for (let i = 0; i < paths.length; i++) {
            const src = normalizeLocalPath(paths[i]);
            if (!src.length)
                continue;
            // Skip dropping a folder into itself or into its own child
            if (src === destDir || destDir.startsWith(src + "/"))
                continue;
            // Skip no-op: already in dest
            if (parentDir(src) === destDir && op === "move")
                continue;
            const base = src.split("/").pop() || "item";
            const dest = destDir + "/" + base;
            if (src === dest)
                continue;
            jobs.push({ src: src, dest: dest });
            n++;
        }
        if (!n) {
            root.state.statusText = qsTr("没有可放置的项");
            return 0;
        }

        // Prefer gio for trash-aware move and remote/gvfs; fall back friendly message
        for (let k = 0; k < jobs.length; k++) {
            const j = jobs[k];
            if (op === "copy")
                Quickshell.execDetached(["gio", "copy", "-p", j.src, j.dest]);
            else
                Quickshell.execDetached(["gio", "move", j.src, j.dest]);
        }
        root.state.statusText = op === "move"
            ? qsTr("已移动 %1 项").arg(n)
            : qsTr("已复制 %1 项").arg(n);
        // Refresh after short delay so gio can finish first write
        Qt.callLater(() => root.state.bumpRefresh());
        refreshTimer.restart();
        return n;
    }

    function dropFromEvent(drop: var, destDir: string): int {
        const paths = pathsFromDrop(drop);
        if (!paths.length) {
            root.state.statusText = qsTr("拖放内容无法识别");
            return 0;
        }
        // Qt.MoveAction / LinkAction → move when proposed; otherwise copy
        let mode = "copy";
        try {
            if (drop.proposedAction === Qt.MoveAction)
                mode = "move";
            else if (drop.supportedActions & Qt.MoveAction) {
                // Modifier: if only Move is proposed by source cut, use move
                // External file managers often use Copy by default
            }
        } catch (e) {}
        // Ctrl = force copy, Shift = force move (common desktop convention)
        // Drop event has no modifiers in Qt Quick DropArea; use proposedAction only.
        return dropInto(paths, destDir, mode);
    }

    Timer {
        id: refreshTimer
        interval: 450
        repeat: false
        onTriggered: root.state.bumpRefresh()
    }

    function trash(paths: list<string>): void {
        if (!paths.length)
            return;
        for (let i = 0; i < paths.length; i++)
            Quickshell.execDetached(["gio", "trash", paths[i]]);
        root.state.setSelection([]);
        root.state.statusText = qsTr("已移到回收站 %1 项").arg(paths.length);
        Qt.callLater(() => root.state.bumpRefresh());
    }

    // Permanent delete (rm -rf) — caller must confirm first
    function deletePermanent(paths: list<string>): void {
        if (!paths.length)
            return;
        for (let i = 0; i < paths.length; i++) {
            const p = paths[i];
            if (!p || p === "/" || p === Paths.home)
                continue;
            Quickshell.execDetached(["rm", "-rf", "--", p]);
        }
        root.state.setSelection([]);
        root.state.statusText = qsTr("已永久删除 %1 项").arg(paths.length);
        Qt.callLater(() => root.state.bumpRefresh());
    }

    function requestEmptyTrash(): void {
        if (confirmUi && typeof confirmUi.openEmptyTrash === "function")
            confirmUi.openEmptyTrash();
        else
            emptyTrash();
    }

    // Wipe XDG trash files + info (caller should confirm)
    function emptyTrash(): void {
        const files = root.state.trashPath();
        const info = Paths.home + "/.local/share/Trash/info";
        const script =
            "set -euo pipefail; " +
            "f=" + shellQuote(files) + "; i=" + shellQuote(info) + "; " +
            "mkdir -p \"$f\" \"$i\"; " +
            "find \"$f\" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true; " +
            "find \"$i\" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true";
        Quickshell.execDetached(["bash", "-c", script]);
        root.state.setSelection([]);
        root.state.statusText = qsTr("回收站已清空");
        Qt.callLater(() => root.state.bumpRefresh());
        // delayed second refresh in case rm is slow
        emptyRefresh.restart();
    }

    Timer {
        id: emptyRefresh
        interval: 400
        repeat: false
        onTriggered: root.state.bumpRefresh()
    }

    function requestMkdir(): void {
        if (nameUi && typeof nameUi.openMkdir === "function")
            nameUi.openMkdir();
        else
            mkdir("");
    }

    function requestRename(path: string): void {
        const p = path || (root.state.selection.length === 1 ? root.state.selection[0] : "");
        if (!p)
            return;
        if (nameUi && typeof nameUi.openRename === "function")
            nameUi.openRename(p);
        else {
            // fallback: no dialog
            root.state.statusText = qsTr("无法打开重命名对话框");
        }
    }

    function mkdir(name: string): void {
        let n = (name || "").trim();
        if (!n.length)
            n = qsTr("新建文件夹");
        if (n.indexOf("/") >= 0 || n === "." || n === "..") {
            root.state.statusText = qsTr("无效的文件夹名称");
            return;
        }
        const dest = root.state.cwdPath() + "/" + n;
        Quickshell.execDetached(["mkdir", "-p", dest]);
        root.state.statusText = qsTr("已创建「%1」").arg(n);
        Qt.callLater(() => root.state.bumpRefresh());
        refreshTimer.restart();
    }

    function rename(path: string, newName: string): void {
        if (!path || !newName)
            return;
        const n = String(newName).trim();
        if (!n.length || n.indexOf("/") >= 0 || n === "." || n === "..") {
            root.state.statusText = qsTr("无效的名称");
            return;
        }
        const parent = path.split("/").slice(0, -1).join("/") || "/";
        const dest = parent + "/" + n;
        if (dest === path) {
            root.state.statusText = qsTr("名称未更改");
            return;
        }
        Quickshell.execDetached(["mv", path, dest]);
        root.state.setSelection([dest]);
        root.state.statusText = qsTr("已重命名为「%1」").arg(n);
        Qt.callLater(() => root.state.bumpRefresh());
        refreshTimer.restart();
    }

    function properties(path: string): void {
        const p = path || (root.state.selection[0] ?? "") || root.state.cwdPath();
        if (!p)
            return;
        if (typeof root.showProperties === "function")
            root.showProperties(p);
        else
            root.state.statusText = qsTr("属性：%1").arg(Paths.shortenHome(p));
    }

    function isArchivePath(path: string): bool {
        if (!path)
            return false;
        const lower = path.toLowerCase();
        for (let i = 0; i < archiveExts.length; i++) {
            if (lower.endsWith(archiveExts[i]))
                return true;
        }
        return false;
    }

    function anyArchive(paths: list<string>): bool {
        for (let i = 0; i < paths.length; i++) {
            if (isArchivePath(paths[i]))
                return true;
        }
        return false;
    }

    function stripArchiveExt(name: string): string {
        const lower = name.toLowerCase();
        const multi = [".tar.gz", ".tar.xz", ".tar.bz2", ".tar.zst", ".tgz", ".txz", ".tbz2", ".tzst"];
        for (let i = 0; i < multi.length; i++) {
            if (lower.endsWith(multi[i]))
                return name.slice(0, name.length - multi[i].length);
        }
        const i = name.lastIndexOf(".");
        return i > 0 ? name.slice(0, i) : name;
    }

    function archiveBaseName(paths: list<string>): string {
        if (paths.length === 1) {
            const base = paths[0].split("/").pop() || "archive";
            return stripArchiveExt(base);
        }
        return qsTr("压缩包");
    }

    function shellQuote(s: string): string {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    function uiOpen(title: string, detail: string): void {
        progress = -1;
        jobTitle = title;
        jobDetail = detail || "";
        if (jobUi && typeof jobUi.openJob === "function")
            jobUi.openJob(title, detail || "");
    }

    function uiProgress(pct: real, text: string): void {
        if (pct >= 0)
            progress = pct;
        if (text && text.length)
            jobDetail = text;
        root.state.statusText = text && text.length ? text : (pct >= 0 ? qsTr("%1% · %2").arg(Math.round(pct)).arg(jobTitle) : jobTitle);
        if (jobUi && typeof jobUi.setProgress === "function")
            jobUi.setProgress(pct, text || "");
    }

    function uiOk(text: string): void {
        progress = 100;
        if (jobUi && typeof jobUi.finishOk === "function")
            jobUi.finishOk(text || "");
    }

    function uiFail(text: string): void {
        if (jobUi && typeof jobUi.finishFail === "function")
            jobUi.finishFail(text || "");
    }

    // Python runner: parse 7z -bsp1 progress and emit PROGRESS:n lines
    function py7zRunner(jobsJson: string): string {
        // jobsJson: [{"cmd":[...],"label":"..."}, ...]
        // Keep as one -c script; use json via env to avoid quote hell
        return "import json,os,re,subprocess,sys\n" +
            "jobs=json.loads(os.environ['FM_JOBS'])\n" +
            "n=max(1,len(jobs))\n" +
            "last=-1\n" +
            "def emit(p,msg=''):\n" +
            "  global last\n" +
            "  p=max(0,min(100,int(p)))\n" +
            "  if p!=last or msg:\n" +
            "    last=p\n" +
            "    print(f'PROGRESS:{p}|{msg}',flush=True)\n" +
            "for i,job in enumerate(jobs):\n" +
            "  cmd=job['cmd']; label=job.get('label','')\n" +
            "  print(f'STAGE:{i+1}/{n}|{label}',flush=True)\n" +
            "  base=i*100.0/n\n" +
            "  emit(base,label)\n" +
            "  p=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,bufsize=0)\n" +
            "  buf=b''\n" +
            "  while True:\n" +
            "    ch=p.stdout.read(1)\n" +
            "    if not ch: break\n" +
            "    buf+=ch\n" +
            "    if len(buf)>240: buf=buf[-240:]\n" +
            "    t=buf.decode('utf-8','replace')\n" +
            "    ms=list(re.finditer(r'(\\d{1,3})%', t))\n" +
            "    if ms:\n" +
            "      pct=int(ms[-1].group(1))\n" +
            "      emit(base+pct/n,label)\n" +
            "  rc=p.wait()\n" +
            "  if rc!=0:\n" +
            "    print(f'FAIL:{rc}|{label}',flush=True)\n" +
            "    sys.exit(rc)\n" +
            "  emit(base+100.0/n,label)\n" +
            "print('OK',flush=True)\n";
    }

    function runPythonJobs(kind: string, jobs: var, title: string, detail: string): void {
        if (busy) {
            root.state.statusText = qsTr("已有压缩/解压任务进行中");
            return;
        }
        busy = true;
        jobKind = kind;
        root.state.statusText = title;
        uiOpen(title, detail || "");
        const json = JSON.stringify(jobs);
        jobProc.running = false;
        // environment via env prefix in bash
        jobProc.command = [
            "bash", "-c",
            "export FM_JOBS=" + shellQuote(json) + "; " +
            "python3 -u -c " + shellQuote(py7zRunner(json))
        ];
        jobProc.running = true;
    }

    function runSoftJob(kind: string, script: string, title: string, detail: string): void {
        // tar etc. without real percent → indeterminate spinner + soft pulse
        if (busy) {
            root.state.statusText = qsTr("已有压缩/解压任务进行中");
            return;
        }
        busy = true;
        jobKind = kind;
        progress = -1;
        root.state.statusText = title;
        uiOpen(title, detail || "");
        softPulse.running = true;
        jobProc.running = false;
        jobProc.command = ["bash", "-c", script];
        jobProc.running = true;
    }

    // format: "zip" | "7z" | "tar.gz" | "tar.xz" | "tar.zst"
    function compress(paths: list<string>, format: string): void {
        if (!paths || !paths.length)
            return;
        const cwd = root.state.cwdPath();
        if (!cwd) {
            root.state.statusText = qsTr("当前目录不可写");
            return;
        }
        const fmt = format || "zip";
        const base = archiveBaseName(paths);
        const title = qsTr("正在压缩…");
        const detail = qsTr("格式：%1 · %2 项").arg(fmt).arg(paths.length);
        const baseQ = shellQuote(cwd + "/" + base);
        const quotedPaths = paths.map(p => shellQuote(p)).join(" ");

        if (fmt === "zip" || fmt === "7z") {
            const type = fmt === "7z" ? "7z" : "zip";
            const ext = fmt === "7z" ? ".7z" : ".zip";
            const wrap = "set -euo pipefail; base=" + baseQ + "; out=\"$base" + ext + "\"; n=1; " +
                "while [ -e \"$out\" ]; do out=\"$base-$n" + ext + "\"; n=$((n+1)); done; " +
                "export FM_JOBS=$(python3 -c " + shellQuote(
                    "import json,sys; out=sys.argv[1]; paths=sys.argv[2:]; " +
                    "print(json.dumps([{'cmd':['7z','a','-t" + type + "','-y','-bsp1','-bso0',out]+paths,'label':out.rsplit('/',1)[-1]}]))"
                ) + " \"$out\" " + quotedPaths + "); " +
                "python3 -u -c " + shellQuote(py7zRunner("")) + "; echo RESULT_OUT:$out";
            busy = true;
            jobKind = "compress";
            root.state.statusText = title;
            uiOpen(title, detail);
            jobProc.running = false;
            jobProc.command = ["bash", "-c", wrap];
            jobProc.running = true;
            return;
        }

        let script = "";
        if (fmt === "tar.gz") {
            script = "set -euo pipefail; base=" + baseQ + "; out=\"$base.tar.gz\"; n=1; " +
                "while [ -e \"$out\" ]; do out=\"$base-$n.tar.gz\"; n=$((n+1)); done; " +
                "tar -czf \"$out\" -- " + quotedPaths + "; echo \"$out\"";
        } else if (fmt === "tar.xz") {
            script = "set -euo pipefail; base=" + baseQ + "; out=\"$base.tar.xz\"; n=1; " +
                "while [ -e \"$out\" ]; do out=\"$base-$n.tar.xz\"; n=$((n+1)); done; " +
                "tar -cJf \"$out\" -- " + quotedPaths + "; echo \"$out\"";
        } else if (fmt === "tar.zst") {
            script = "set -euo pipefail; base=" + baseQ + "; out=\"$base.tar.zst\"; n=1; " +
                "while [ -e \"$out\" ]; do out=\"$base-$n.tar.zst\"; n=$((n+1)); done; " +
                "tar --zstd -cf \"$out\" -- " + quotedPaths + "; echo \"$out\"";
        } else {
            root.state.statusText = qsTr("不支持的格式：%1").arg(fmt);
            return;
        }
        runSoftJob("compress", script, title, detail);
    }

    // mode: "here" | "folder"
    function extract(paths: list<string>, mode: string): void {
        const list = [];
        for (let i = 0; i < (paths || []).length; i++) {
            if (isArchivePath(paths[i]))
                list.push(paths[i]);
        }
        if (!list.length) {
            root.state.statusText = qsTr("请选择压缩包");
            return;
        }
        const m = mode || "here";
        const title = m === "folder" ? qsTr("正在解压到新文件夹…") : qsTr("正在解压…");
        const names = list.map(p => p.split("/").pop()).join(", ");
        const detail = names;

        // Build jobs for python 7z progress runner
        const jobs = [];
        for (let i = 0; i < list.length; i++) {
            const arc = list[i];
            const parent = arc.split("/").slice(0, -1).join("/") || "/";
            const name = arc.split("/").pop() || "archive";
            const folder = parent + "/" + stripArchiveExt(name);
            let outDir = parent;
            if (m === "folder")
                outDir = folder;
            const cmd = ["7z", "x", "-y", "-bsp1", "-bso0", "-o" + outDir, "--", arc];
            jobs.push({
                cmd: cmd,
                label: name,
                mkdir: m === "folder" ? folder : ""
            });
        }

        // Pre-mkdir folders then run progress python
        const mkdirBits = jobs.filter(j => j.mkdir).map(j => "mkdir -p " + shellQuote(j.mkdir)).join("; ");
        const jobsClean = jobs.map(j => ({
                cmd: j.cmd,
                label: j.label
            }));
        const wrap = (mkdirBits ? mkdirBits + "; " : "") +
            "export FM_JOBS=" + shellQuote(JSON.stringify(jobsClean)) + "; " +
            "python3 -u -c " + shellQuote(py7zRunner(""));

        busy = true;
        jobKind = "extract";
        progress = 0;
        root.state.statusText = title;
        uiOpen(title, detail);
        jobProc.running = false;
        jobProc.command = ["bash", "-c", wrap];
        jobProc.running = true;
    }

    Timer {
        id: softPulse
        interval: 400
        repeat: true
        running: false
        property real t: 0
        onTriggered: {
            if (!root.busy || root.progress >= 0) {
                running = false;
                return;
            }
            t += 0.08;
            // gentle fake progress up to 90% while waiting
            const fake = Math.min(90, 10 + t * 25);
            if (root.jobUi && typeof root.jobUi.setProgress === "function")
                root.jobUi.setProgress(-1, root.jobDetail);
            root.state.statusText = root.jobTitle + "…";
        }
    }

    Process {
        id: jobProc
        command: ["true"]
        stdout: SplitParser {
            onRead: line => {
                const s = String(line || "").trim();
                if (!s.length)
                    return;
                if (s.startsWith("PROGRESS:")) {
                    const rest = s.slice("PROGRESS:".length);
                    const pipe = rest.indexOf("|");
                    const pct = Number(pipe >= 0 ? rest.slice(0, pipe) : rest);
                    const msg = pipe >= 0 ? rest.slice(pipe + 1) : "";
                    if (!isNaN(pct))
                        root.uiProgress(pct, msg ? qsTr("%1 · %2%").arg(msg).arg(Math.round(pct)) : qsTr("%1%").arg(Math.round(pct)));
                } else if (s.startsWith("STAGE:")) {
                    const rest = s.slice("STAGE:".length);
                    const pipe = rest.indexOf("|");
                    const stage = pipe >= 0 ? rest.slice(0, pipe) : rest;
                    const label = pipe >= 0 ? rest.slice(pipe + 1) : "";
                    root.jobDetail = label || stage;
                    if (root.jobUi && typeof root.jobUi.setProgress === "function")
                        root.jobUi.setProgress(root.progress, label ? qsTr("正在处理：%1").arg(label) : stage);
                } else if (s.startsWith("RESULT_OUT:")) {
                    root.jobDetail = s.slice("RESULT_OUT:".length).split("/").pop();
                } else if (s === "OK") {
                    // handled on exit
                } else if (s.startsWith("FAIL:")) {
                    // handled on exit
                } else if (s.startsWith("/") || s.endsWith(".zip") || s.endsWith(".7z") || s.endsWith(".tar.gz") || s.endsWith(".tar.xz") || s.endsWith(".tar.zst")) {
                    root.jobDetail = s.split("/").pop();
                }
            }
        }
        stderr: StdioCollector {
            id: jobErr
        }
        onExited: code => {
            softPulse.running = false;
            root.busy = false;
            const kind = root.jobKind;
            root.jobKind = "";
            if (code === 0) {
                const msg = kind === "compress" ? (root.jobDetail ? qsTr("已压缩：%1").arg(root.jobDetail) : qsTr("压缩完成")) : qsTr("解压完成");
                root.state.statusText = msg;
                root.uiOk(msg);
                root.state.bumpRefresh();
            } else {
                const err = (jobErr.text || "").trim();
                const msg = err.length ? qsTr("失败：%1").arg(err.slice(0, 120)) : qsTr("压缩/解压失败");
                root.state.statusText = msg;
                root.uiFail(msg);
            }
            root.progress = -1;
        }
    }
}
