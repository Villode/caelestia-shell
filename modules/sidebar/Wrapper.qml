pragma ComponentBehavior: Bound

import QtQuick
import Caelestia
import Caelestia.Config
import qs.components

Item {
    id: root

    required property DrawerVisibilities visibilities
    readonly property Props props: Props {}
    // When true, host positions this panel on the left and slides from left.
    property bool edgeLeft: false

    readonly property bool shouldBeActive: visibilities.sidebar && Config.sidebar.enabled
    property real offsetScale: shouldBeActive ? 0 : 1

    visible: offsetScale < 1
    implicitWidth: Tokens.sizes.sidebar.width
    opacity: 1 - offsetScale

    Behavior on offsetScale {
        Anim {}
    }

    Loader {
        id: content

        // Original right chrome pads the INNER edge (left of a right-side panel) heavily.
        // Left chrome mirrors that: heavy pad on the right (inner), thin on the left (screen).
        readonly property real innerPad: Tokens.padding.large
        readonly property real outerPad: CUtils.clamp(innerPad - Config.border.thickness, 0, innerPad)

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.edgeLeft ? outerPad : innerPad
        anchors.rightMargin: root.edgeLeft ? innerPad : outerPad
        anchors.topMargin: outerPad
        anchors.bottomMargin: 0

        active: root.shouldBeActive || root.visible

        sourceComponent: Content {
            implicitWidth: Tokens.sizes.sidebar.width - content.anchors.leftMargin - content.anchors.rightMargin
            props: root.props
            visibilities: root.visibilities
        }
    }
}
