pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.components.images
import qs.services
import qs.utils

// Grid tile for FmFolderView — parent provides root via required property
StyledRect {
    id: item

    required property var host
    required property int index
    // ListModel roles — must be required so Qt binds them from the model
    required property string path
    required property string name
    required property bool isDir
    required property bool isImage
    required property var size
    required property string mimeType
    required property string suffix
    required property string baseName

    readonly property var modelData: ({
        path: path,
        name: name,
        isDir: isDir,
        isImage: isImage,
        size: size,
        mimeType: mimeType,
        suffix: suffix,
        baseName: baseName
    })

    readonly property bool isSelected: {
        if (!modelData)
            return false;
        const list = host.dragVisualActive && host.frozenSelection && host.frozenSelection.length
            ? host.frozenSelection
            : host.state.selection;
        return list.indexOf(modelData.path) >= 0;
    }
    readonly property bool isCut: modelData && host.state.clipboardMode === "cut" && host.state.clipboardPaths.indexOf(modelData.path) >= 0
    readonly property real nonAnimHeight: icon.implicitHeight + nameLabel.anchors.topMargin + nameLabel.implicitHeight + Tokens.padding.medium * 2

    // Slightly smaller than cell so adjacent tiles have breathing room
    width: GridView.view ? Math.max(host.minItemWidth, GridView.view.cellWidth - host.gridGap) : host.itemWidth
    implicitWidth: width
    implicitHeight: nonAnimHeight
    radius: Tokens.rounding.large
    opacity: isCut ? 0.42 : 1
    readonly property bool isDropTarget: {
        if (!modelData || !modelData.isDir || !host.dropHoverActive)
            return false;
        // Source: freeze UI — no tile chrome walking under cursor
        if (host.dragVisualActive)
            return false;
        if (!FmDrag.active)
            return false;
        if (FmDrag.pendingWindowId && host.windowId && FmDrag.pendingWindowId !== host.windowId)
            return false;
        return host.dropHoverPath === modelData.path;
    }
    // Drop target = outline only (not selection fill) so it never looks like selection moving
    color: isDropTarget
        ? "transparent"
        : Qt.alpha(Colours.tPalette.m3surfaceContainerHighest, (GridView.isCurrentItem || isSelected) ? Colours.tPalette.m3surfaceContainerHighest.a : 0)
    border.width: isDropTarget ? 2 : 0
    border.color: isDropTarget ? Colours.palette.m3primary : "transparent"
    z: GridView.isCurrentItem || isSelected || isDropTarget || implicitHeight !== nonAnimHeight ? 1 : 0
    clip: true

    Behavior on opacity {
        Anim { type: Anim.DefaultEffects }
    }

    StateLayer {
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
    }

    Rectangle {
        visible: item.isCut
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6
        width: cutBadge.implicitWidth + 10
        height: cutBadge.implicitHeight + 4
        radius: height / 2
        color: Colours.palette.m3tertiary
        z: 2
        StyledText {
            id: cutBadge
            anchors.centerIn: parent
            text: qsTr("剪切")
            color: Colours.palette.m3onTertiary
            font: Tokens.font.body.builders.small.scale(0.85).weight(Font.Bold).build()
        }
    }

    CachingIconImage {
        id: icon
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Tokens.padding.medium
        implicitSize: host.itemWidth - Tokens.padding.medium * 2
        opacity: item.isCut ? 0.85 : 1
        // Reactive: roles change when delegate is recycled
        source: {
            const d = item.modelData;
            if (!d || !d.path)
                return "";
            if (d.isImage)
                return Qt.resolvedUrl(d.path);
            return host.iconFor(d);
        }
    }

    StyledText {
        id: nameLabel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: icon.bottom
        anchors.topMargin: Tokens.spacing.small
        anchors.margins: Tokens.padding.medium
        horizontalAlignment: Text.AlignHCenter
        text: {
            // Prefer role properties (avoid id shadowing of "name")
            const d = {
                path: item.path,
                name: item.name,
                isDir: item.isDir,
                isImage: item.isImage,
                size: item.size,
                mimeType: item.mimeType,
                suffix: item.suffix,
                baseName: item.baseName
            };
            return host.state.displayName(d);
        }
        // Keep tile height stable: always elide; at most 2 lines when focused/selected
        wrapMode: (item.GridView.isCurrentItem || item.isSelected) ? Text.WrapAtWordBoundaryOrAnywhere : Text.NoWrap
        maximumLineCount: (item.GridView.isCurrentItem || item.isSelected) ? 2 : 1
        elide: Text.ElideRight
    }

    Behavior on implicitHeight {
        Anim {}
    }
}
