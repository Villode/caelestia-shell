pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import qs.components
import qs.components.images
import Caelestia.Config

Scope {
    id: root

    // Multi-window: keep weak refs; prune destroyed entries on each open
    property var windows: []

    Component {
        id: managerComp
        ManagerWindow {}
    }

    function prune(): void {
        const next = [];
        for (let i = 0; i < windows.length; i++) {
            const w = windows[i];
            if (w)
                next.push(w);
        }
        windows = next;
    }

    function attachWindow(w: var): void {
        if (!w)
            return;
        w.requestClose.connect(() => {
            // Remove this window from the list
            const next = [];
            for (let i = 0; i < windows.length; i++) {
                if (windows[i] !== w && windows[i])
                    next.push(windows[i]);
            }
            windows = next;
            try {
                w.destroy();
            } catch (e) {}
        });
        const next = windows.slice();
        next.push(w);
        windows = next;
    }

    function createWindow(): var {
        prune();
        const w = managerComp.createObject(root);
        if (!w)
            return null;
        attachWindow(w);
        return w;
    }

    function lastWindow(): var {
        prune();
        if (!windows.length)
            return null;
        return windows[windows.length - 1];
    }

    function raiseWindow(w: var): void {
        if (!w)
            return;
        w.visible = true;
        // Nudge focus: re-set visible / title pulse for Hyprland
        try {
            if (typeof w.requestActivate === "function")
                w.requestActivate();
        } catch (e) {}
    }

    // Prefer a new window when one is already open so Super+E / explorer can stack windows.
    // First launch still creates a single window.
    function openHome(): void {
        prune();
        if (windows.length > 0)
            openNew("");
        else {
            const w = createWindow();
            if (!w)
                return;
            w.openPath("");
            raiseWindow(w);
        }
    }

    function openPath(path: string): void {
        prune();
        if (windows.length > 0)
            openNew(path || "");
        else {
            const w = createWindow();
            if (!w)
                return;
            w.openPath(path || "");
            raiseWindow(w);
        }
    }

    // Always new FloatingWindow
    function openNew(path: string): void {
        const w = createWindow();
        if (!w)
            return;
        w.openPath(path || "");
        raiseWindow(w);
    }

    // Open parent of file and select it (FileManager1 ShowItems)
    function openReveal(filePath: string): void {
        prune();
        if (windows.length > 0) {
            const w = windows[windows.length - 1];
            if (w) {
                w.revealPath(filePath || "");
                raiseWindow(w);
                return;
            }
        }
        openRevealNew(filePath);
    }

    function openRevealNew(filePath: string): void {
        const w = createWindow();
        if (!w)
            return;
        w.revealPath(filePath || "");
        raiseWindow(w);
    }

    function closeAll(): void {
        prune();
        const copy = windows.slice();
        windows = [];
        for (let i = 0; i < copy.length; i++) {
            const w = copy[i];
            if (!w)
                continue;
            try {
                w.visible = false;
                w.destroy();
            } catch (e) {}
        }
    }

    function count(): int {
        prune();
        return windows.length;
    }


    // Screen-space drag ghost (click-through). Drop completes via hypr mouse bind + FmDrag IPC.
    Variants {
        model: Screens.screens

        PanelWindow {
            id: dragLayer
            required property var modelData
            screen: modelData
            visible: FmDrag.active && FmDrag.cursorReady
            color: "transparent"
            WlrLayershell.namespace: "caelestia-fm-drag"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            mask: Region {}
            anchors.top: true
            anchors.left: true
            anchors.right: true
            anchors.bottom: true

            Timer {
                interval: 16
                running: FmDrag.active
                repeat: true
                onTriggered: {
                    if (!cursorProc.running)
                        cursorProc.running = true;
                }
            }

            Process {
                id: cursorProc
                command: ["hyprctl", "cursorpos", "-j"]
                running: false
                stdout: StdioCollector {
                    onStreamFinished: {
                        if (!FmDrag.active)
                            return;
                        try {
                            const pos = JSON.parse(text);
                            if (pos && pos.x !== undefined)
                                FmDrag.updateGlobal(Number(pos.x), Number(pos.y));
                        } catch (e) {}
                    }
                }
            }

            Item {
                visible: FmDrag.cursorReady
                x: FmDrag.globalX - (dragLayer.screen ? dragLayer.screen.x : 0) - FmDrag.hotX
                y: FmDrag.globalY - (dragLayer.screen ? dragLayer.screen.y : 0) - FmDrag.hotY
                width: card.implicitWidth
                height: card.implicitHeight
                opacity: 0.94

                StyledRect {
                    id: card
                    anchors.left: parent.left
                    anchors.top: parent.top
                    implicitWidth: Math.min(240, row.implicitWidth + Tokens.padding.medium * 2)
                    implicitHeight: row.implicitHeight + Tokens.padding.small * 2
                    radius: Tokens.rounding.large
                    color: Colours.palette.m3surfaceContainerHigh
                    border.width: 1
                    border.color: Colours.palette.m3outlineVariant

                    RowLayout {
                        id: row
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Tokens.padding.small
                        spacing: Tokens.spacing.small

                        CachingIconImage {
                            implicitSize: 36
                            source: FmDrag.iconSource
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText {
                                Layout.fillWidth: true
                                text: FmDrag.primaryName
                                elide: Text.ElideMiddle
                                color: Colours.palette.m3onSurface
                                font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                            }
                            StyledText {
                                visible: FmDrag.count > 1
                                text: qsTr("%1 项").arg(FmDrag.count)
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.body.builders.small.scale(0.85).build()
                            }
                        }
                    }

                    Rectangle {
                        visible: FmDrag.count > 1
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: -6
                        width: badge.implicitWidth + 10
                        height: badge.implicitHeight + 4
                        radius: height / 2
                        color: Colours.palette.m3primary
                        StyledText {
                            id: badge
                            anchors.centerIn: parent
                            text: String(FmDrag.count)
                            color: Colours.palette.m3onPrimary
                            font: Tokens.font.body.builders.small.scale(0.85).weight(Font.Bold).build()
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "filemanager"

        function open(): void {
            root.openHome();
        }

        function openPath(path: string): void {
            root.openPath(path);
        }

        // New window (optional path)
        function openNew(path: string): void {
            root.openNew(path || "");
        }

        function openNewHome(): void {
            root.openNew("");
        }

        function openReveal(path: string): void {
            root.openReveal(path || "");
        }

        function openRevealNew(path: string): void {
            root.openRevealNew(path || "");
        }

        function closeAll(): void {
            root.closeAll();
        }

        function count(): string {
            return String(root.count());
        }
    }

    IpcHandler {
        target: "fmdrag"

        function complete(): void {
            if (FmDrag.active)
                FmDrag.completeDrop();
        }

        function cancel(): void {
            if (FmDrag.active)
                FmDrag.cancel();
        }
    }

}
