pragma Singleton

import QtQuick
import Quickshell

// Cross-window file drag for Villode FM without Qt Drag.Automatic (which freezes under QS+Hypr).
Singleton {
    id: root

    property bool active: false
    property var paths: []
    property string sourceCwd: ""
    property string primaryName: ""
    property string iconSource: ""
    property int count: 0
    property real globalX: 0
    property real globalY: 0
    property int sessionId: 0
    // Absolute path under the pointer in the hovered FM window (set by target)
    property string pendingDest: ""

    function begin(pathsList, cwd, name, icon) {
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
        primaryName = name || (list[0].split("/").pop() || "");
        iconSource = icon || "";
        count = list.length;
        sessionId = sessionId + 1;
        active = true;
    }

    function updateGlobal(gx, gy) {
        if (!active)
            return;
        globalX = gx;
        globalY = gy;
    }

    function end() {
        active = false;
        paths = [];
        sourceCwd = "";
        primaryName = "";
        iconSource = "";
        count = 0;
        pendingDest = "";
    }

    function takePaths() {
        const out = (paths && paths.length) ? paths.slice() : [];
        end();
        return out;
    }
}
