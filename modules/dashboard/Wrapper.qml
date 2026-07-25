pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.filedialog
import qs.services
import qs.utils

Item {
    id: root

    required property DrawerVisibilities visibilities
    // Top taskbar only: open position sits this far below the screen top.
    property real edgeClearance: 0
    readonly property DashboardState dashState: DashboardState {
        reloadableId: "dashboardState"
    }
    readonly property FileDialog facePicker: FileDialog {
        title: qsTr("Select a profile picture")
        filterLabel: qsTr("Image files")
        filters: Images.validImageExtensions
        onAccepted: path => {
            if (CUtils.copyFile(Qt.resolvedUrl(path), Qt.resolvedUrl(`${Paths.home}/.face`)))
                Quickshell.execDetached(["notify-send", "-a", "caelestia-shell", "-u", "low", "-h", `STRING:image-path:${path}`, "Profile picture changed", `Profile picture changed to ${Paths.shortenHome(path)}`]);
            else
                Quickshell.execDetached(["notify-send", "-a", "caelestia-shell", "-u", "critical", "Unable to change profile picture", `Failed to change profile picture to ${Paths.shortenHome(path)}`]);
        }
    }

    readonly property real nonAnimHeight: (content.item as Content)?.nonAnimHeight ?? 0
    readonly property bool shouldBeActive: visibilities.dashboard && !visibilities.multitasking && Config.dashboard.enabled
    property real offsetScale: shouldBeActive ? 0 : 1

    // Never draw the dashboard over the multitasking scrim. Closing it
    // immediately also prevents a translucent frame during the two animations.
    visible: !visibilities.multitasking && offsetScale < 1
    // Open: edgeClearance (0 for side bars). Closed: fully above the screen.
    anchors.topMargin: root.edgeClearance + (-implicitHeight - 5 - root.edgeClearance) * offsetScale
    implicitHeight: content.implicitHeight
    implicitWidth: content.implicitWidth || 854 // Hard coded fallback for first open
    opacity: 1 - offsetScale

    Behavior on offsetScale {
        Anim {}
    }

    // Local glass for all bar positions — ContentWindow dashBg + deform was
    // shifting content relative to the blob (empty left on side bars, empty
    // top / overflow on top bar). Keep glass and content as one box.
    StyledRect {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: Math.max(content.width, parent.implicitWidth)
        height: Math.max(content.height, 1)
        radius: Tokens.rounding.extraLarge
        color: Colours.tPalette.m3surface
        visible: root.visible
        z: 0
    }

    Loader {
        id: content

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        z: 1

        active: root.shouldBeActive || root.visible

        sourceComponent: Content {
            visibilities: root.visibilities
            dashState: root.dashState
            facePicker: root.facePicker
        }
    }
}
