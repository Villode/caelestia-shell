pragma ComponentBehavior: Bound

import QtQuick
import Caelestia
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property DrawerVisibilities visibilities
    // When true, chrome sits on the left edge (taskbar on the right).
    property bool edgeLeft: false

    readonly property bool shouldBeActive: !!(visibilities.clipboard && Config.utilities.clipboard.enabled)
    property real offsetScale: shouldBeActive ? 0 : 1

    readonly property real totalPadding: Tokens.padding.large + CUtils.clamp(Tokens.padding.large - Config.border.thickness, 0, Tokens.padding.large)
    readonly property real nonAnimHeight: ((content.item as Content)?.nonAnimHeight ?? 0) + totalPadding

    visible: offsetScale < 1
    // Slide down from top (dashboard-style), not up from bottom.
    anchors.topMargin: (-implicitHeight - 5) * offsetScale
    implicitHeight: content.implicitHeight + totalPadding
    implicitWidth: Tokens.sizes.clipboard.width
    opacity: 1 - offsetScale

    Behavior on offsetScale {
        Anim {}
    }

    onShouldBeActiveChanged: {
        if (shouldBeActive) {
            Clipboard.clearFilter();
            Clipboard.refresh();
        }
    }

    Loader {
        id: content

        readonly property real innerPad: Tokens.padding.large
        readonly property real outerPad: CUtils.clamp(innerPad - Config.border.thickness, 0, innerPad)

        anchors.bottom: parent.bottom
        anchors.left: root.edgeLeft ? parent.left : undefined
        anchors.right: root.edgeLeft ? undefined : parent.right
        anchors.bottomMargin: innerPad
        anchors.leftMargin: root.edgeLeft ? outerPad : innerPad
        anchors.rightMargin: root.edgeLeft ? innerPad : outerPad

        asynchronous: true
        active: true

        sourceComponent: Content {
            implicitWidth: root.implicitWidth - root.totalPadding
            visibilities: root.visibilities
        }
    }
}
