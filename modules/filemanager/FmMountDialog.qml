pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// In-window sheet: confirm elevated mount (pkexec will show system password dialog)
Item {
    id: root

    property bool expanded: false
    property string device: ""
    property string deviceName: ""
    property string detail: ""
    property bool busy: false

    signal confirmed(string device, string name)
    signal cancelled

    anchors.fill: parent
    z: 12000
    visible: expanded
    enabled: expanded

    function openFor(dev: string, name: string, detailText: string): void {
        device = dev || "";
        deviceName = name || dev || "";
        detail = detailText || "";
        busy = false;
        expanded = true;
    }

    function close(): void {
        expanded = false;
        busy = false;
    }

    // Dim backdrop
    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (!root.busy)
                root.cancelled();
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Colours.palette.m3scrim, 0.45)
        }
    }

    StyledRect {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 420)
        implicitHeight: body.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.extraLarge
        color: Colours.palette.m3surfaceContainerHigh
        border.width: 1
        border.color: Colours.palette.m3outlineVariant

        // block click-through
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        ColumnLayout {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.medium

            RowLayout {
                spacing: Tokens.spacing.medium
                MaterialIcon {
                    text: "lock"
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.builders.large.build()
                    fill: 1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("需要挂载磁盘")
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.body.builders.large.weight(Font.Bold).build()
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("「%1」尚未挂载，需要管理员权限才能访问。").arg(root.deviceName)
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
                wrapMode: Text.WordWrap
            }

            StyledText {
                visible: root.device.length > 0
                Layout.fillWidth: true
                text: qsTr("设备：%1").arg(root.device)
                color: Colours.palette.m3outline
                font: Tokens.font.body.builders.small.scale(0.9).build()
                wrapMode: Text.WrapAnywhere
            }

            StyledText {
                visible: root.detail.length > 0
                Layout.fillWidth: true
                text: root.detail
                color: Colours.palette.m3error
                font: Tokens.font.body.builders.small.scale(0.9).build()
                wrapMode: Text.WordWrap
                maximumLineCount: 4
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("点击「挂载」后将弹出系统密码窗口（polkit）。输入本机用户密码即可。")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.builders.small.scale(0.9).build()
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.small
                spacing: Tokens.spacing.medium

                Item { Layout.fillWidth: true }

                StyledRect {
                    implicitWidth: cancelLbl.implicitWidth + Tokens.padding.large * 2
                    implicitHeight: cancelLbl.implicitHeight + Tokens.padding.medium
                    radius: Tokens.rounding.full
                    color: "transparent"
                    border.width: 1
                    border.color: Colours.palette.m3outlineVariant

                    StateLayer {
                        radius: parent.radius
                        disabled: root.busy
                        onClicked: root.cancelled()
                    }
                    StyledText {
                        id: cancelLbl
                        anchors.centerIn: parent
                        text: qsTr("取消")
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.body.small
                    }
                }

                StyledRect {
                    implicitWidth: okLbl.implicitWidth + Tokens.padding.large * 2
                    implicitHeight: okLbl.implicitHeight + Tokens.padding.medium
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3primary

                    StateLayer {
                        radius: parent.radius
                        color: Colours.palette.m3onPrimary
                        disabled: root.busy
                        onClicked: {
                            root.busy = true;
                            root.confirmed(root.device, root.deviceName);
                        }
                    }
                    StyledText {
                        id: okLbl
                        anchors.centerIn: parent
                        text: root.busy ? qsTr("挂载中…") : qsTr("挂载")
                        color: Colours.palette.m3onPrimary
                        font: Tokens.font.body.builders.small.weight(Font.Bold).build()
                    }
                }
            }
        }
    }
}
