pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services as Svc
import qs.modules.bar.popouts // Need to import this module so the Wrapper type is the same as others

Item {
    id: root

    required property ShellScreen screen
    required property real borderThickness

    readonly property alias content: content
    property real offsetScale: x > 0 || content.hasCurrent ? 0 : 1

    // Opaque fill for the sliding popout shell (palette colours may be translucent).
    readonly property color shellBg: {
        const c = Svc.Colours.palette.m3surfaceContainer;
        return Qt.rgba(c.r, c.g, c.b, 1);
    }

    visible: width > 0 && height > 0
    clip: true

    implicitWidth: content.implicitWidth * (1 - offsetScale)
    implicitHeight: content.implicitHeight

    x: content.isDetached ? (parent.width - content.nonAnimWidth) / 2 : 0
    y: {
        if (content.isDetached)
            return (parent.height - content.nonAnimHeight) / 2;

        const off = content.currentCenter - borderThickness - content.nonAnimHeight / 2;
        const diff = parent.height - Math.floor(off + content.nonAnimHeight);
        if (diff < 0)
            return off + diff;
        return Math.max(off, 0);
    }

    Behavior on offsetScale {
        Anim {}
    }

    Behavior on x {
        Anim {
            duration: content.animLength
            easing: content.animCurve
        }
    }

    Behavior on y {
        enabled: root.offsetScale < 1

        Anim {
            duration: content.animLength
            easing: content.animCurve
        }
    }

    // Solid backdrop behind sliding content
    Rectangle {
        anchors.verticalCenter: content.verticalCenter
        anchors.left: content.left
        width: content.width
        height: content.height
        radius: Tokens.rounding.extraLarge
        color: root.shellBg
        visible: content.hasCurrent && !content.isDetached && content.width > 1
        z: 0
    }

    Wrapper {
        id: content

        screen: root.screen
        offsetScale: root.offsetScale

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: (-implicitWidth - 5) * root.offsetScale
    }
}
