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
        Quickshell.execDetached(["sh", "-c", "sleep 0.3; output=$(caelestia screenshot \"$@\" 2>&1); code=$?; if [ $code -ne 0 ]; then [ -n \"$output\" ] || output='请检查截图依赖是否完整。'; caelestia shell toaster error '截图失败' \"$output\" screenshot >/dev/null 2>&1 || notify-send -u critical -- '截图失败' \"$output\"; fi; exit $code", "sh", ...args]);
        root.visibilities.utilities = false;
    }
    Layout.fillWidth: true
    implicitHeight: nonAnimHeight

    radius: Tokens.rounding.large
    // Glass card — layer blur on caelestia-drawers frosts the translucent fill.
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
                text: qsTr("Screenshot")
                font: Tokens.font.body.medium
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Capture the whole screen or a selected region")
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
                    text: qsTr("Full-screen screenshot")
                    activeText: qsTr("Full screen")
                    onClicked: root.takeScreenshot([])
                },
                MenuItem {
                    icon: "screenshot_region"
                    text: qsTr("Region screenshot")
                    activeText: qsTr("Region")
                    onClicked: root.takeScreenshot(["-r"])
                },
                MenuItem {
                    icon: "select"
                    text: qsTr("Freeze the screen and select a region")
                    activeText: qsTr("Frozen selection")
                    onClicked: root.takeScreenshot(["-r", "-f"])
                }
            ]
        }
    }
}
