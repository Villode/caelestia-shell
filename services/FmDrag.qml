pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Cross-window FM drag without Qt Drag.Automatic.
// Drop completes on: source MouseArea release, OR hypr left-button release bind, OR overlay.
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
    property var dropHandler: null
    property bool bindInstalled: false

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
                next.push({ id: id, x: x, y: y, w: w, h: h, cwd: cwd || "" });
                found = true;
            } else {
                next.push(e);
            }
        }
        if (!found)
            next.push({ id: id, x: x, y: y, w: w, h: h, cwd: cwd || "" });
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
        // Left button release (bindl) anywhere → complete drop even outside FloatingWindow
        Quickshell.execDetached(["hyprctl", "keyword", "bindl", ", mouse:272, exec, qs -c caelestia ipc call fmdrag complete"]);
        Quickshell.execDetached(["hyprctl", "keyword", "bindl", ", mouse:273, exec, qs -c caelestia ipc call fmdrag cancel"]);
        bindInstalled = true;
    }

    function removeReleaseBind() {
        if (!bindInstalled)
            return;
        Quickshell.execDetached(["hyprctl", "keyword", "unbind", ", mouse:272"]);
        Quickshell.execDetached(["hyprctl", "keyword", "unbind", ", mouse:273"]);
        bindInstalled = false;
    }

    function begin(pathsList, cwd, name, icon, windowId, handler) {
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
        dropHandler = handler || null;
        pendingDest = cwd || "";
        pendingWindowId = windowId || "";
        sessionId = sessionId + 1;
        cursorReady = false;
        active = true;
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
        cancelled();
    }

    function completeDrop() {
        if (!active)
            return 0;
        const list = paths.slice();
        const win = windowAt(globalX, globalY);
        let dest = "";
        // 1) Window under cursor (most reliable for cross-window)
        if (win && win.cwd)
            dest = win.cwd;
        // 2) Explicit hover dest if same window as under cursor (subfolder tile)
        if (pendingDest && pendingDest.length) {
            if (!win || !pendingWindowId || pendingWindowId === (win.id || ""))
                dest = pendingDest;
        }
        if ((!dest || !dest.length) && sourceCwd)
            dest = sourceCwd;

        const foreign = !!(win && sourceWindowId && win.id !== sourceWindowId);

        const handler = dropHandler;
        const srcCwd = sourceCwd;
        end();

        if (!list.length || !dest || !dest.length) {
            cancelled();
            return 0;
        }
        if (!foreign && dest === srcCwd) {
            cancelled();
            return 0;
        }
        if (list.indexOf(dest) >= 0) {
            cancelled();
            return 0;
        }
        let n = 0;
        if (typeof handler === "function") {
            try {
                n = handler(list, dest) | 0;
            } catch (e) {
                n = 0;
            }
        }
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
        dropHandler = null;
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
                    const pos = JSON.parse(text());
                    if (pos && pos.x !== undefined)
                        root.updateGlobal(Number(pos.x), Number(pos.y));
                } catch (e) {}
            }
        }
    }
}
