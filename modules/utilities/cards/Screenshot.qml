pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

StyledRect {
    id: root

    required property var props
    required property DrawerVisibilities visibilities
    readonly property real nonAnimHeight: layout.implicitHeight + layout.anchors.margins * 2

    function takeScreenshot(args: var): void {
        Quickshell.execDetached([
            "sh",
            "-c",
            "sleep 0.3; exec caelestia screenshot \"$@\"",
            "sh",
            ...args
        ]);
        root.visibilities.utilities = false;
    }

    Layout.fillWidth: true
    implicitHeight: nonAnimHeight

    radius: Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer

    RowLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        StyledRect {
            implicitWidth: implicitHeight
            implicitHeight: icon.implicitHeight + Tokens.padding.large

            radius: Tokens.rounding.full
            color: Colours.palette.m3tertiaryContainer

            MaterialIcon {
                id: icon

                anchors.centerIn: parent
                text: "screenshot"
                color: Colours.palette.m3onTertiaryContainer
                fontStyle: Tokens.font.icon.large
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: qsTr("屏幕截图")
                font: Tokens.font.body.medium
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("截取整个屏幕或选定区域")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }
        }

        SplitButton {
            active: menuItems.find(m => root.props.screenshotMode === m.icon + m.text) ?? menuItems[0]
            menu.onItemSelected: item => root.props.screenshotMode = item.icon + item.text

            menuItems: [
                MenuItem {
                    icon: "fullscreen"
                    text: qsTr("全屏截图")
                    activeText: qsTr("全屏")
                    onClicked: root.takeScreenshot([])
                },
                MenuItem {
                    icon: "screenshot_region"
                    text: qsTr("区域截图")
                    activeText: qsTr("区域")
                    onClicked: root.takeScreenshot(["-r"])
                },
                MenuItem {
                    icon: "select"
                    text: qsTr("冻结画面并选择区域")
                    activeText: qsTr("冻结选区")
                    onClicked: root.takeScreenshot(["-r", "-f"])
                }
            ]
        }
    }
}
