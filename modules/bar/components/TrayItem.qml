pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import Caelestia.Config
import qs.components.effects
import qs.services
import qs.utils

MouseArea {
    id: root

    required property SystemTrayItem modelData

    acceptedButtons: Qt.LeftButton | Qt.RightButton
    implicitWidth: Tokens.font.body.small.pointSize * 2
    implicitHeight: Tokens.font.body.small.pointSize * 2

    onClicked: event => {
        if (event.button === Qt.LeftButton)
            modelData.activate();
        else
            modelData.secondaryActivate();
    }

    // Prefer the raw tray pixmap/name. Only recolour when the user explicitly
    // enables tray recolouring — otherwise monochrome/black icons vanish on a
    // dark bar and some SNI pixmaps fail under Colouriser.
    Item {
        anchors.fill: parent

        IconImage {
            anchors.fill: parent
            asynchronous: true
            source: Icons.getTrayIcon(root.modelData.id, root.modelData.icon)
            visible: !Config.bar.tray.recolour
        }

        ColouredIcon {
            anchors.fill: parent
            source: Icons.getTrayIcon(root.modelData.id, root.modelData.icon)
            colour: Colours.palette.m3secondary
            visible: Config.bar.tray.recolour
            layer.enabled: true
        }
    }
}
