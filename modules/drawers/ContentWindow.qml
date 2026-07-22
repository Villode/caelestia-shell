pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Caelestia.Blobs
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.modules.bar

StyledWindow {
    id: root

    readonly property alias bar: bar
    readonly property alias interactionWrapper: interactions

    readonly property HyprlandMonitor monitor: Hypr.monitorFor(screen)
    readonly property bool hasSpecialWorkspace: (monitor?.lastIpcObject.specialWorkspace?.name.length ?? 0) > 0
    readonly property bool hasFullscreenOnNormalWs: monitor?.activeWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false
    readonly property bool hasFullscreen: {
        if (hasSpecialWorkspace) {
            const specialName = monitor?.lastIpcObject.specialWorkspace?.name;
            if (!specialName)
                return false;
            const specialWs = Hypr.workspaces.values.find(ws => ws.name === specialName);
            return specialWs?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false;
        }
        return hasFullscreenOnNormalWs;
    }

    property real fsTransitionProg: hasFullscreen ? 1 : 0
    readonly property real sdfBorderOffset: 2 * fsTransitionProg // SDFs joins are not exact, so offset by 2px to ensure nothing shows
    readonly property real borderThickness: contentItem.Config.border.thickness * (1 - fsTransitionProg)
    readonly property real borderRounding: contentItem.Config.border.rounding * (1 - fsTransitionProg)
    readonly property real shadowOpacity: 0.7 * (1 - fsTransitionProg)
    readonly property real borderLayoutThickness: hasFullscreen ? 0 : contentItem.Config.border.thickness

    property color surfaceColour: Colours.tPalette.m3surface

    readonly property int dragMaskPadding: {
        if (focusGrab.active || panels.popouts.isDetached)
            return 0;

        if (monitor?.lastIpcObject.specialWorkspace?.name || monitor?.activeWorkspace.lastIpcObject.windows > 0)
            return 0;

        const thresholds = [];
        for (const panel of ["dashboard", "launcher", "session", "sidebar", "clipboard"])
            if (contentItem.Config[panel].enabled)
                thresholds.push(contentItem.Config[panel].dragThreshold);
        return Math.max(...thresholds);
    }

    onHasFullscreenChanged: {
        visibilities.launcher = false;
        visibilities.session = false;
        visibilities.clipboard = false;
        visibilities.multitasking = false;
        visibilities.dashboard = false;
        panels.popouts.close();
    }

    name: "drawers"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: (fsTransitionProg > 0 && contentItem.Config.general.showOverFullscreen) || (hasSpecialWorkspace && hasFullscreenOnNormalWs) ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: visibilities.launcher || visibilities.session || visibilities.clipboard || visibilities.multitasking ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: hasFullscreen ? emptyRegion : regions

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    Behavior on fsTransitionProg {
        Anim {}
    }

    Behavior on surfaceColour {
        CAnim {}
    }

    Region {
        id: emptyRegion

        x: panels.notifications.x + (bar.isLeft ? bar.implicitWidth : 0)
        y: panels.notifications.y + (bar.isTop ? bar.implicitHeight : root.borderThickness)
        width: panels.notifications.width
        height: panels.notifications.height

        Region {
            x: panels.osdWrapper.onLeft ? 0 : (root.width - width)
            y: panels.osdWrapper.y + root.borderThickness
            width: panels.osdWrapper.width * (1 - panels.osd.offsetScale) + root.borderThickness
            height: panels.osd.height
        }
    }

    Regions {
        id: regions

        bar: bar
        panels: panels
        win: root
    }

    HyprlandFocusGrab {
        id: focusGrab

        // Do NOT include multitasking — FocusGrab can monopolize input and freeze the external dock.
        // Multitasking uses Esc on its own content + click empty strip + logo toggle.
        active: (visibilities.launcher && root.contentItem.Config.launcher.enabled) || (visibilities.session && root.contentItem.Config.session.enabled) || (visibilities.clipboard && root.contentItem.Config.utilities.clipboard.enabled) || (visibilities.sidebar && root.contentItem.Config.sidebar.enabled) || (!root.contentItem.Config.dashboard.showOnHover && visibilities.dashboard && root.contentItem.Config.dashboard.enabled) || (panels.popouts.currentName.startsWith("traymenu") && (panels.popouts.current as StackView)?.depth > 1)
        windows: [root]
        onCleared: {
            visibilities.launcher = false;
            visibilities.session = false;
            visibilities.clipboard = false;
            // leave multitasking alone here — closed by its own UI / logo
            visibilities.sidebar = false;
            visibilities.dashboard = false;
            panels.popouts.hasCurrent = false;
            bar.closeTray();
        }
    }

    Connections {
        target: panels.popouts

        function onHasCurrentChanged(): void {
            // The multitasking scrim sits in the same layer surface and would
            // darken the translucent popout before Hyprland can blur it.
            if (panels.popouts.hasCurrent)
                visibilities.multitasking = false;
        }
    }

    // Dim desktop (must sit UNDER blob panel backgrounds so top popouts keep glass).
    // Full-screen visual only — dock is Overlay above this Top layer. Input for
    // dismiss is handled by Regions (Combine mask) + Interactions click handler;
    // do NOT put a full-window MouseArea here (it cannot clear the Overlay dock,
    // and under Xor masks free-area clicks never reach it anyway).
    StyledRect {
        id: modalScrim
        anchors.fill: parent
        color: "#000000"
        opacity: {
            if (visibilities.multitasking)
                return 0.55;
            if (visibilities.session && Config.session.enabled)
                return 0.55;
            if (visibilities.clipboard && Config.utilities.clipboard.enabled)
                return 0.55;
            if (panels.popouts.detachedMode !== "")
                return 0.55;
            return 0;
        }
        z: 0

        Behavior on opacity {
            Anim {
                type: Anim.SlowEffects
            }
        }
    }

    Item {
        anchors.fill: parent
        // Above scrim so frosted panel shells stay solid/visible
        z: 1
        opacity: root.surfaceColour.a
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            blurMax: 15
            shadowColor: Qt.alpha(Colours.palette.m3shadow, Math.max(0, root.shadowOpacity))
        }

        BlobGroup {
            id: blobGroup

            color: root.surfaceColour
            smoothing: root.contentItem.Config.border.smoothing
        }

        BlobInvertedRect {
            anchors.fill: parent
            anchors.margins: -50 // Make border thicker to smooth out bulge from closed drawers
            group: blobGroup
            radius: root.borderRounding
            borderLeft: (bar.isRight ? root.borderThickness : bar.isTop ? root.borderThickness : bar.implicitWidth) - anchors.margins - root.sdfBorderOffset
            borderRight: (bar.isRight ? bar.implicitWidth : root.borderThickness) - anchors.margins - root.sdfBorderOffset
            borderTop: (bar.isTop ? bar.implicitHeight : root.borderThickness) - anchors.margins - root.sdfBorderOffset
            borderBottom: root.borderThickness - anchors.margins - root.sdfBorderOffset
        }

        PanelBg {
            id: dashBg

            panel: panels.dashboard
            deformAmount: 0.1
            // y is offset by top-bar height or the top border thickness. Height must
            // subtract the same offset or the glass hangs past the content bottom
            // (exterior strip under the dashboard, often most visible on Performance).
            implicitHeight: {
                const yOff = bar.isTop ? bar.implicitHeight : root.borderThickness;
                return Math.max(0, panel.height - yOff);
            }
        }

        PanelBg {
            id: launcherBg

            panel: panels.launcher
            deformAmount: 0.1
        }

        PanelBg {
            id: sessionBg

            // Floating center panel — standard panel tracking, light deform
            panel: panels.sessionWrapper
            deformAmount: 0.06
            visible: panels.session.visible
        }

        PanelBg {
            id: clipboardBg

            panel: panels.clipboardWrapper
            deformAmount: 0.06
            visible: panels.clipboard.visible
        }

        // Multitasking uses only the scrim — no BlobRect panel background

        PanelBg {
            id: sidebarBg

            panel: panels.sidebar
            deformAmount: 0.03
            implicitHeight: panel.height * (1 / rawDeformMatrix.m22) + 2
            exclude: panels.sidebar.offsetScale > 0.08 ? [] : [utilsBg]
            bottomLeftRadius: Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius
        }

        PanelBg {
            id: osdBg

            panel: panels.osdWrapper
            deformAmount: 0.25
            x: panels.osdWrapper.x + panels.osd.x + (bar.isLeft ? bar.implicitWidth : 0)
            y: panels.osdWrapper.y + panels.osd.y + (bar.isTop ? bar.implicitHeight : root.borderThickness)
            implicitWidth: panels.osd.width
            implicitHeight: panels.osd.height
        }

        PanelBg {
            id: notifsBg

            panel: panels.notifications
        }

        PanelBg {
            id: utilsBg

            panel: panels.utilities
            deformAmount: panels.sidebar.visible ? 0.1 : 0.15
            exclude: panels.sidebar.offsetScale > 0.08 ? [] : [sidebarBg]
            topLeftRadius: Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius
        }

        PanelBg {
            id: popoutBg

            // Extra size along the bar attachment axis keeps deform from detaching the blob.
            // Right-bar popouts slide like the dashboard (no wipe stretch).
            property real extraAlong: (panels.popouts.isDetached || bar.isRight) ? 0 : 0.2
            readonly property bool fromTop: bar.isTop
            readonly property bool fromRight: bar.isRight
            readonly property bool popVisible: panels.popouts.hasCurrent || panels.popouts.isDetached || panels.popoutsWrapper.midTransition || panels.popoutsWrapper.open > 0.01

            panel: panels.popoutsWrapper
            visible: popVisible
            deformAmount: panels.popouts.isDetached ? 0.05 : (panels.popouts.hasCurrent ? 0.15 : 0.1)
            // Follow wrapper fade for right-edge slide (dashboard-style).
            opacity: bar.isRight ? panels.popoutsWrapper.opacity : 1
            x: {
                const base = panels.popoutsWrapper.x + panels.popouts.x + (bar.isLeft ? bar.implicitWidth : 0);
                if (fromTop || fromRight)
                    return base;
                return base - panels.popouts.width * extraAlong;
            }
            y: {
                const base = panels.popoutsWrapper.y + panels.popouts.y + (bar.isTop ? bar.implicitHeight : root.borderThickness);
                if (fromTop)
                    return base - panels.popouts.height * extraAlong;
                return base;
            }
            implicitWidth: popVisible ? (fromTop || fromRight ? panels.popouts.width : panels.popouts.width * (1 + extraAlong)) : 0
            implicitHeight: popVisible ? (fromTop ? panels.popouts.height * (1 + extraAlong) : panels.popouts.height) : 0

            Behavior on extraAlong {
                Anim {}
            }
        }
    }

    DrawerVisibilities {
        id: visibilities

        Component.onCompleted: Visibilities.load(root.screen, this)
    }

    Interactions {
        id: interactions
        // Above blob + scrim so interactive content (cards, popouts) is visible
        z: 2

        screen: root.screen
        popouts: panels.popouts
        visibilities: visibilities
        panels: panels
        bar: bar
        borderThickness: root.borderLayoutThickness
        fullscreen: root.hasFullscreen

        Panels {
            id: panels
            z: 1

            screen: root.screen
            visibilities: visibilities
            bar: bar
            borderThickness: root.borderThickness

            utilities.horizontalStretch: (sidebarBg.rawDeformMatrix.m11 - 1) / 2 + 1
            utilities.deformMatrix: utilsBg.rawDeformMatrix

            dashboard.transform: Matrix4x4 {
                matrix: dashBg.deformMatrix
            }
            launcher.transform: Matrix4x4 {
                matrix: launcherBg.deformMatrix
            }
            // Session is a centered floating menu — do not apply edge-rail deform
            // (that matrix is for side panels and can hide/shift center content).
            sidebar.transform: Matrix4x4 {
                matrix: sidebarBg.deformMatrix
            }
            osd.transform: Matrix4x4 {
                matrix: osdBg.deformMatrix
            }
            notifications.transform: Matrix4x4 {
                matrix: notifsBg.deformMatrix
            }
            utilities.transform: Matrix4x4 {
                matrix: utilsBg.deformMatrix
            }
            // Keep popout content aligned with blob; when multitasking scrim is
            // active or the popout is fully closed, skip deform (avoids ghost blobs).
            popouts.transform: Matrix4x4 {
                matrix: (visibilities.multitasking || !popoutBg.popVisible) ? Qt.matrix4x4() : popoutBg.deformMatrix
            }
        }

        // Bar always above multitasking / panels content (logo, status, popouts anchor)
        BarWrapper {
            id: bar
            z: 500

            // Explicit geometry: conditional anchors do not clear when position changes at runtime.
            x: bar.isRight ? parent.width - width : 0
            y: 0
            width: bar.isVertical ? bar.shownThickness : parent.width
            height: bar.isVertical ? parent.height : bar.shownThickness

            screen: root.screen
            visibilities: visibilities
            popouts: panels.popouts

            fullscreen: root.hasFullscreen

            Component.onCompleted: Visibilities.bars.set(root.screen, this)
        }
    }

    component PanelBg: BlobRect {
        required property Item panel
        property real deformAmount: 0.15

        visible: panel.visible
        group: blobGroup
        x: panel.x + (bar.isLeft ? bar.implicitWidth : 0)
        y: panel.y + (bar.isTop ? bar.implicitHeight : root.borderThickness)
        implicitWidth: panel.width
        implicitHeight: panel.height
        radius: Tokens.rounding.extraLarge
        deformScale: (deformAmount * Config.appearance.deformScale) / 10000
    }
}
