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

    // Normal mode (Xor): full window XOR free-area-with-panel-holes
    //   → only chrome/panels receive input; desktop free area is click-through.
    // Multitasking (Combine): free-area rectangle is the mask itself
    //   → dimmed area can dismiss; bottom dockClearance is NOT in the mask
    //   so Overlay dock keeps hover + clicks. Shrinking free-area under Xor
    //   would do the OPPOSITE (make the bottom strip interactive on drawers).
    x: multitaskingOpen ? 0 : bar.clampedWidth + win.dragMaskPadding
    y: multitaskingOpen ? 0 : clampedThickness + win.dragMaskPadding
    width: multitaskingOpen ? win.width : win.width - bar.clampedWidth - clampedThickness - win.dragMaskPadding * 2
    height: multitaskingOpen ? Math.max(0, win.height - dockClearance) : win.height - clampedThickness * 2 - win.dragMaskPadding * 2
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
        x: root.win.width - width
        width: panel.width * (1 - root.panels.sidebar.offsetScale) + root.borderThickness
    }

    R {
        panel: root.panels.osdWrapper
        x: root.win.width - width
        width: panel.width * (1 - root.panels.osd.offsetScale) + root.borderThickness + sidebarRegion.width
    }

    R {
        panel: root.panels.notifications
        y: 0
        height: panel.height + root.borderThickness
    }

    R {
        panel: root.panels.utilities
        y: root.win.height - height
        height: panel.height * (1 - root.panels.utilities.offsetScale) + root.borderThickness
    }

    R {
        panel: root.panels.popoutsWrapper
        width: panel.width * (1 - root.panels.popoutsWrapper.offsetScale)
    }

    component R: Region {
        required property Item panel

        x: panel.x + root.bar.implicitWidth
        y: panel.y + root.borderThickness
        // Under Combine multitasking mask, Subtract children would cut holes in
        // the dismiss area — disable them (zero size is a no-op subtract).
        width: root.multitaskingOpen ? 0 : panel.width
        height: root.multitaskingOpen ? 0 : panel.height
        intersection: Intersection.Subtract
    }
}
