pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

// Multi-row window cards (wrap when one row is full). Scrim only (no panel shell).
Item {
    id: root

    required property DrawerVisibilities visibilities
    required property ShellScreen screen

    readonly property real screenAspect: Math.max(1.2, screen.width / Math.max(1, screen.height))
    readonly property real edgePad: Tokens.padding.largeIncreased
    readonly property real cardGap: Tokens.spacing.large
    readonly property real labelExtra: 36
    // Available width for cards inside the strip
    readonly property real availableW: Math.max(160, screen.width - 48 - edgePad * 2)
    // Max vertical room: leave space for dock + a little breathing room
    readonly property real maxStripH: Math.max(200, screen.height * 0.62)

    readonly property int clientCount: clients.length

    // Preferred card height scales down as the grid fills more rows
    readonly property real baseCardH: Math.min(screen.height * 0.30, 260)
    readonly property real minCardH: Math.min(120, baseCardH * 0.55)

    // Estimate columns from available width using a mid aspect
    readonly property real midAspect: Math.max(1.0, Math.min(1.8, screenAspect))
    readonly property real estCardW: baseCardH * midAspect
    readonly property int colsAtBase: Math.max(1, Math.floor((availableW + cardGap) / (estCardW + cardGap)))
    readonly property int rowsAtBase: Math.max(1, Math.ceil(Math.max(1, clientCount) / colsAtBase))

    // Shrink card height if too many rows would overflow maxStripH
    readonly property real rowPitchAtBase: baseCardH + labelExtra + cardGap
    readonly property real fitScale: {
        if (clientCount <= 0)
            return 1;
        const need = rowsAtBase * (baseCardH + labelExtra) + Math.max(0, rowsAtBase - 1) * cardGap;
        if (need <= maxStripH)
            return 1;
        const scale = maxStripH / Math.max(1, need);
        return Math.max(minCardH / baseCardH, Math.min(1, scale));
    }

    readonly property real cardH: Math.max(minCardH, baseCardH * fitScale)

    // After cardH settled, recompute columns with actual typical width
    readonly property real typCardW: cardH * midAspect
    readonly property int flowColumns: Math.max(1, Math.floor((availableW + cardGap) / (typCardW + cardGap)))

    implicitWidth: Math.max(1, screen.width - 48)
    // Height follows Flow content (multi-row)
    implicitHeight: {
        if (clientCount === 0)
            return cardH + 48;
        // Prefer measured flow height when available
        const measured = flow.implicitHeight > 0 ? flow.implicitHeight + edgePad * 2 : 0;
        if (measured > 0)
            return Math.min(maxStripH + edgePad, measured);
        const rows = Math.max(1, Math.ceil(clientCount / flowColumns));
        return Math.min(maxStripH + edgePad, rows * (cardH + labelExtra) + Math.max(0, rows - 1) * cardGap + edgePad * 2);
    }

    function clientAddress(client: var): string {
        const a = client?.address ?? client?.lastIpcObject?.address ?? "";
        if (!a)
            return "";
        const s = String(a);
        return s.startsWith("0x") ? s : `0x${s}`;
    }

    function clientAspect(client: var): real {
        const size = client?.lastIpcObject?.size;
        if (size && size.length >= 2 && size[1] > 0)
            return Math.max(0.75, Math.min(2.4, size[0] / size[1]));
        return root.screenAspect;
    }

    function focusClient(client: var): void {
        const addr = root.clientAddress(client);
        if (!addr)
            return;
        root.visibilities.multitasking = false;
        Hypr.dispatch(Hypr.usingLua ? `hl.dsp.window.focus({ window = "address:${addr}" })` : `focuswindow address:${addr}`);
    }

    function closeClient(client: var): void {
        const addr = root.clientAddress(client);
        if (!addr)
            return;
        Hypr.dispatch(Hypr.usingLua ? `hl.dsp.window.kill({ window = "address:${addr}" })` : `closewindow address:${addr}`);
        refreshTimer.restart();
    }

    function listClients(): list<var> {
        const all = Hypr.toplevels?.values ?? [];
        const out = [];
        for (const t of all) {
            const ipc = t.lastIpcObject || {};
            if (ipc.mapped === false)
                continue;
            if (ipc.hidden)
                continue;
            const wsName = t.workspace?.name ?? ipc.workspace?.name ?? "";
            if (String(wsName).startsWith("special:"))
                continue;
            out.push(t);
        }
        out.sort((a, b) => {
            const fa = a.lastIpcObject?.focusHistoryID ?? 999;
            const fb = b.lastIpcObject?.focusHistoryID ?? 999;
            return fa - fb;
        });
        return out;
    }

    property list<var> clients: []

    function refresh(): void {
        Hyprland.refreshToplevels();
        clients = listClients();
    }

    Component.onCompleted: refresh()

    Timer {
        id: refreshTimer
        interval: 120
        onTriggered: root.refresh()
    }

    Connections {
        target: root.visibilities
        function onMultitaskingChanged(): void {
            if (root.visibilities.multitasking)
                root.refresh();
        }
    }

    Timer {
        interval: 400
        running: root.visibilities.multitasking
        repeat: true
        onTriggered: root.clients = root.listClients()
    }

    Keys.onEscapePressed: root.visibilities.multitasking = false
    focus: visibilities.multitasking

    ColumnLayout {
        anchors.centerIn: parent
        visible: root.clients.length === 0
        spacing: Tokens.spacing.small

        MaterialIcon {
            Layout.alignment: Qt.AlignHCenter
            text: "web_asset_off"
            color: Colours.palette.m3outline
            fontStyle: Tokens.font.icon.builders.extraLarge.scale(1.4).build()
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("No running applications")
            color: Colours.palette.m3outline
            font: Tokens.font.body.medium
        }
    }

    Flickable {
        id: strip

        anchors.fill: parent
        visible: root.clients.length > 0
        contentWidth: width
        contentHeight: Math.max(height, flow.y + flow.implicitHeight + root.edgePad)
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        contentX: 0
        contentY: 0

        Flow {
            id: flow

            x: root.edgePad
            y: root.edgePad
            width: Math.max(1, strip.width - root.edgePad * 2)
            spacing: root.cardGap
            // Flow lays left-to-right, wraps to next line
            flow: Flow.LeftToRight

            Repeater {
                model: root.clients

                AppCard {
                    required property var modelData
                    required property int index

                    client: modelData
                    cardHeight: root.cardH
                    cardWidth: root.cardH * root.clientAspect(modelData)
                    screen: root.screen
                }
            }
        }

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: strip
        }
    }

    component AppCard: Item {
        id: card

        required property var client
        required property real cardWidth
        required property real cardHeight
        required property ShellScreen screen

        width: cardWidth
        height: cardHeight + 36

        readonly property string appClass: client?.lastIpcObject?.class ?? ""
        readonly property string appTitle: client?.title ?? client?.lastIpcObject?.title ?? qsTr("Application")
        readonly property bool isFocused: {
            const ipc = client?.lastIpcObject ?? {};
            if (ipc.focused === true || ipc.active === true)
                return true;
            // Match Hyprland focused toplevel by address
            const active = Hypr.activeToplevel ?? null;
            const a = root.clientAddress(client);
            const b = root.clientAddress(active);
            if (a && b && a === b)
                return true;
            // focusHistoryID 0 is usually the focused window
            if ((ipc.focusHistoryID ?? -1) === 0)
                return true;
            return false;
        }
        property bool hovered: false
        readonly property real cardRadius: Tokens.rounding.large
        readonly property real ringW: card.hovered || card.isFocused ? 3 : 1
        readonly property color ringColor: card.isFocused
            ? Colours.palette.m3primary
            : card.hovered
              ? Colours.palette.m3secondary
              : Qt.alpha(Colours.palette.m3outlineVariant, 0.3)

        // Outer ring (no clip) — avoids square corners from thick border + clip
        Rectangle {
            id: ring

            anchors.left: parent.left
            anchors.top: parent.top
            width: card.cardWidth
            height: card.cardHeight
            radius: card.cardRadius
            color: "transparent"
            border.width: card.ringW
            border.color: card.ringColor
            z: 4

            Behavior on border.width {
                NumberAnimation {
                    duration: 120
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on border.color {
                ColorAnimation {
                    duration: 120
                }
            }
        }

        // Inner card: clip content to rounded rect; leave room for ring stroke
        Item {
            id: frame

            anchors.left: ring.left
            anchors.top: ring.top
            anchors.margins: card.ringW
            width: ring.width - card.ringW * 2
            height: ring.height - card.ringW * 2
            clip: true

            // Rounded mask for children (clip alone can leave square pixels on GPU layers)
            layer.enabled: true
            layer.smooth: true
            layer.samples: 4

            Rectangle {
                id: frameBg

                anchors.fill: parent
                radius: Math.max(0, card.cardRadius - card.ringW)
                color: Colours.tPalette.m3surfaceContainer
            }

            ScreencopyView {
                id: thumb

                anchors.fill: parent
                captureSource: card.client?.wayland ?? null // qmllint disable unresolved-type
                live: true
                constraintSize.width: frame.width
                constraintSize.height: frame.height
            }

            Rectangle {
                anchors.fill: parent
                visible: !thumb.captureSource
                color: Colours.palette.m3surfaceContainerHigh
                radius: Math.max(0, card.cardRadius - card.ringW)

                Image {
                    anchors.centerIn: parent
                    width: 48
                    height: 48
                    source: Icons.getAppIcon(card.appClass, "image-missing")
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
            }

            // Soft wash — same radius as frame, sits under close btn
            Rectangle {
                anchors.fill: parent
                radius: Math.max(0, card.cardRadius - card.ringW)
                color: card.isFocused
                    ? Qt.alpha(Colours.palette.m3primary, 0.18)
                    : card.hovered
                      ? Qt.alpha(Colours.palette.m3secondary, 0.12)
                      : "transparent"
                z: 2
            }

            MouseArea {
                anchors.fill: parent
                z: 3
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onEntered: card.hovered = true
                onExited: card.hovered = false
                onClicked: root.focusClient(card.client)
            }

            StyledRect {
                id: closeBtn

                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Tokens.padding.small
                implicitWidth: 40
                implicitHeight: 40
                radius: Tokens.rounding.full
                color: Colours.palette.m3error
                z: 5

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "close"
                    fill: 1
                    color: Colours.palette.m3onError
                    fontStyle: Tokens.font.icon.builders.medium.scale(1.15).build()
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        mouse.accepted = true;
                        root.closeClient(card.client);
                    }
                }
            }
        }

        RowLayout {
            anchors.left: ring.left
            anchors.top: ring.bottom
            anchors.topMargin: Tokens.spacing.extraSmall
            width: card.cardWidth
            spacing: Tokens.spacing.extraSmall

            Image {
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                source: Icons.getAppIcon(card.appClass, "image-missing")
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }

            StyledText {
                Layout.fillWidth: true
                text: card.appTitle
                color: card.isFocused
                    ? Colours.palette.m3primary
                    : card.hovered
                      ? Colours.palette.m3secondary
                      : Colours.palette.m3onSurface
                font: Tokens.font.label.small
                elide: Text.ElideRight
            }
        }
    }
}
