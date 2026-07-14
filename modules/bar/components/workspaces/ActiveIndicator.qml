pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services

StyledRect {
    id: root

    required property int activeWsId
    required property Repeater workspaces
    required property Item mask
    required property bool fullscreen

    readonly property bool isVertical: String(Config.bar.position || "left").toLowerCase() !== "top"

    readonly property int currentWsIdx: {
        let i = activeWsId - 1;
        while (i < 0)
            i += Config.bar.workspaces.shown;
        return i % Config.bar.workspaces.shown;
    }

    property real leading: {
        if (workspaces.count <= 0)
            return 0;
        const item = workspaces.itemAt(currentWsIdx);
        return root.isVertical ? (item?.y ?? 0) : (item?.x ?? 0);
    }
    property real trailing: {
        if (workspaces.count <= 0)
            return 0;
        const item = workspaces.itemAt(currentWsIdx);
        return root.isVertical ? (item?.y ?? 0) : (item?.x ?? 0);
    }
    property real currentSize: workspaces.count > 0 ? (workspaces.itemAt(currentWsIdx) as Workspace)?.size ?? 0 : 0
    property real offset: Math.min(leading, trailing)
    property real size: {
        const s = Math.abs(leading - trailing) + currentSize;
        if (Config.bar.workspaces.activeTrail && lastWs > currentWsIdx) {
            const ws = workspaces.itemAt(lastWs) as Workspace;
            if (!ws)
                return 0;
            return root.isVertical ? Math.min(ws.y + ws.size - offset, s) : Math.min(ws.x + ws.size - offset, s);
        }
        return s;
    }

    property int cWs
    property int lastWs

    onCurrentWsIdxChanged: {
        lastWs = cWs;
        cWs = currentWsIdx;
    }

    clip: true
    x: root.isVertical ? 0 : (offset + mask.x)
    y: root.isVertical ? (offset + mask.y) : 0
    implicitWidth: root.isVertical ? (Tokens.sizes.bar.innerWidth - Tokens.padding.small) : size
    implicitHeight: root.isVertical ? size : (Tokens.sizes.bar.innerWidth - Tokens.padding.small)
    radius: Tokens.rounding.full
    color: Colours.palette.m3primary

    Colouriser {
        source: root.mask
        sourceColor: Colours.palette.m3onSurface
        colorizationColor: Colours.palette.m3onPrimary

        x: root.isVertical ? 0 : -parent.offset
        y: root.isVertical ? -parent.offset : 0
        implicitWidth: root.mask.implicitWidth
        implicitHeight: root.mask.implicitHeight

        anchors.horizontalCenter: root.isVertical ? parent.horizontalCenter : undefined
        anchors.verticalCenter: root.isVertical ? undefined : parent.verticalCenter
    }

    Behavior on leading {
        enabled: root.Config.bar.workspaces.activeTrail

        EAnim {}
    }

    Behavior on trailing {
        enabled: root.Config.bar.workspaces.activeTrail

        EAnim {
            duration: Tokens.anim.durations.normal * 2
        }
    }

    Behavior on currentSize {
        enabled: root.Config.bar.workspaces.activeTrail

        EAnim {}
    }

    Behavior on offset {
        enabled: !root.Config.bar.workspaces.activeTrail

        EAnim {}
    }

    Behavior on size {
        enabled: !root.Config.bar.workspaces.activeTrail

        EAnim {}
    }

    component EAnim: Anim {
        type: Anim.Emphasized
    }
}
