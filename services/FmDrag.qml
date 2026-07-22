pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Cross-window FM drag without Qt Drag.Automatic.
// Windows register geometry (screen coords); hover uses that — not mapFromGlobal.
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

    // { id: string, x, y, w, h, cwd: string } — updated by each ManagerWindow
    property var windows: []

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

    // Topmost registered window under point (last registered that contains point —
    // windows list order is registration order; prefer highest y-overlap last open)
    function windowAt(gx, gy) {
        // Prefer non-source window under cursor (target), else source, else null.
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
                otherHit = e; // last non-source wins (later register ≈ later open)
        }
        return otherHit || sourceHit;
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
        pendingDest = "";
        pendingWindowId = "";
        sessionId = sessionId + 1;
        active = true;
    }

    function updateGlobal(gx, gy) {
        if (!active)
            return;
        if (gx === globalX && gy === globalY)
            return;
        globalX = gx;
        globalY = gy;
    }

    function end() {
        active = false;
        paths = [];
        sourceCwd = "";
        sourceWindowId = "";
        primaryName = "";
        iconSource = "";
        count = 0;
        pendingDest = "";
        pendingWindowId = "";
    }

    function takePaths() {
        const out = (paths && paths.length) ? paths.slice() : [];
        end();
        return out;
    }
}
