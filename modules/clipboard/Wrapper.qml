pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property DrawerVisibilities visibilities
    // Panels API compatibility (session has sidebarVisible)
    property bool sidebarVisible: false

    readonly property bool shouldBeActive: !!(visibilities.clipboard && Config.utilities.clipboard.enabled)
    readonly property alias contentItem: content.item

    property real offsetScale: 1

    readonly property real contentW: content.item ? content.item.implicitWidth : 0
    readonly property real contentH: content.item ? content.item.implicitHeight : 0
    readonly property real nonAnimWidth: contentW
    readonly property real nonAnimHeight: contentH

    implicitWidth: Math.max(contentW, 1)
    implicitHeight: Math.max(contentH, 1)

    visible: shouldBeActive || offsetScale < 0.999
    opacity: 1 - offsetScale
    scale: 0.94 + 0.06 * (1 - offsetScale)
    transformOrigin: Item.Center

    Behavior on offsetScale {
        Anim {}
    }

    onShouldBeActiveChanged: {
        offsetScale = shouldBeActive ? 0 : 1;
        if (shouldBeActive)
            Clipboard.refresh();
    }

    Component.onCompleted: offsetScale = shouldBeActive ? 0 : 1

    Loader {
        id: content

        anchors.centerIn: parent
        active: root.shouldBeActive || root.offsetScale < 0.999

        sourceComponent: Content {
            visibilities: root.visibilities
        }
    }
}
