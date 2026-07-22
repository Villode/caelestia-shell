pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Cross-window FM drag without Qt Drag.Automatic.
Singleton {
    id: root

    property bool active: false
    property var paths: []
    property string sourceCwd: ""
    property string sourceWindowId: ""
    property string primaryName: ""
    property string iconSource: ""
    property int count: 0
    property real globalX: 0
    property real globalY: 0
    property int sessionId: 0
    property string pendingDest: ""
    property string pendingWindowId: ""
    property real hotX: 18
    property real hotY: 18
    property bool cursorReady: false
    property var windows: []
    property bool bindInstalled: false
    property string lastStatus: ""

    signal finished(int moved)
    signal cancelled()


    function registerWindow(id, x, y, w, h, cwd) {
        if (!id)
            return;
        const next = [];
        let found = false;
        for (let i = 0; i < windows.length; i++) {
            const e = windows[i];
            if (!e || !e.id)
                continue;
            if (e.id === id) {
                next.push({ id: id, x: Number(x) || 0, y: Number(y) || 0, w: Number(w) || 0, h: Number(h) || 0, cwd: cwd || "" });
                found = true;
            } else {
                next.push(e);
            }
        }
        if (!found)
            next.push({ id: id, x: Number(x) || 0, y: Number(y) || 0, w: Number(w) || 0, h: Number(h) || 0, cwd: cwd || "" });
        windows = next;
    }

    function unregisterWindow(id) {
        if (!id)
            return;
        const next = [];
        for (let i = 0; i < windows.length; i++) {
            const e = windows[i];
            if (e && e.id !== id)
                next.push(e);
        }
        windows = next;
    }

    function windowAt(gx, gy) {
        let sourceHit = null;
        let otherHit = null;
        for (let i = 0; i < windows.length; i++) {
            const e = windows[i];
            if (!e || !e.w || !e.h)
                continue;
            if (gx < e.x || gy < e.y || gx >= e.x + e.w || gy >= e.y + e.h)
                continue;
            if (sourceWindowId && e.id === sourceWindowId)
                sourceHit = e;
            else
                otherHit = e;
        }
        return otherHit || sourceHit;
    }

    function installReleaseBind() {
        if (bindInstalled)
            return;
        // bindr = on release (bindl is "locked/session lock", NOT release)
        Quickshell.execDetached(["hyprctl", "keyword", "bindr", ", mouse:272, exec, qs -c caelestia ipc call fmdrag complete"]);
        Quickshell.execDetached(["hyprctl", "keyword", "bindr", ", mouse:273, exec, qs -c caelestia ipc call fmdrag cancel"]);
        bindInstalled = true;
    }

    function removeReleaseBind() {
        if (!bindInstalled)
            return;
        Quickshell.execDetached(["hyprctl", "keyword", "unbind", ", mouse:272"]);
        Quickshell.execDetached(["hyprctl", "keyword", "unbind", ", mouse:273"]);
        // Also clear release binds if hypr stores separately
        Quickshell.execDetached(["hyprctl", "keyword", "unbind", "r, mouse:272"]);
        Quickshell.execDetached(["hyprctl", "keyword", "unbind", "r, mouse:273"]);
        bindInstalled = false;
    }

    function begin(pathsList, cwd, name, icon, windowId) {
        const list = [];
        if (pathsList && pathsList.length) {
            for (let i = 0; i < pathsList.length; i++) {
                const p = String(pathsList[i] || "");
                if (p.length)
                    list.push(p);
            }
        }
        if (!list.length)
            return;
        paths = list;
        sourceCwd = cwd || "";
        sourceWindowId = windowId || "";
        primaryName = name || (list[0].split("/").pop() || "");
        iconSource = icon || "";
        count = list.length;
        pendingDest = cwd || "";
        pendingWindowId = windowId || "";
        sessionId = sessionId + 1;
        cursorReady = false;
        active = true;
        lastStatus = "";
        installReleaseBind();
        cursorSeed.running = true;
    }

    function updateGlobal(gx, gy) {
        if (!active)
            return;
        globalX = gx;
        globalY = gy;
        cursorReady = true;
        const win = windowAt(gx, gy);
        if (win) {
            pendingWindowId = win.id || "";
            if (win.cwd)
                pendingDest = win.cwd;
        }
    }

    function setHoverDest(windowId, dest) {
        if (!active)
            return;
        pendingWindowId = windowId || pendingWindowId;
        if (dest && dest.length)
            pendingDest = dest;
    }

    function cancel() {
        if (!active)
            return;
        end();
        lastStatus = qsTr("已取消拖动");
        cancelled();
    }

    function parentDir(path) {
        const p = String(path || "");
        const i = p.lastIndexOf("/");
        if (i <= 0)
            return "/";
        return p.slice(0, i);
    }

    function normalizePath(urlOrPath) {
        let s = String(urlOrPath || "");
        if (s.startsWith("file://")) {
            try {
                s = decodeURIComponent(s.slice(7));
            } catch (e) {
                s = s.slice(7);
            }
        }
        while (s.length > 1 && s.endsWith("/"))
            s = s.slice(0, -1);
        return s;
    }

    function movePaths(list, destDir) {
        destDir = normalizePath(destDir);
        if (!list || !list.length || !destDir)
            return 0;
        let n = 0;
        for (let i = 0; i < list.length; i++) {
            const src = normalizePath(list[i]);
            if (!src.length)
                continue;
            if (src === destDir || destDir.startsWith(src + "/"))
                continue;
            if (parentDir(src) === destDir)
                continue;
            const base = src.split("/").pop() || "item";
            const dest = destDir + "/" + base;
            if (src === dest)
                continue;
            Quickshell.execDetached(["gio", "move", src, dest]);
            n++;
        }
        return n;
    }

    function completeDrop() {
        if (!active)
            return 0;
        // Final cursor sample is best-effort; use last known global + pending
        const list = paths.slice();
        const win = windowAt(globalX, globalY);
        let dest = "";
        if (pendingDest && pendingDest.length)
            dest = pendingDest;
        if (win && win.cwd) {
            // Prefer pending if it is under this window; else window cwd
            if (!dest || !dest.length)
                dest = win.cwd;
            // If pending is from another window, use win under cursor
            if (pendingWindowId && win.id && pendingWindowId !== win.id)
                dest = win.cwd;
        }
        if ((!dest || !dest.length) && sourceCwd)
            dest = sourceCwd;

        const foreign = !!(win && sourceWindowId && win.id !== sourceWindowId)
            || !!(dest && sourceCwd && dest !== sourceCwd);

        end();

        if (!list.length || !dest || !dest.length) {
            lastStatus = qsTr("已取消拖动");
            cancelled();
            return 0;
        }
        if (!foreign && dest === sourceCwd) {
            lastStatus = qsTr("已取消（放到原目录）");
            cancelled();
            return 0;
        }
        if (list.indexOf(dest) >= 0) {
            lastStatus = qsTr("无法放到自身");
            cancelled();
            return 0;
        }

        const n = movePaths(list, dest);
        if (n > 0)
            lastStatus = foreign
                ? qsTr("已移动 %1 项到另一窗口").arg(n)
                : qsTr("已移动 %1 项").arg(n);
        else
            lastStatus = qsTr("没有可放置的项");
        finished(n);
        return n;
    }

    function end() {
        removeReleaseBind();
        active = false;
        paths = [];
        sourceCwd = "";
        sourceWindowId = "";
        primaryName = "";
        iconSource = "";
        count = 0;
        pendingDest = "";
        pendingWindowId = "";
        cursorReady = false;
    }

    Process {
        id: cursorSeed
        command: ["hyprctl", "cursorpos", "-j"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.active)
                    return;
                try {
                    const pos = JSON.parse(text);
                    if (pos && pos.x !== undefined)
                        root.updateGlobal(Number(pos.x), Number(pos.y));
                } catch (e) {}
            }
        }
    }

    // Poll button state via hyprctl devices? Not available.
    // Fallback: while active, poll cursor and detect when left button released using
    // `hyprctl getoption` no...
    // Use Process: python reading /dev/input requires root.
}
