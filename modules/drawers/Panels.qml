import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.bar as Bar
import qs.modules.dashboard as Dashboard
import qs.modules.launcher as Launcher
import qs.modules.notifications as Notifications
import qs.modules.osd as Osd
import qs.modules.session as Session
import qs.modules.multitasking as Multitasking
import qs.modules.sidebar as Sidebar
import qs.modules.utilities as Utilities
import qs.modules.bar.popouts as BarPopouts
import qs.modules.utilities.toasts as Toasts

Item {
    id: root

    required property ShellScreen screen
    required property DrawerVisibilities visibilities
    required property Bar.BarWrapper bar
    required property real borderThickness

    readonly property alias osd: osd
    readonly property alias osdWrapper: osdWrapper
    readonly property alias notifications: notifications
    readonly property alias session: session
    readonly property alias sessionWrapper: sessionWrapper
    readonly property alias multitasking: multitasking
    readonly property alias multitaskingWrapper: multitaskingWrapper
    readonly property alias launcher: launcher
    readonly property alias dashboard: dashboard
    readonly property alias popouts: popoutsWrapper.content
    readonly property alias popoutsWrapper: popoutsWrapper
    readonly property alias utilities: utilities
    readonly property alias toasts: toasts
    readonly property alias sidebar: sidebar

    anchors.fill: parent
    anchors.margins: borderThickness
    anchors.leftMargin: bar.implicitWidth

    // Multitasking: ONLY the card strip height — do not cover dock / bottom chrome.
    // Dimming is ContentWindow.modalScrim (visual only). Empty clicks on cards strip dismiss.
    Item {
        id: multitaskingWrapper

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        // Height = card strip only (not full screen) so bottom dock stays free for input
        height: multitasking.visible || multitasking.shouldBeActive ? multitasking.implicitHeight + Tokens.padding.large : 0
        visible: multitasking.visible || multitasking.shouldBeActive
        z: 10
        clip: false

        // Dismiss when clicking empty space within the strip (not full screen)
        MouseArea {
            anchors.fill: parent
            z: 0
            onClicked: root.visibilities.multitasking = false
        }

        Multitasking.Wrapper {
            id: multitasking

            visibilities: root.visibilities
            screen: root.screen

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: implicitHeight
            z: 1
        }
    }

    Launcher.Wrapper {
        id: launcher
        z: 12

        screen: root.screen
        visibilities: root.visibilities
        panels: root

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
    }

    Dashboard.Wrapper {
        id: dashboard
        // Top dashboard must stay above multitasking cards
        z: 120

        visibilities: root.visibilities

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
    }

    // Power / session menu — centered modal
    Item {
        id: sessionWrapper

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        readonly property real pad: Tokens.padding.extraLarge
        width: session.implicitWidth + pad * 2
        height: session.implicitHeight + pad * 2
        visible: session.visible || session.shouldBeActive
        z: 100

        Session.Wrapper {
            id: session

            visibilities: root.visibilities
            sidebarVisible: sidebar.visible

            anchors.centerIn: parent
            width: implicitWidth
            height: implicitHeight
        }
    }

    // —— Shell chrome (always above multitasking) ——
    Item {
        id: osdWrapper
        z: 200

        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: sidebar.width * (1 - sidebar.offsetScale)
        clip: sidebar.visible

        implicitWidth: osd.implicitWidth * (1 - osd.offsetScale)
        implicitHeight: osd.implicitHeight

        Osd.Wrapper {
            id: osd

            screen: root.screen
            visibilities: root.visibilities
            sidebarOrSessionVisible: sidebar.visible || session.visible

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
        }
    }

    Notifications.Wrapper {
        id: notifications
        z: 210

        visibilities: root.visibilities
        sidebarPanel: sidebar
        osdPanel: osdWrapper
        sessionPanel: sessionWrapper
        utilitiesPanel: utilities

        anchors.top: parent.top
        anchors.right: parent.right
    }

    BarPopouts.ClipWrapper {
        id: popoutsWrapper
        z: 220

        screen: root.screen
        borderThickness: root.borderThickness
    }

    Utilities.Wrapper {
        id: utilities
        z: 200

        visibilities: root.visibilities
        sidebar: sidebar
        popouts: popoutsWrapper.content

        anchors.bottom: parent.bottom
        anchors.right: parent.right
    }

    Toasts.Toasts {
        id: toasts
        z: 230

        anchors.bottom: sidebar.visible ? parent.bottom : utilities.top
        anchors.right: sidebar.left
        anchors.margins: Tokens.padding.medium
    }

    Sidebar.Wrapper {
        id: sidebar
        z: 200

        visibilities: root.visibilities

        anchors.top: notifications.bottom
        anchors.bottom: utilities.top
        anchors.right: parent.right
        anchors.topMargin: -notifications.anchors.topMargin
    }
}
