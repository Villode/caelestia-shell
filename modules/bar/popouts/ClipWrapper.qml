pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.modules.bar.popouts // Need to import this module so the Wrapper type is the same as others

Item {
    id: root

    required property ShellScreen screen
    required property real borderThickness

    readonly property alias content: content
    readonly property string barPosition: {
        const value = String(Config.bar.position || "left").toLowerCase();
        if (value === "right" || value === "top")
            return value;
        return "left";
    }
    readonly property bool barIsTop: barPosition === "top"
    readonly property bool barIsRight: barPosition === "right"
    readonly property bool barIsLeft: barPosition === "left"
    // Right bar: same motion language as the top dashboard — slide from the edge + fade.
    readonly property bool useEdgeSlide: barIsRight && !content.isDetached

    // 0 = open, 1 = closed (same driver as dashboard / sidebar).
    property real offsetScale: content.hasCurrent || content.isDetached ? 0 : 1
    readonly property real open: 1 - offsetScale
    readonly property bool midTransition: open > 0.01 && open < 0.99
    readonly property bool fullyClosed: open <= 0.01 && !content.hasCurrent && !content.isDetached

    // Keep last real size so close / next open still have a box (content unloads while closing).
    // Prefer cache while opening so the first frames already slide a full-size panel
    // (dashboard keeps a stable box; a 0→full size jump makes the motion feel rushed).
    property real lockedW: 0
    property real lockedH: 0
    property real cacheW: 320
    property real cacheH: 280

    readonly property real liveW: content.nonAnimWidth
    readonly property real liveH: content.nonAnimHeight
    readonly property real contentW: {
        if (!useEdgeSlide)
            return liveW;
        // While closed or mid-open with no live size yet, hold a stable box.
        if (liveW > 1 && (content.hasCurrent || content.isDetached || midTransition))
            return liveW;
        if (lockedW > 1)
            return lockedW;
        return cacheW;
    }
    readonly property real contentH: {
        if (!useEdgeSlide)
            return liveH;
        if (liveH > 1 && (content.hasCurrent || content.isDetached || midTransition))
            return liveH;
        if (lockedH > 1)
            return lockedH;
        return cacheH;
    }

    visible: {
        if (content.isDetached)
            return true;
        if (useEdgeSlide)
            return !fullyClosed;
        return width > 0.5 && height > 0.5;
    }
    // Left/top still wipe through a clip host; right slides like the dashboard (no clip wipe).
    clip: !useEdgeSlide

    implicitWidth: {
        if (content.isDetached || useEdgeSlide || barIsTop)
            return contentW;
        return Math.max(1, contentW * open);
    }
    implicitHeight: {
        if (content.isDetached || useEdgeSlide)
            return contentH;
        if (barIsTop)
            return Math.max(1, contentH * open);
        return contentH;
    }

    // Dashboard-style fade on the same offsetScale driver.
    opacity: useEdgeSlide ? open : 1

    x: {
        if (content.isDetached)
            return (parent.width - contentW) / 2;

        if (barIsTop) {
            const off = content.currentCenter - borderThickness - contentW / 2;
            const maxX = Math.max(0, parent.width - contentW);
            return Math.min(Math.max(off, 0), maxX);
        }

        if (barIsRight) {
            // Mirror dashboard's topMargin slide: fully off-edge when closed, docked when open.
            // dashboard: topMargin = (-height - 5) * offsetScale
            // right bar: x = dockedX + (width + 5) * offsetScale
            const docked = parent.width - contentW;
            return docked + (contentW + 5) * offsetScale;
        }

        return 0;
    }
    y: {
        if (content.isDetached)
            return (parent.height - contentH) / 2;

        if (barIsTop)
            return 0;

        const off = content.currentCenter - borderThickness - contentH / 2;
        const maxY = Math.max(0, parent.height - contentH);
        return Math.min(Math.max(off, 0), maxY);
    }

    onFullyClosedChanged: {
        if (fullyClosed) {
            lockedW = 0;
            lockedH = 0;
        }
    }

    function rememberSize(): void {
        if (liveW > 0) {
            lockedW = liveW;
            cacheW = liveW;
        }
        if (liveH > 0) {
            lockedH = liveH;
            cacheH = liveH;
        }
    }

    Connections {
        target: content
        function onHasCurrentChanged(): void {
            if (content.hasCurrent || content.isDetached)
                root.rememberSize();
        }
        function onIsDetachedChanged(): void {
            if (content.isDetached)
                root.rememberSize();
        }
    }

    onLiveWChanged: {
        if ((content.hasCurrent || content.isDetached) && liveW > 0)
            rememberSize();
    }
    onLiveHChanged: {
        if ((content.hasCurrent || content.isDetached) && liveH > 0)
            rememberSize();
    }

    // Same default Anim as dashboard / sidebar (DefaultSpatial ~500ms, expressive curve).
    // Do NOT also Behavior on x/opacity for edge-slide — those are pure functions of
    // offsetScale, so a second Behavior shortens/fights the motion.
    Behavior on offsetScale {
        Anim {}
    }

    Behavior on x {
        enabled: !root.useEdgeSlide
        Anim {
            duration: content.animLength
            easing: content.animCurve
        }
    }

    Behavior on y {
        enabled: !root.useEdgeSlide && root.offsetScale < 1
        Anim {
            duration: content.animLength
            easing: content.animCurve
        }
    }

    Wrapper {
        id: content

        screen: root.screen
        offsetScale: root.offsetScale
        edgeSlide: root.useEdgeSlide

        width: root.contentW
        height: root.contentH
        x: {
            if (root.useEdgeSlide || root.content.isDetached)
                return 0;
            if (root.barIsTop)
                return (root.width - width) / 2;
            // Left bar wipe: content sits just outside the growing clip.
            return -(width + 5) * root.offsetScale;
        }
        y: {
            if (root.useEdgeSlide || root.content.isDetached)
                return 0;
            if (root.barIsTop)
                return -(height + 5) * root.offsetScale;
            return (root.height - height) / 2;
        }
    }
}
