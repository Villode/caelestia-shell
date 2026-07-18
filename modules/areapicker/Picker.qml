pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services

MouseArea {
    id: root

    required property LazyLoader loader
    required property ShellScreen screen

    // selecting: hover windows / drag a new rect
    // adjusting: resize handles, move, confirm / cancel
    property string mode: "selecting"
    property bool onClient
    property bool capturing: false

    property real realBorderWidth: onClient && mode === "selecting" ? (Hypr.options["general:border_size"] ?? 1) : 2
    property real realRounding: onClient && mode === "selecting" ? (Hypr.options["decoration:rounding"] ?? 0) : 0

    property real ssx
    property real ssy
    property real sx: 0
    property real sy: 0
    property real ex: screen.width
    property real ey: screen.height

    property real pressTime: 0
    property bool armed: false
    property bool didDrag: false
    readonly property real minSize: 8
    readonly property real handleSize: 10
    readonly property real edgeHit: 8

    // active resize/move interaction while adjusting
    property string dragKind: "" // "", "move", "n","s","e","w","ne","nw","se","sw"
    property real dragOriginX: 0
    property real dragOriginY: 0
    property real dragStartRsx: 0
    property real dragStartRsy: 0
    property real dragStartSw: 0
    property real dragStartSh: 0

    Timer {
        id: armTimer
        interval: 250
        onTriggered: root.armed = true
    }

    // Poll cursor while dragging for smoother Wayland motion
    Timer {
        id: mousePoller
        interval: 4
        running: root.pressed && root.armed && (root.mode === "selecting" || root.dragKind !== "")
        repeat: true
        onTriggered: cursorQueryProcess.running = true
    }

    Process {
        id: cursorQueryProcess
        running: false
        command: ["hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.pressed)
                    return;
                try {
                    const pos = JSON.parse(text);
                    const localX = pos.x - root.screen.x;
                    const localY = pos.y - root.screen.y;
                    root.applyPointer(localX, localY);
                } catch (e) {}
            }
        }
    }

    property real rsx: Math.min(sx, ex)
    property real rsy: Math.min(sy, ey)
    property real sw: Math.abs(sx - ex)
    property real sh: Math.abs(sy - ey)

    property list<var> clients: {
        const mon = Hypr.monitorFor(screen);
        if (!mon)
            return [];

        const special = mon.lastIpcObject.specialWorkspace;
        const wsId = special.name ? special.id : mon.activeWorkspace.id;

        return Hypr.toplevels.values.filter(c => {
            const data = c?.lastIpcObject;
            return c?.workspace?.id === wsId && data?.at?.length >= 2 && data?.size?.length >= 2;
        }).sort((a, b) => {
            const ac = a.lastIpcObject;
            const bc = b.lastIpcObject;
            return (bc.pinned - ac.pinned) || ((bc.fullscreen !== 0) - (ac.fullscreen !== 0)) || (bc.floating - ac.floating);
        });
    }

    function normalizeSelection(): void {
        const x1 = Math.min(sx, ex);
        const y1 = Math.min(sy, ey);
        const x2 = Math.max(sx, ex);
        const y2 = Math.max(sy, ey);
        sx = x1;
        sy = y1;
        ex = x2;
        ey = y2;
    }

    function clampSelection(): void {
        sx = Math.max(0, Math.min(sx, screen.width));
        sy = Math.max(0, Math.min(sy, screen.height));
        ex = Math.max(0, Math.min(ex, screen.width));
        ey = Math.max(0, Math.min(ey, screen.height));
        if (Math.abs(ex - sx) < minSize) {
            if (ex >= sx)
                ex = Math.min(screen.width, sx + minSize);
            else
                sx = Math.min(screen.width, ex + minSize);
        }
        if (Math.abs(ey - sy) < minSize) {
            if (ey >= sy)
                ey = Math.min(screen.height, sy + minSize);
            else
                sy = Math.min(screen.height, ey + minSize);
        }
    }

    function checkClientRects(x: real, y: real): void {
        if (mode !== "selecting" || pressed)
            return;

        onClient = false;
        for (const client of clients) {
            if (!client?.lastIpcObject?.at || !client.lastIpcObject.size)
                continue;

            let {
                at: [cx, cy],
                size: [cw, ch]
            } = client.lastIpcObject;
            cx -= screen.x;
            cy -= screen.y;
            if (cx <= x && cy <= y && cx + cw >= x && cy + ch >= y) {
                onClient = true;
                sx = cx;
                sy = cy;
                ex = cx + cw;
                ey = cy + ch;
                return;
            }
        }
    }

    function enterAdjusting(): void {
        normalizeSelection();
        clampSelection();
        onClient = false;
        mode = "adjusting";
        dragKind = "";
        didDrag = false;
        cursorShape = Qt.ArrowCursor;
    }

    function applyPointer(x: real, y: real): void {
        if (mode === "selecting" && pressed && didDrag) {
            onClient = false;
            sx = ssx;
            sy = ssy;
            ex = x;
            ey = y;
            return;
        }

        if (mode === "adjusting" && dragKind !== "") {
            const dx = x - dragOriginX;
            const dy = y - dragOriginY;
            let nx1 = dragStartRsx;
            let ny1 = dragStartRsy;
            let nx2 = dragStartRsx + dragStartSw;
            let ny2 = dragStartRsy + dragStartSh;

            if (dragKind === "move") {
                nx1 = dragStartRsx + dx;
                ny1 = dragStartRsy + dy;
                nx2 = nx1 + dragStartSw;
                ny2 = ny1 + dragStartSh;
                // keep fully on screen
                if (nx1 < 0) {
                    nx2 -= nx1;
                    nx1 = 0;
                }
                if (ny1 < 0) {
                    ny2 -= ny1;
                    ny1 = 0;
                }
                if (nx2 > screen.width) {
                    nx1 -= (nx2 - screen.width);
                    nx2 = screen.width;
                }
                if (ny2 > screen.height) {
                    ny1 -= (ny2 - screen.height);
                    ny2 = screen.height;
                }
            } else {
                if (dragKind.includes("w"))
                    nx1 = dragStartRsx + dx;
                if (dragKind.includes("e"))
                    nx2 = dragStartRsx + dragStartSw + dx;
                if (dragKind.includes("n"))
                    ny1 = dragStartRsy + dy;
                if (dragKind.includes("s"))
                    ny2 = dragStartRsy + dragStartSh + dy;

                // enforce min size by pinning the opposite edge
                if (nx2 - nx1 < minSize) {
                    if (dragKind.includes("w"))
                        nx1 = nx2 - minSize;
                    else
                        nx2 = nx1 + minSize;
                }
                if (ny2 - ny1 < minSize) {
                    if (dragKind.includes("n"))
                        ny1 = ny2 - minSize;
                    else
                        ny2 = ny1 + minSize;
                }

                nx1 = Math.max(0, Math.min(nx1, screen.width - minSize));
                ny1 = Math.max(0, Math.min(ny1, screen.height - minSize));
                nx2 = Math.max(minSize, Math.min(nx2, screen.width));
                ny2 = Math.max(minSize, Math.min(ny2, screen.height));
            }

            sx = nx1;
            sy = ny1;
            ex = nx2;
            ey = ny2;
        }
    }

    function beginDrag(kind: string, x: real, y: real): void {
        dragKind = kind;
        dragOriginX = x;
        dragOriginY = y;
        dragStartRsx = rsx;
        dragStartRsy = rsy;
        dragStartSw = sw;
        dragStartSh = sh;
        pressTime = Date.now();
    }

    function endDrag(): void {
        dragKind = "";
        normalizeSelection();
        clampSelection();
    }

    function confirmCapture(): void {
        if (capturing || closeAnim.running || mode !== "adjusting")
            return;
        if (sw < minSize || sh < minSize)
            return;

        capturing = true;
        normalizeSelection();
        clampSelection();

        // Prefer grim for live capture (faster than QML grab + less UI flash).
        // Freeze mode still uses the frozen ScreencopyView buffer.
        if (root.loader.freeze) {
            overlay.visible = border.visible = handles.visible = toolbar.visible = sizeLabel.visible = false;
            saveFromScreencopy();
        } else {
            saveWithGrim();
        }
    }

    function cancel(): void {
        if (closeAnim.running)
            return;
        closeAnim.start();
    }

    function openResult(path: string): void {
        if (root.loader.clipboardOnly) {
            Quickshell.execDetached(["sh", "-c", "wl-copy --type image/png < " + path]);
            Quickshell.execDetached(["notify-send", "-a", "caelestia-cli", "-i", path, "Screenshot taken", "Screenshot copied to clipboard"]);
        } else {
            Quickshell.execDetached([`${Quickshell.env("HOME")}/.local/bin/villode-screenshot-editor`, path]);
        }
        closeAnim.start();
    }

    function saveWithGrim(): void {
        // Hide picker chrome first so grim does not capture handles/toolbar.
        overlay.visible = border.visible = handles.visible = toolbar.visible = sizeLabel.visible = false;
        root.opacity = 0;
        root.loader.closing = true;

        const gx = Math.round(root.screen.x + rsx);
        const gy = Math.round(root.screen.y + rsy);
        const gw = Math.max(1, Math.round(sw));
        const gh = Math.max(1, Math.round(sh));
        const path = `/tmp/caelestia-picker-${Quickshell.processId}-${Date.now()}.png`;
        grimProc.outPath = path;
        grimProc.command = ["grim", "-g", `${gx},${gy} ${gw}x${gh}`, path];
        // Small delay for compositor to drop the overlay from the frame.
        grimDelay.restart();
    }

    function saveFromScreencopy(): void {
        const tmpfile = Qt.resolvedUrl(`/tmp/caelestia-picker-${Quickshell.processId}-${Date.now()}.png`);
        CUtils.saveItem(screencopy, tmpfile, Qt.rect(Math.ceil(rsx), Math.ceil(rsy), Math.floor(sw), Math.floor(sh)), path => {
            openResult(path);
        });
    }

    onClientsChanged: {
        if (mode === "selecting")
            checkClientRects(mouseX, mouseY);
    }

    anchors.fill: parent
    opacity: 0
    hoverEnabled: true
    preventStealing: true
    cursorShape: Qt.CrossCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    Component.onCompleted: {
        Hypr.extras.refreshOptions();

        if (loader.freeze)
            clients = clients;

        opacity = 1;
        armTimer.start();

        // Start with no fixed selection box — wait for hover / drag
        sx = 0;
        sy = 0;
        ex = 0;
        ey = 0;
        onClient = false;
    }

    onPressed: event => {
        if (!armed || capturing || closeAnim.running)
            return;

        if (event.button === Qt.RightButton) {
            cancel();
            return;
        }

        const x = event.x;
        const y = event.y;

        if (mode === "selecting") {
            ssx = x;
            ssy = y;
            pressTime = Date.now();
            didDrag = false;
            // If already hovering a client, keep that rect until drag starts
            if (!onClient) {
                sx = x;
                sy = y;
                ex = x;
                ey = y;
            }
            return;
        }

        // adjusting: root only handles click-outside (children handle handles/move)
        if (x < rsx || x > rsx + sw || y < rsy || y > rsy + sh) {
            // click outside → cancel (QQ/WeChat style)
            cancel();
        }
    }

    onReleased: event => {
        if (!armed || pressTime === 0 || capturing)
            return;
        if (closeAnim.running)
            return;

        if (mode === "selecting") {
            if (didDrag) {
                if (sw >= minSize && sh >= minSize)
                    enterAdjusting();
                else {
                    // tiny drag — treat as cancel of drag, restore hover
                    didDrag = false;
                    checkClientRects(event.x, event.y);
                }
            } else if (onClient && sw >= minSize && sh >= minSize) {
                // click on window without drag → select that window and adjust
                enterAdjusting();
            }
            pressTime = 0;
            return;
        }

        if (dragKind !== "")
            endDrag();
        pressTime = 0;
    }

    onPositionChanged: event => {
        const x = event.x;
        const y = event.y;

        if (mode === "selecting") {
            if (pressed && armed) {
                const dx = Math.abs(x - ssx);
                const dy = Math.abs(y - ssy);
                if (!didDrag && (dx > 3 || dy > 3)) {
                    didDrag = true;
                    onClient = false;
                    sx = ssx;
                    sy = ssy;
                }
                if (didDrag) {
                    sx = ssx;
                    sy = ssy;
                    ex = x;
                    ey = y;
                }
            } else {
                checkClientRects(x, y);
            }
            return;
        }

        if (pressed && dragKind !== "")
            applyPointer(x, y);
    }

    onDoubleClicked: event => {
        if (mode !== "adjusting" || capturing)
            return;
        if (event.x >= rsx && event.x <= rsx + sw && event.y >= rsy && event.y <= rsy + sh)
            confirmCapture();
    }

    focus: true
    Keys.onEscapePressed: cancel()
    Keys.onReturnPressed: confirmCapture()
    Keys.onEnterPressed: confirmCapture()

    SequentialAnimation {
        id: closeAnim

        PropertyAction {
            target: root.loader
            property: "closing"
            value: true
        }
        ParallelAnimation {
            Anim {
                target: root
                property: "opacity"
                to: 0
                type: Anim.StandardLarge
            }
            Anim {
                target: root
                properties: "rsx,rsy"
                to: 0
            }
            Anim {
                target: root
                property: "sw"
                to: root.screen.width
            }
            Anim {
                target: root
                property: "sh"
                to: root.screen.height
            }
        }
        PropertyAction {
            target: root.loader
            property: "activeAsync"
            value: false
        }
    }

    Process {
        running: true
        command: ["hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const pos = JSON.parse(text);
                    root.checkClientRects(pos.x - root.screen.x, pos.y - root.screen.y);
                } catch (e) {}
            }
        }
    }

    Timer {
        id: grimDelay
        interval: 40
        repeat: false
        onTriggered: grimProc.running = true
    }

    Process {
        id: grimProc
        property string outPath: ""
        running: false
        onExited: code => {
            if (code === 0 && outPath.length)
                root.openResult(outPath);
            else {
                root.capturing = false;
                root.loader.closing = false;
                root.opacity = 1;
                overlay.visible = border.visible = handles.visible = toolbar.visible = sizeLabel.visible = true;
            }
        }
    }

    Loader {
        id: screencopy

        asynchronous: true
        anchors.fill: parent
        active: root.loader.freeze

        sourceComponent: ScreencopyView {
            captureSource: root.screen

            onHasContentChanged: {
                // Freeze mode captures from the frozen buffer after confirm.
                if (hasContent && root.loader.freeze && root.capturing)
                    root.saveFromScreencopy();
            }
        }
    }

    StyledRect {
        id: overlay

        anchors.fill: parent
        color: Colours.palette.m3secondaryContainer
        opacity: 0.35
        visible: root.sw > 0 && root.sh > 0

        layer.enabled: true
        layer.effect: Mask {
            maskSource: selectionWrapper
            maskInverted: true
        }
    }

    Item {
        id: selectionWrapper

        anchors.fill: parent
        layer.enabled: true
        visible: false

        Rectangle {
            id: selectionRect

            radius: root.realRounding
            x: root.rsx
            y: root.rsy
            implicitWidth: Math.max(0, root.sw)
            implicitHeight: Math.max(0, root.sh)
        }
    }

    Rectangle {
        id: border

        color: "transparent"
        radius: root.realRounding > 0 ? root.realRounding + root.realBorderWidth : 0
        border.width: root.realBorderWidth
        border.color: Colours.palette.m3primary
        visible: root.sw > 0 && root.sh > 0

        x: selectionRect.x - root.realBorderWidth
        y: selectionRect.y - root.realBorderWidth
        implicitWidth: selectionRect.implicitWidth + root.realBorderWidth * 2
        implicitHeight: selectionRect.implicitHeight + root.realBorderWidth * 2

        Behavior on border.color {
            CAnim {}
        }
    }

    // Move surface (inside selection) — only in adjusting mode
    MouseArea {
        id: moveArea

        x: root.rsx
        y: root.rsy
        width: Math.max(0, root.sw)
        height: Math.max(0, root.sh)
        visible: root.mode === "adjusting" && !root.capturing
        hoverEnabled: true
        cursorShape: Qt.SizeAllCursor
        acceptedButtons: Qt.LeftButton
        z: 10

        onPressed: event => {
            root.beginDrag("move", root.rsx + event.x, root.rsy + event.y);
            event.accepted = true;
        }
        onPositionChanged: event => {
            if (pressed)
                root.applyPointer(root.rsx + event.x, root.rsy + event.y);
        }
        onReleased: root.endDrag()
        onDoubleClicked: root.confirmCapture()
    }

    // Resize handles
    Item {
        id: handles

        anchors.fill: parent
        visible: root.mode === "adjusting" && !root.capturing
        z: 20

        component Handle: Rectangle {
            required property string kind
            required property int cursor

            width: root.handleSize
            height: root.handleSize
            radius: width / 2
            color: Colours.palette.m3primary
            border.width: 1
            border.color: Colours.palette.m3onPrimary
            z: 21

            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: parent.cursor
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton

                onPressed: event => {
                    const p = mapToItem(root, event.x, event.y);
                    root.beginDrag(parent.kind, p.x, p.y);
                    event.accepted = true;
                }
                onPositionChanged: event => {
                    if (pressed) {
                        const p = mapToItem(root, event.x, event.y);
                        root.applyPointer(p.x, p.y);
                    }
                }
                onReleased: root.endDrag()
            }
        }

        Handle {
            kind: "nw"
            cursor: Qt.SizeFDiagCursor
            x: root.rsx - width / 2
            y: root.rsy - height / 2
        }
        Handle {
            kind: "n"
            cursor: Qt.SizeVerCursor
            x: root.rsx + root.sw / 2 - width / 2
            y: root.rsy - height / 2
        }
        Handle {
            kind: "ne"
            cursor: Qt.SizeBDiagCursor
            x: root.rsx + root.sw - width / 2
            y: root.rsy - height / 2
        }
        Handle {
            kind: "e"
            cursor: Qt.SizeHorCursor
            x: root.rsx + root.sw - width / 2
            y: root.rsy + root.sh / 2 - height / 2
        }
        Handle {
            kind: "se"
            cursor: Qt.SizeFDiagCursor
            x: root.rsx + root.sw - width / 2
            y: root.rsy + root.sh - height / 2
        }
        Handle {
            kind: "s"
            cursor: Qt.SizeVerCursor
            x: root.rsx + root.sw / 2 - width / 2
            y: root.rsy + root.sh - height / 2
        }
        Handle {
            kind: "sw"
            cursor: Qt.SizeBDiagCursor
            x: root.rsx - width / 2
            y: root.rsy + root.sh - height / 2
        }
        Handle {
            kind: "w"
            cursor: Qt.SizeHorCursor
            x: root.rsx - width / 2
            y: root.rsy + root.sh / 2 - height / 2
        }
    }

    // Size label above selection
    Rectangle {
        id: sizeLabel

        visible: root.sw > 0 && root.sh > 0 && !root.capturing
        z: 30
        radius: 4
        color: Qt.rgba(0, 0, 0, 0.65)
        implicitWidth: sizeText.implicitWidth + 12
        implicitHeight: sizeText.implicitHeight + 6
        x: Math.min(Math.max(0, root.rsx), Math.max(0, root.screen.width - implicitWidth))
        y: {
            const above = root.rsy - implicitHeight - 6;
            return above >= 0 ? above : Math.min(root.rsy + 6, root.screen.height - implicitHeight);
        }

        StyledText {
            id: sizeText
            anchors.centerIn: parent
            text: `${Math.round(root.sw)} × ${Math.round(root.sh)}`
            color: "white"
            font: Tokens.font.label.small
        }
    }

    // Bottom toolbar: Cancel / Done
    Rectangle {
        id: toolbar

        visible: root.mode === "adjusting" && !root.capturing
        z: 30
        radius: 8
        color: Qt.rgba(Colours.palette.m3surfaceContainer.r, Colours.palette.m3surfaceContainer.g, Colours.palette.m3surfaceContainer.b, 0.95)
        border.width: 1
        border.color: Colours.palette.m3outlineVariant
        implicitWidth: toolbarRow.implicitWidth + 16
        implicitHeight: toolbarRow.implicitHeight + 12

        x: {
            const ideal = root.rsx + root.sw / 2 - implicitWidth / 2;
            return Math.min(Math.max(8, ideal), root.screen.width - implicitWidth - 8);
        }
        y: {
            const below = root.rsy + root.sh + 10;
            if (below + implicitHeight + 8 <= root.screen.height)
                return below;
            const above = root.rsy - implicitHeight - 10;
            if (above >= 8)
                return above;
            return Math.max(8, root.screen.height - implicitHeight - 8);
        }

        Row {
            id: toolbarRow
            anchors.centerIn: parent
            spacing: 8

            Rectangle {
                radius: 6
                color: "transparent"
                implicitWidth: cancelLabel.implicitWidth + 20
                implicitHeight: cancelLabel.implicitHeight + 12

                StyledText {
                    id: cancelLabel
                    anchors.centerIn: parent
                    text: qsTr("取消")
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.label.medium
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: root.cancel()
                    onEntered: parent.color = Qt.rgba(Colours.palette.m3onSurface.r, Colours.palette.m3onSurface.g, Colours.palette.m3onSurface.b, 0.08)
                    onExited: parent.color = "transparent"
                }
            }

            Rectangle {
                radius: 6
                color: Colours.palette.m3primary
                implicitWidth: doneLabel.implicitWidth + 20
                implicitHeight: doneLabel.implicitHeight + 12

                StyledText {
                    id: doneLabel
                    anchors.centerIn: parent
                    text: qsTr("完成")
                    color: Colours.palette.m3onPrimary
                    font: Tokens.font.label.medium
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: root.confirmCapture()
                    onEntered: parent.opacity = 0.9
                    onExited: parent.opacity = 1
                }
            }
        }
    }

    Behavior on opacity {
        Anim {
            type: Anim.StandardLarge
        }
    }

    Behavior on rsx {
        enabled: !root.pressed && root.mode === "selecting" && !root.didDrag
        Anim {}
    }

    Behavior on rsy {
        enabled: !root.pressed && root.mode === "selecting" && !root.didDrag
        Anim {}
    }

    Behavior on sw {
        enabled: !root.pressed && root.mode === "selecting" && !root.didDrag
        Anim {}
    }

    Behavior on sh {
        enabled: !root.pressed && root.mode === "selecting" && !root.didDrag
        Anim {}
    }
}
