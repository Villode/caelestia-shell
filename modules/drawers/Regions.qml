pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.modules.bar as Bar

Region {
    id: root

    required property Bar.BarWrapper bar
    required property Panels panels
    required property var win

    readonly property real borderThickness: win.contentItem.Config.border.thickness
    readonly property real clampedThickness: win.contentItem.Config.border.clampedThickness

    // villode-dock Overlay is 128px tall; leave a pass-through strip so icon
    // hover/magnify still receives events through drawers' input mask.
    readonly property real dockClearance: 160

    readonly property bool multitaskingOpen: {
        const v = root.panels.visibilities;
        return !!(v && v.multitasking);
    }

    readonly property real leftInset: bar.isLeft ? bar.clampedThickness : clampedThickness
    readonly property real rightInset: bar.isRight ? bar.clampedThickness : clampedThickness
    readonly property real topInset: bar.isTop ? bar.clampedThickness : clampedThickness
    readonly property real bottomInset: clampedThickness
    readonly property real panelXOffset: bar.isLeft ? bar.implicitWidth : 0
    readonly property real panelYOffset: bar.isTop ? bar.implicitHeight : borderThickness

    // Normal mode (Xor): full window XOR free-area-with-panel-holes
    //   → only chrome/panels receive input; desktop free area is click-through.
    // Multitasking (Combine): free-area rectangle is the mask itself
    //   → dimmed area can dismiss; bottom dockClearance is NOT in the mask
    //   so Overlay dock keeps hover + clicks. Shrinking free-area under Xor
    //   would do the OPPOSITE (make the bottom strip interactive on drawers).
    x: multitaskingOpen ? 0 : leftInset + win.dragMaskPadding
    y: multitaskingOpen ? 0 : topInset + win.dragMaskPadding
    width: multitaskingOpen ? win.width : win.width - leftInset - rightInset - win.dragMaskPadding * 2
    height: multitaskingOpen ? Math.max(0, win.height - dockClearance) : win.height - topInset - bottomInset - win.dragMaskPadding * 2
    intersection: multitaskingOpen ? Intersection.Combine : Intersection.Xor

    R {
        panel: root.panels.dashboard
        y: 0
        height: panel.height * (1 - root.panels.dashboard.offsetScale) + root.borderThickness
    }

    R {
        panel: root.panels.launcher
        y: root.win.height - height
        height: panel.height * (1 - root.panels.launcher.offsetScale) + root.borderThickness
    }

    R {
        id: sessionRegion

        // Centered session menu — track the floating panel bounds
        panel: root.panels.sessionWrapper
    }

    R {
        id: clipboardRegion

        // Centered clipboard history — track floating panel bounds
        panel: root.panels.clipboardWrapper
    }

    // Multitasking cards strip — only needed in Xor mode (as a hole → interactive).
    // In Combine multitasking mode the whole free area is already interactive.
    R {
        panel: root.panels.multitaskingWrapper
        width: (!root.multitaskingOpen && root.panels.multitaskingWrapper.visible) ? panel.width : 0
        height: (!root.multitaskingOpen && root.panels.multitaskingWrapper.visible) ? panel.height : 0
    }

    R {
        id: sidebarRegion

        panel: root.panels.sidebar
        x: root.panels.sidebar.edgeLeft ? root.panelXOffset : (root.win.width - width)
        width: panel.width * (1 - root.panels.sidebar.offsetScale) + root.borderThickness
    }

    R {
        panel: root.panels.osdWrapper
        x: root.panels.osdWrapper.onLeft ? root.panelXOffset : (root.win.width - width)
        width: Math.max(panel.width * (1 - root.panels.osd.offsetScale), root.clampedThickness) + root.borderThickness + (root.panels.osdWrapper.onLeft ? 0 : sidebarRegion.width)
    }

    R {
        panel: root.panels.notifications
        x: root.panels.sidebar.edgeLeft ? root.panelXOffset : (root.win.width - width)
        y: 0
        height: panel.height + root.borderThickness
    }

    R {
        panel: root.panels.utilities
        x: root.panels.sidebar.edgeLeft ? root.panelXOffset : (root.win.width - width)
        y: root.win.height - height
        height: panel.height * (1 - root.panels.utilities.offsetScale) + root.borderThickness
    }

    R {
        panel: root.panels.popoutsWrapper
        // Hide input region when fully closed (prevents residual hit targets / ghost chrome).
        width: {
            if (root.panels.popoutsWrapper.fullyClosed)
                return 0;
            if (root.bar.isRight)
                return panel.width;
            return panel.width * (1 - root.panels.popoutsWrapper.offsetScale);
        }
        height: {
            if (root.panels.popoutsWrapper.fullyClosed)
                return 0;
            if (root.bar.isTop)
                return panel.height * (1 - root.panels.popoutsWrapper.offsetScale);
            return panel.height;
        }
    }

    component R: Region {
        required property Item panel

        x: panel.x + root.panelXOffset
        y: panel.y + root.panelYOffset
        // Under Combine multitasking mask, Subtract children would cut holes in
        // the dismiss area — disable them (zero size is a no-op subtract).
        width: root.multitaskingOpen ? 0 : panel.width
        height: root.multitaskingOpen ? 0 : panel.height
        intersection: Intersection.Subtract
    }
}
