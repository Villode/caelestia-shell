pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.utils
import qs.modules.bar.popouts as BarPopouts

Item {
    id: root

    required property ShellScreen screen
    required property DrawerVisibilities visibilities
    required property BarPopouts.Wrapper popouts
    required property bool fullscreen

    readonly property bool disabled: Strings.testRegexList(Config.bar.excludedScreens, screen.name)
    readonly property string position: {
        const value = String(Config.bar.position || "left").toLowerCase();
        if (value === "right" || value === "top")
            return value;
        return "left";
    }
    readonly property bool isVertical: position !== "top"
    readonly property bool isLeft: position === "left"
    readonly property bool isRight: position === "right"
    readonly property bool isTop: position === "top"

    readonly property int padding: Math.max(Tokens.padding.small, Config.border.thickness)
    readonly property int contentThickness: Tokens.sizes.bar.innerWidth + padding * 2
    readonly property int clampedThickness: Math.max(Config.border.minThickness, isVertical ? implicitWidth : implicitHeight)
    readonly property int exclusiveZone: !disabled && (Config.bar.persistent || visibilities.bar) ? contentThickness : Config.border.thickness
    readonly property bool shouldBeVisible: !fullscreen && !disabled && (Config.bar.persistent || visibilities.bar || isHovered)
    property bool isHovered

    // Compatibility aliases used by existing drawers code.
    readonly property int contentWidth: contentThickness
    readonly property int clampedWidth: isVertical ? clampedThickness : Config.border.minThickness
    readonly property int clampedHeight: isVertical ? Config.border.minThickness : clampedThickness
    readonly property int exclusiveWidth: isVertical ? exclusiveZone : Config.border.thickness
    readonly property int exclusiveHeight: isVertical ? Config.border.thickness : exclusiveZone

    function closeTray(): void {
        (content.item as Bar)?.closeTray();
    }

    function checkPopout(pos: real): void {
        (content.item as Bar)?.checkPopout(pos);
    }

    function handleWheel(pos: real, angleDelta: point): void {
        (content.item as Bar)?.handleWheel(pos, angleDelta);
    }

    // Thickness along the bar axis (animated). Extent along the screen edge is always full.
    property real shownThickness: shouldBeVisible ? contentThickness : Config.border.thickness

    clip: true
    visible: shownThickness > Config.border.thickness || shouldBeVisible
    // Size is driven by ContentWindow geometry bindings; keep implicit sizes for exclusions.
    implicitWidth: fullscreen ? 0 : (isVertical ? shownThickness : (parent ? parent.width : 0))
    implicitHeight: fullscreen ? 0 : (isVertical ? (parent ? parent.height : 0) : shownThickness)

    Behavior on shownThickness {
        Anim {
            type: root.shouldBeVisible ? Anim.DefaultSpatial : Anim.Emphasized
        }
    }

    // Rebuild bar content when edge/orientation changes so GridLayout and anchors re-init.
    onPositionChanged: content.reload()

    Loader {
        id: content

        // Explicit geometry — conditional anchors do not clear at runtime in Qt Quick.
        // Top bar: pin content to y=0 (screen top). Bottom-pinning during thickness
        // animation left a hollow / sunken strip in the middle of the top edge.
        x: root.isLeft ? Math.max(0, root.width - root.contentThickness) : 0
        y: 0
        width: root.isVertical ? root.contentThickness : root.width
        height: root.isVertical ? root.height : root.contentThickness
        active: root.shouldBeVisible

        function reload(): void {
            const wasActive = active;
            active = false;
            active = wasActive && root.shouldBeVisible;
        }

        sourceComponent: Bar {
            width: content.width
            height: content.height
            screen: root.screen
            visibilities: root.visibilities
            popouts: root.popouts // qmllint disable incompatible-type
            fullscreen: root.fullscreen
            position: root.position
            isVertical: root.isVertical
        }
    }
}
