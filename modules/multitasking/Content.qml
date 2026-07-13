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

// Horizontal landscape cards, start from top-left. Scrim only (no panel shell).
Item {
    id: root

    required property DrawerVisibilities visibilities
    required property ShellScreen screen

    readonly property real screenAspect: Math.max(1.2, screen.width / Math.max(1, screen.height))
    readonly property real cardH: Math.min(screen.height * 0.34, 280)
    readonly property real cardW: cardH * screenAspect
    readonly property real edgePad: Tokens.padding.largeIncreased

    implicitWidth: Math.max(1, screen.width - 48)
    implicitHeight: cardH + 48

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
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: root.edgePad
        anchors.topMargin: root.edgePad
        visible: root.clients.length === 0
        spacing: Tokens.spacing.small

        MaterialIcon {
            Layout.alignment: Qt.AlignLeft
            text: "web_asset_off"
            color: Colours.palette.m3outline
            fontStyle: Tokens.font.icon.builders.extraLarge.scale(1.4).build()
        }

        StyledText {
            text: qsTr("没有正在运行的应用")
            color: Colours.palette.m3outline
            font: Tokens.font.body.medium
        }
    }

    Flickable {
        id: strip

        anchors.fill: parent
        visible: root.clients.length > 0
        contentWidth: row.implicitWidth + root.edgePad * 2
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: false
        // Start from left — do not center the first card
        contentX: 0

        Row {
            id: row

            x: root.edgePad
            y: root.edgePad
            height: root.cardH + 36
            spacing: Tokens.spacing.large

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
        readonly property string appTitle: client?.title ?? client?.lastIpcObject?.title ?? qsTr("应用")

        StyledRect {
            id: frame

            anchors.left: parent.left
            anchors.top: parent.top
            width: card.cardWidth
            height: card.cardHeight
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.3)
            clip: true

            ScreencopyView {
                id: thumb

                anchors.fill: parent
                anchors.margins: 1
                captureSource: card.client?.wayland ?? null // qmllint disable unresolved-type
                live: true
                constraintSize.width: width
                constraintSize.height: height
            }

            Rectangle {
                anchors.fill: parent
                visible: !thumb.captureSource
                color: Colours.palette.m3surfaceContainerHigh
                radius: parent.radius

                Image {
                    anchors.centerIn: parent
                    width: 48
                    height: 48
                    source: Icons.getAppIcon(card.appClass, "image-missing")
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
            }

            // Focus (below close)
            MouseArea {
                anchors.fill: parent
                z: 1
                acceptedButtons: Qt.LeftButton
                onClicked: root.focusClient(card.client)
            }

            // Larger, clearer close control (top-right of each card)
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
                    anchors.margins: -4 // larger hit area
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        mouse.accepted = true;
                        root.closeClient(card.client);
                    }
                }
            }
        }

        RowLayout {
            anchors.left: frame.left
            anchors.top: frame.bottom
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
                color: Colours.palette.m3onSurface
                font: Tokens.font.label.small
                elide: Text.ElideRight
            }
        }
    }
}
