pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// Confirm trash / permanent delete
Item {
    id: root

    property bool expanded: false
    property string title: ""
    property string message: ""
    property string confirmLabel: qsTr("确定")
    property bool danger: false
    property var pendingPaths: []
    property string mode: "" // "trash" | "delete" | "empty-trash"

    signal accepted(var paths, string mode)
    signal cancelled

    anchors.fill: parent
    z: 15500
    visible: expanded
    enabled: expanded

    function openTrash(paths: var): void {
        const list = paths || [];
        if (!list.length)
            return;
        mode = "trash";
        pendingPaths = list.slice();
        danger = false;
        title = qsTr("移到回收站");
        message = list.length === 1
            ? qsTr("确定将「%1」移到回收站？").arg(list[0].split("/").pop())
            : qsTr("确定将 %1 项移到回收站？").arg(list.length);
        confirmLabel = qsTr("移到回收站");
        expanded = true;
    }

    function openDelete(paths: var): void {
        const list = paths || [];
        if (!list.length)
            return;
        mode = "delete";
        pendingPaths = list.slice();
        danger = true;
        title = qsTr("永久删除");
        message = list.length === 1
            ? qsTr("确定永久删除「%1」？此操作无法撤销。").arg(list[0].split("/").pop())
            : qsTr("确定永久删除 %1 项？此操作无法撤销。").arg(list.length);
        confirmLabel = qsTr("永久删除");
        expanded = true;
    }

    function openEmptyTrash(): void {
        mode = "empty-trash";
        pendingPaths = [];
        danger = true;
        title = qsTr("清空回收站");
        message = qsTr("确定清空回收站？所有项目将被永久删除，此操作无法撤销。");
        confirmLabel = qsTr("清空回收站");
        expanded = true;
    }

    function close(): void {
        expanded = false;
        pendingPaths = [];
        mode = "";
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            root.close();
            root.cancelled();
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Colours.palette.m3scrim, 0.45)
        }
    }

    StyledRect {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 420)
        implicitHeight: body.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.extraLarge
        color: Colours.palette.m3surfaceContainerHigh
        border.width: 1
        border.color: Colours.palette.m3outlineVariant

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
                    text: root.danger ? "delete_forever" : "delete"
                    color: root.danger ? Colours.palette.m3error : Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.builders.large.build()
                    fill: 1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.body.builders.large.weight(Font.Bold).build()
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: root.message
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
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
                        onClicked: {
                            root.close();
                            root.cancelled();
                        }
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
                    color: root.danger ? Colours.palette.m3error : Colours.palette.m3primary

                    StateLayer {
                        radius: parent.radius
                        color: root.danger ? Colours.palette.m3onError : Colours.palette.m3onPrimary
                        onClicked: {
                            const p = root.pendingPaths.slice();
                            const m = root.mode;
                            root.close();
                            root.accepted(p, m);
                        }
                    }
                    StyledText {
                        id: okLbl
                        anchors.centerIn: parent
                        text: root.confirmLabel
                        color: root.danger ? Colours.palette.m3onError : Colours.palette.m3onPrimary
                        font: Tokens.font.body.builders.small.weight(Font.Bold).build()
                    }
                }
            }
        }
    }
}
