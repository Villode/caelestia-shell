pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// Windows-style 此电脑: drive rows with capacity bars (no duplicate folders)
Item {
    id: root

    required property var state
    required property var devices

    signal openDevice(var device)
    signal requestMount(var device)

    readonly property var allDevices: devices ? (devices.devices || []) : []
    readonly property var driveItems: {
        const src = allDevices;
        const out = [];
        for (let i = 0; i < src.length; i++) {
            const k = src[i].kind;
            // disks + USB + phone/MTP; network listed separately
            if (k !== "folder" && k !== "network")
                out.push(src[i]);
        }
        return out;
    }
    readonly property var networkItems: {
        const src = allDevices;
        const out = [];
        for (let i = 0; i < src.length; i++) {
            if (src[i].kind === "network")
                out.push(src[i]);
        }
        return out;
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        contentHeight: col.implicitHeight + Tokens.padding.large
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            width: flick.width
            spacing: Tokens.spacing.small

            StyledText {
                Layout.fillWidth: true
                Layout.bottomMargin: Tokens.spacing.small
                text: qsTr("设备和驱动器")
                color: Colours.palette.m3onSurface
                font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
            }

            Repeater {
                model: root.driveItems

                DriveRow {
                    required property var modelData
                    Layout.fillWidth: true
                    device: modelData
                    onActivated: {
                        if (modelData.mounted && modelData.path)
                            root.openDevice(modelData);
                        else
                            root.requestMount(modelData);
                    }
                }
            }

            StyledText {
                visible: root.driveItems.length === 0
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.medium
                text: qsTr("未检测到磁盘设备")
                color: Colours.palette.m3outline
                font: Tokens.font.body.small
            }

            StyledText {
                visible: root.networkItems.length > 0
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.large
                Layout.bottomMargin: Tokens.spacing.small
                text: qsTr("网络")
                color: Colours.palette.m3onSurface
                font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
            }

            Repeater {
                model: root.networkItems

                DriveRow {
                    required property var modelData
                    Layout.fillWidth: true
                    device: modelData
                    onActivated: root.openDevice(modelData)
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.large
                text: qsTr("未挂载磁盘点击后会尝试挂载；需要权限时弹出系统密码对话框。")
                color: Colours.palette.m3outline
                font: Tokens.font.body.builders.small.scale(0.9).build()
                wrapMode: Text.WordWrap
            }
        }
    }

    component DriveRow: StyledRect {
        id: row

        property var device: ({})
        signal activated

        readonly property real pct: Math.min(100, Math.max(0, Number(device.usedPct) || 0))
        readonly property bool showBar: !!(device.mounted && device.sizeBytes > 0)
        readonly property color barColor: pct >= 90 ? Colours.palette.m3error : (pct >= 75 ? Colours.palette.m3tertiary : Colours.palette.m3primary)

        implicitHeight: 64
        radius: Tokens.rounding.medium
        color: "transparent"

        StateLayer {
            color: Colours.palette.m3onSurface
            radius: row.radius
            onClicked: row.activated()
            onDoubleClicked: row.activated()
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.medium
            anchors.rightMargin: Tokens.padding.medium
            spacing: Tokens.spacing.medium

            // Drive icon tile
            StyledRect {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                radius: Tokens.rounding.small
                color: Colours.tPalette.m3surfaceContainerHigh

                MaterialIcon {
                    anchors.centerIn: parent
                    text: row.device.icon || "hard_drive"
                    color: row.device.mounted ? Colours.palette.m3primary : Colours.palette.m3outline
                    fontStyle: Tokens.font.icon.builders.large.build()
                    fill: 1
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            const n = row.device.name || "";
                            const L = row.device.letter || "";
                            return L ? (n + " (" + L + ")") : n;
                        }
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.body.builders.small.weight(Font.DemiBold).build()
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    StyledText {
                        visible: !row.device.mounted
                        text: qsTr("未挂载")
                        color: Colours.palette.m3tertiary
                        font: Tokens.font.body.builders.small.scale(0.9).weight(Font.Medium).build()
                    }
                }

                // Capacity bar (Windows style)
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 8
                    visible: row.showBar

                    Rectangle {
                        anchors.fill: parent
                        radius: 4
                        color: Colours.palette.m3surfaceContainerHighest
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * (row.pct / 100)
                        radius: 4
                        color: row.barColor
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: row.device.subtitle || ""
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.builders.small.scale(0.9).build()
                    elide: Text.ElideMiddle
                    maximumLineCount: 1
                }
            }
        }
    }
}
