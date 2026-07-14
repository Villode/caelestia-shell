pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia
import Caelestia.Config
import qs.components
import qs.modules.sidebar as Sidebar
import qs.modules.bar.popouts as BarPopouts

Item {
    id: root

    required property DrawerVisibilities visibilities
    required property Sidebar.Wrapper sidebar
    required property BarPopouts.Wrapper popouts
    property real horizontalStretch
    property matrix4x4 deformMatrix
    // When true, chrome sits on the left edge (taskbar on the right).
    property bool edgeLeft: false

    readonly property PersistentProperties props: PersistentProperties {
        property bool recordingListExpanded: false
        property string recordingConfirmDelete
        property string recordingMode
        property string screenshotMode

        reloadableId: "utilities"
    }
    readonly property bool shouldBeActive: visibilities.sidebar || (visibilities.utilities && Config.utilities.enabled && !(visibilities.session && Config.session.enabled))
    readonly property real totalPadding: Tokens.padding.large + CUtils.clamp(Tokens.padding.large - Config.border.thickness, 0, Tokens.padding.large)
    readonly property real nonAnimHeight: ((content.item as Content)?.nonAnimHeight ?? 0) + totalPadding
    property real offsetScale: shouldBeActive ? 0 : 1
    property real sidebarLerp

    visible: offsetScale < 1
    anchors.bottomMargin: (-implicitHeight - 5) * offsetScale
    implicitHeight: content.implicitHeight + totalPadding
    implicitWidth: sidebar.width * (1 - sidebar.offsetScale) * horizontalStretch * sidebarLerp + Tokens.sizes.utilities.width * (1 - sidebarLerp)
    opacity: 1 - offsetScale

    states: State {
        name: "attachedToSidebar"
        when: root.visibilities.sidebar

        PropertyChanges {
            root.sidebarLerp: 1
        }
    }

    transitions: [
        Transition {
            from: ""

            Anim {
                property: "sidebarLerp"
                duration: Tokens.anim.durations.expressiveDefaultSpatial / 2
                easing: Tokens.anim.standardAccel
            }
        },
        Transition {
            to: ""

            Anim {
                property: "sidebarLerp"
                duration: Tokens.anim.durations.expressiveDefaultSpatial / 2
                easing: Tokens.anim.standardDecel
            }
        }
    ]

    Behavior on offsetScale {
        Anim {}
    }

    Loader {
        id: content

        // Right chrome: pad from left (inner). Left chrome: pad from right (inner).
        readonly property real innerPad: Tokens.padding.large
        readonly property real outerPad: CUtils.clamp(innerPad - Config.border.thickness, 0, innerPad)

        anchors.top: parent.top
        anchors.left: root.edgeLeft ? parent.left : undefined
        anchors.right: root.edgeLeft ? undefined : parent.right
        anchors.topMargin: innerPad
        anchors.leftMargin: root.edgeLeft ? outerPad : innerPad
        anchors.rightMargin: root.edgeLeft ? innerPad : outerPad

        // Build the utility cards once in the background. Destroying them when
        // the drawer closes makes every open animation compete with recreating
        // screenshot, recording and toggle controls, so the contents pop in.
        asynchronous: true
        active: true

        sourceComponent: Content {
            implicitWidth: root.implicitWidth - root.totalPadding
            props: root.props
            visibilities: root.visibilities
            popouts: root.popouts
            deformMatrix: root.deformMatrix
        }
    }
}
