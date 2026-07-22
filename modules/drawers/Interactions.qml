import QtQuick
import QtQuick.Controls
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.modules.bar as Bar
import qs.modules.bar.popouts as BarPopouts

CustomMouseArea {
    id: root

    required property ShellScreen screen
    required property BarPopouts.Wrapper popouts
    required property DrawerVisibilities visibilities
    required property Panels panels
    required property Bar.BarWrapper bar
    required property real borderThickness
    required property bool fullscreen

    property point dragStart
    property bool dashboardShortcutActive
    property bool osdShortcutActive
    property bool utilitiesShortcutActive
    property bool clipboardShortcutActive

    readonly property real contentXOffset: bar.isLeft ? bar.implicitWidth : 0
    readonly property real contentYOffset: bar.isTop ? bar.implicitHeight : borderThickness

    function withinPanelHeight(panel: Item, x: real, y: real): bool {
        const panelY = root.contentYOffset + panel.y;
        return y >= panelY - Config.border.rounding && y <= panelY + panel.height + Config.border.rounding;
    }

    function withinPanelWidth(panel: Item, x: real, y: real): bool {
        const panelX = root.contentXOffset + panel.x;
        return x >= panelX - Config.border.rounding && x <= panelX + panel.width + Config.border.rounding;
    }

    function inBarArea(x: real, y: real): bool {
        if (bar.isLeft)
            return x < bar.clampedThickness;
        if (bar.isRight)
            return x > width - bar.clampedThickness;
        return y < bar.clampedThickness;
    }

    function inLeftPanel(panel: Item, x: real, y: real): bool {
        return x < root.contentXOffset + panel.x + panel.width && withinPanelHeight(panel, x, y);
    }

    function inRightPanel(panel: Item, x: real, y: real): bool {
        const edge = bar.isRight ? width - bar.implicitWidth : width;
        return x > Math.min(edge - Config.border.minThickness, root.contentXOffset + panel.x) && withinPanelHeight(panel, x, y);
    }

    function inOsdPanel(panel: Item, x: real, y: real): bool {
        // OSD (and its closed hit strip) sits on the side opposite the taskbar when bar is L/R.
        if (!withinPanelHeight(panel, x, y))
            return false;
        if (bar.isRight) {
            const hit = Math.max(panel.width, Config.border.minThickness, borderThickness);
            return x < root.contentXOffset + hit;
        }
        return inRightPanel(panel, x, y);
    }

    function inChromePanel(panel: Item, x: real, y: real): bool {
        // Notifications / sidebar / utilities share the chrome edge.
        if (bar.isRight)
            return inLeftPanel(panel, x, y);
        return inRightPanel(panel, x, y);
    }

    function chromeEdgeX(): real {
        // Screen-space X of the free edge used for sidebar open gestures.
        if (bar.isRight)
            return root.contentXOffset + Config.border.minThickness;
        return Math.min(width - Config.border.minThickness, root.contentXOffset + panels.sidebar.x);
    }

    function inTopPanel(panel: Item, x: real, y: real): bool {
        const panelHeight = panel.height * (1 - (panel.offsetScale ?? 0)); // qmllint disable missing-property
        const topEdge = bar.isTop ? bar.implicitHeight : Config.border.thickness;
        return y < Math.max(Config.border.minThickness, topEdge + panelHeight) && withinPanelWidth(panel, x, y);
    }

    function inBottomPanel(panel: Item, x: real, y: real, isCorner = false): bool {
        const panelHeight = panel.height * (1 - (panel.offsetScale ?? 0)); // qmllint disable missing-property
        return y > height - Math.max(Config.border.minThickness, Config.border.thickness + panelHeight) - (isCorner ? Config.border.rounding : 0) && withinPanelWidth(panel, x, y);
    }

    function onWheel(event: WheelEvent): void {
        if (fullscreen)
            return;
        if (inBarArea(event.x, event.y)) {
            const pos = bar.isTop ? event.x : event.y;
            bar.handleWheel(pos, event.angleDelta);
        }
    }

    anchors.fill: parent
    acceptedButtons: fullscreen ? Qt.NoButton : Qt.AllButtons
    hoverEnabled: true

    onPressed: event => dragStart = Qt.point(event.x, event.y)

    // Multitasking dismiss: free-area clicks land here (scrim is visual-only).
    // Card / strip MouseAreas accept first; if we get the click it's empty dim.
    onClicked: {
        if (visibilities.multitasking)
            visibilities.multitasking = false;
        // Corner clipboard panel: click free area to dismiss (not full-screen modal).
        if (visibilities?.clipboard && panels.clipboard && !inBottomPanel(panels.clipboard, mouseX, mouseY, true))
            visibilities.clipboard = false;
    }
    onContainsMouseChanged: {
        if (!containsMouse) {
            // Only hide if not activated by shortcut
            if (!osdShortcutActive) {
                visibilities.osd = false;
                root.panels.osd.hovered = false;
            }

            if (!dashboardShortcutActive)
                visibilities.dashboard = false;

            if (!utilitiesShortcutActive)
                visibilities.utilities = false;
            if (!clipboardShortcutActive && visibilities)
                visibilities.clipboard = false;

            if (!popouts.currentName.startsWith("traymenu") || ((popouts.current as StackView)?.depth ?? 0) <= 1) {
                popouts.hasCurrent = false;
                bar.closeTray();
            }

            if (Config.bar.showOnHover)
                bar.isHovered = false;

            if (Config.sidebar.showOnHover)
                visibilities.sidebar = false;
        }
    }

    onPositionChanged: event => {
        if (popouts.isDetached)
            return;

        const x = event.x;
        const y = event.y;
        const dragX = x - dragStart.x;
        const dragY = y - dragStart.y;

        if (fullscreen) {
            root.panels.osd.hovered = inOsdPanel(panels.osdWrapper, x, y);
            return;
        }

        // Show bar in non-exclusive mode on hover
        if (!visibilities.bar && Config.bar.showOnHover && inBarArea(x, y))
            bar.isHovered = true;

        // Show/hide bar on drag
        if (pressed && inBarArea(dragStart.x, dragStart.y)) {
            if (bar.isLeft) {
                if (dragX > Config.bar.dragThreshold)
                    visibilities.bar = true;
                else if (dragX < -Config.bar.dragThreshold)
                    visibilities.bar = false;
            } else if (bar.isRight) {
                if (dragX < -Config.bar.dragThreshold)
                    visibilities.bar = true;
                else if (dragX > Config.bar.dragThreshold)
                    visibilities.bar = false;
            } else {
                if (dragY > Config.bar.dragThreshold)
                    visibilities.bar = true;
                else if (dragY < -Config.bar.dragThreshold)
                    visibilities.bar = false;
            }
        }

        if (panels.sidebar.offsetScale === 1) {
            // Show osd on hover
            const showOsd = inOsdPanel(panels.osdWrapper, x, y);

            // Always update visibility based on hover if not in shortcut mode
            if (!osdShortcutActive) {
                visibilities.osd = showOsd;
                root.panels.osd.hovered = showOsd;
            } else if (showOsd) {
                // If hovering over OSD area while in shortcut mode, transition to hover control
                osdShortcutActive = false;
                root.panels.osd.hovered = true;
            }

            const onLeftChrome = bar.isRight;
            const showSidebar = pressed && (onLeftChrome ? dragStart.x < Math.max(Config.border.minThickness, root.contentXOffset + Config.border.minThickness + 8) : dragStart.x > Math.min(width - Config.border.minThickness, root.contentXOffset + panels.sidebar.x));

            // Show sidebar on hover (top corner of chrome edge)
            if (Config.sidebar.showOnHover) {
                const sidebarTriggerY = Math.max(Config.sidebar.minHoverThreshold, panels.notifications.y + panels.notifications.height + borderThickness);
                const showSidebarHover = onLeftChrome ? (x < Math.max(Config.border.minThickness, root.contentXOffset + Config.border.minThickness + 8) && y <= sidebarTriggerY) : (x > Math.min(width - Config.border.minThickness, root.contentXOffset + panels.sidebar.x) && y <= sidebarTriggerY);
                if (showSidebarHover && !visibilities.sidebar)
                    visibilities.sidebar = true;
            }

            // Open sidebar: drag inward from the chrome edge.
            if (showSidebar && (onLeftChrome ? dragX > Config.sidebar.dragThreshold : dragX < -Config.sidebar.dragThreshold))
                visibilities.sidebar = true;
        } else {
            const onLeftChrome = bar.isRight;
            const sidebarExtent = panels.sidebar.width * (1 - panels.sidebar.offsetScale);
            const outOfSidebar = onLeftChrome ? (x > root.contentXOffset + sidebarExtent) : (x < width - sidebarExtent);
            // Show osd on hover
            const showOsd = outOfSidebar && inOsdPanel(panels.osdWrapper, x, y);

            // Always update visibility based on hover if not in shortcut mode
            if (!osdShortcutActive) {
                visibilities.osd = showOsd;
                root.panels.osd.hovered = showOsd;
            } else if (showOsd) {
                // If hovering over OSD area while in shortcut mode, transition to hover control
                osdShortcutActive = false;
                root.panels.osd.hovered = true;
            }

            // Show/hide sidebar on hover
            if (Config.sidebar.showOnHover && !pressed) {
                const sidebarTriggerY = Math.max(Config.sidebar.minHoverThreshold, panels.notifications.y + panels.notifications.height + borderThickness);
                const showSidebarHover = onLeftChrome ? (x < Math.max(Config.border.minThickness, root.contentXOffset + sidebarExtent) && y <= sidebarTriggerY) : (x > Math.min(width - Config.border.minThickness, root.contentXOffset + panels.sidebar.x) && y <= sidebarTriggerY);
                if (showSidebarHover && !visibilities.sidebar) {
                    visibilities.sidebar = true;
                } else {
                    const inSidebarArea = inChromePanel(panels.sidebar, x, y) || inChromePanel(panels.sessionWrapper, x, y);
                    if (!inSidebarArea)
                        visibilities.sidebar = false;
                }
            }

            // Hide sidebar on drag (outward from chrome edge)
            if (pressed && inChromePanel(panels.sidebar, dragStart.x, 0) && (onLeftChrome ? dragX < -Config.sidebar.dragThreshold : dragX > Config.sidebar.dragThreshold))
                visibilities.sidebar = false;
        }

        // Show launcher on hover, or show/hide on drag if hover is disabled
        if (Config.launcher.showOnHover) {
            if (!visibilities.launcher && inBottomPanel(panels.launcher, x, y))
                visibilities.launcher = true;
        } else if (pressed && inBottomPanel(panels.launcher, dragStart.x, dragStart.y) && withinPanelWidth(panels.launcher, x, y)) {
            if (dragY < -Config.launcher.dragThreshold)
                visibilities.launcher = true;
            else if (dragY > Config.launcher.dragThreshold)
                visibilities.launcher = false;
        }

        // Show popouts on hover first so top-bar widget targets can win over dashboard.
        if (inBarArea(x, y)) {
            bar.checkPopout(bar.isTop ? x : y);
        } else if ((!popouts.currentName.startsWith("traymenu") || ((popouts.current as StackView)?.depth ?? 0) <= 1) && !(bar.isLeft ? inLeftPanel(panels.popoutsWrapper, x, y) : (bar.isRight ? inRightPanel(panels.popoutsWrapper, x, y) : inTopPanel(panels.popoutsWrapper, x, y)))) {
            popouts.hasCurrent = false;
            bar.closeTray();
        }

        // Show dashboard on hover.
        // Top bar shares the dashboard edge: only open when not over a bar popout target
        // (clock / tray / status). Active-window hover popouts are skipped on top bars.
        const overDashboard = inTopPanel(panels.dashboard, x, y);
        const barPopoutBlocksDashboard = bar.isTop && popouts.hasCurrent;
        const showDashboard = !visibilities.multitasking && Config.dashboard.showOnHover && overDashboard && !barPopoutBlocksDashboard;

        // Always update visibility based on hover if not in shortcut mode
        if (!dashboardShortcutActive) {
            visibilities.dashboard = showDashboard;
        } else if (showDashboard) {
            // If hovering over dashboard area while in shortcut mode, transition to hover control
            dashboardShortcutActive = false;
        }

        // Show/hide dashboard on drag (for touchscreen devices)
        if (!visibilities.multitasking && pressed && inTopPanel(panels.dashboard, dragStart.x, dragStart.y) && withinPanelWidth(panels.dashboard, x, y)) {
            if (dragY > Config.dashboard.dragThreshold)
                visibilities.dashboard = true;
            else if (dragY < -Config.dashboard.dragThreshold)
                visibilities.dashboard = false;
        }

        // Never stack top dashboard and bar popouts.
        if (bar.isTop && visibilities.dashboard && popouts.hasCurrent) {
            popouts.hasCurrent = false;
            bar.closeTray();
        }

        // Show utilities on hover
        const showUtilities = inBottomPanel(panels.utilities, x, y, true);

        // Always update visibility based on hover if not in shortcut mode
        if (!utilitiesShortcutActive) {
            visibilities.utilities = showUtilities;
        } else if (showUtilities) {
            // If hovering over utilities area while in shortcut mode, transition to hover control
            utilitiesShortcutActive = false;
        }
    }

    // Monitor individual visibility changes
    Connections {
        function onMultitaskingChanged() {
            if (root.visibilities.multitasking) {
                root.dashboardShortcutActive = false;
                root.visibilities.dashboard = false;
            }
        }

        function onLauncherChanged() {
            // If launcher is hidden, clear shortcut flags for dashboard and OSD
            if (!root.visibilities.launcher) {
                root.dashboardShortcutActive = false;
                root.osdShortcutActive = false;
                root.utilitiesShortcutActive = false;

                // Also hide dashboard and OSD if they're not being hovered
                const inDashboardArea = root.inTopPanel(root.panels.dashboard, root.mouseX, root.mouseY);
                const inOsdArea = root.inOsdPanel(root.panels.osdWrapper, root.mouseX, root.mouseY);

                if (!inDashboardArea) {
                    root.visibilities.dashboard = false;
                }
                if (!inOsdArea) {
                    root.visibilities.osd = false;
                    root.panels.osd.hovered = false;
                }
            }
        }

        function onDashboardChanged() {
            if (root.visibilities.dashboard) {
                // Dashboard became visible, immediately check if this should be shortcut mode
                const inDashboardArea = root.inTopPanel(root.panels.dashboard, root.mouseX, root.mouseY);
                if (!inDashboardArea) {
                    root.dashboardShortcutActive = true;
                }
            } else {
                // Dashboard hidden, clear shortcut flag
                root.dashboardShortcutActive = false;
            }
        }

        function onOsdChanged() {
            if (root.visibilities.osd) {
                // OSD became visible, immediately check if this should be shortcut mode
                const inOsdArea = root.inOsdPanel(root.panels.osdWrapper, root.mouseX, root.mouseY);
                if (!inOsdArea) {
                    root.osdShortcutActive = true;
                }
            } else {
                // OSD hidden, clear shortcut flag
                root.osdShortcutActive = false;
            }
        }

        function onUtilitiesChanged() {
            if (root.visibilities.utilities) {
                // Utilities became visible, immediately check if this should be shortcut mode
                const inUtilitiesArea = root.inBottomPanel(root.panels.utilities, root.mouseX, root.mouseY);
                if (!inUtilitiesArea) {
                    root.utilitiesShortcutActive = true;
                }
            } else {
                // Utilities hidden, clear shortcut flag
                root.utilitiesShortcutActive = false;
            }
        }

        function onClipboardChanged() {
            if (!root.visibilities || !root.panels?.clipboard) {
                root.clipboardShortcutActive = false;
                return;
            }
            if (root.visibilities.clipboard) {
                const inClip = root.inBottomPanel(root.panels.clipboard, root.mouseX, root.mouseY, true);
                root.clipboardShortcutActive = !inClip;
            } else {
                root.clipboardShortcutActive = false;
            }
        }

        target: root.visibilities
    }
}
