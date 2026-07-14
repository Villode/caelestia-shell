import QtQuick
import qs.components

Item {
    id: root

    required property DrawerVisibilities visibilities
    required property Item sidebarPanel
    // When true, chrome sits on the left edge (taskbar on the right).
    property bool edgeLeft: false
    property alias osdPanel: content.osdPanel
    property alias sessionPanel: content.sessionPanel
    property alias utilitiesPanel: content.utilitiesPanel

    visible: height > 0
    anchors.topMargin: -5
    implicitWidth: Math.max(sidebarPanel.width, content.implicitWidth)
    implicitHeight: content.implicitHeight

    Content {
        id: content

        anchors.topMargin: -root.anchors.topMargin
        edgeLeft: root.edgeLeft
        visibilities: root.visibilities
    }
}
