pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Modal name entry for rename / new folder
Item {
    id: root

    property bool expanded: false
    property string title: ""
    property string label: ""
    property string mode: "" // "rename" | "mkdir"
    property string sourcePath: ""
    property string initialName: ""

    signal accepted(string mode, string sourcePath, string name)
    signal cancelled

    anchors.fill: parent
    z: 15600
    visible: expanded
    enabled: expanded

    function openRename(path: string): void {
        if (!path || !path.length)
            return;
        mode = "rename";
        sourcePath = path;
        const base = path.split("/").pop() || path;
        initialName = base;
        title = qsTr("重命名");
        label = qsTr("新名称");
        field.text = base;
        expanded = true;
        Qt.callLater(() => {
            field.forceActiveFocus();
            // Select basename without extension when file has one
            const i = base.lastIndexOf(".");
            if (i > 0)
                field.select(0, i);
            else
                field.selectAll();
        });
    }

    function openMkdir(): void {
        mode = "mkdir";
        sourcePath = "";
        initialName = qsTr("新建文件夹");
        title = qsTr("新建文件夹");
        label = qsTr("文件夹名称");
        field.text = initialName;
        expanded = true;
        Qt.callLater(() => {
            field.forceActiveFocus();
            field.selectAll();
        });
    }

    function close(): void {
        expanded = false;
        mode = "";
        sourcePath = "";
        field.text = "";
    }

    function submit(): void {
        const name = (field.text || "").trim();
        if (!name.length) {
            field.forceActiveFocus();
            return;
        }
        // Disallow path separators
        if (name.indexOf("/") >= 0 || name.indexOf("\\") >= 0) {
            field.forceActiveFocus();
            return;
        }
        if (name === "." || name === "..") {
            field.forceActiveFocus();
            return;
        }
        const m = mode;
        const src = sourcePath;
        close();
        root.accepted(m, src, name);
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

            StyledText {
                text: root.title
                color: Colours.palette.m3onSurface
                font: Tokens.font.body.builders.large.weight(Font.Bold).build()
            }

            StyledText {
                text: root.label
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.builders.small.build()
            }

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: field.implicitHeight + Tokens.padding.small * 2
                radius: Tokens.rounding.medium
                color: Colours.tPalette.m3surfaceContainerHighest

                StyledTextField {
                    id: field
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.medium
                    anchors.rightMargin: Tokens.padding.medium
                    selectByMouse: true
                    Keys.onReturnPressed: root.submit()
                    Keys.onEnterPressed: root.submit()
                    Keys.onEscapePressed: {
                        root.close();
                        root.cancelled();
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small
                Item { Layout.fillWidth: true }

                StyledRect {
                    implicitWidth: cancelLbl.implicitWidth + Tokens.padding.large * 2
                    implicitHeight: cancelLbl.implicitHeight + Tokens.padding.small * 2
                    radius: Tokens.rounding.full
                    color: Colours.tPalette.m3surfaceContainerHighest
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
                        font: Tokens.font.body.builders.small.weight(Font.Bold).build()
                    }
                }

                StyledRect {
                    implicitWidth: okLbl.implicitWidth + Tokens.padding.large * 2
                    implicitHeight: okLbl.implicitHeight + Tokens.padding.small * 2
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3primary
                    StateLayer {
                        radius: parent.radius
                        color: Colours.palette.m3onPrimary
                        onClicked: root.submit()
                    }
                    StyledText {
                        id: okLbl
                        anchors.centerIn: parent
                        text: qsTr("确定")
                        color: Colours.palette.m3onPrimary
                        font: Tokens.font.body.builders.small.weight(Font.Bold).build()
                    }
                }
            }
        }
    }
}
