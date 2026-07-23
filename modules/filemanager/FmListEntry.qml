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
    id: row

    required property var host
    required property int index
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
    readonly property bool isCut: !!(modelData && host.state.clipboardMode === "cut" && host.state.clipboardPaths.indexOf(modelData.path) >= 0)

    width: ListView.view ? ListView.view.width : 200
    implicitHeight: 40
    radius: Tokens.rounding.medium
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
    color: isDropTarget
        ? "transparent"
        : Qt.alpha(Colours.tPalette.m3surfaceContainerHighest, (ListView.isCurrentItem || isSelected) ? Colours.tPalette.m3surfaceContainerHighest.a : 0)
    border.width: isDropTarget ? 2 : 0
    border.color: isDropTarget ? Colours.palette.m3primary : "transparent"

    Behavior on opacity {
        Anim { type: Anim.DefaultEffects }
    }

    StateLayer {
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        spacing: Tokens.spacing.medium

        CachingIconImage {
            implicitSize: 24
            source: {
                const d = row.modelData;
                if (!d || !d.path)
                    return "";
                if (d.isImage)
                    return Qt.resolvedUrl(d.path);
                return host.iconFor(d);
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: host.state.displayName({
                path: row.path,
                name: row.name,
                isDir: row.isDir,
                isImage: row.isImage,
                size: row.size,
                mimeType: row.mimeType,
                suffix: row.suffix,
                baseName: row.baseName
            })
            color: Colours.palette.m3onSurface
            font: Tokens.font.body.small
            elide: Text.ElideMiddle
        }

        StyledText {
            visible: row.modelData && !row.modelData.isDir
            Layout.preferredWidth: 72
            horizontalAlignment: Text.AlignRight
            text: row.modelData ? host.humanSize(row.modelData.size) : ""
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.builders.small.scale(0.9).build()
        }

        StyledText {
            visible: !!(row.modelData && row.modelData.isDir)
            Layout.preferredWidth: 72
            horizontalAlignment: Text.AlignRight
            text: qsTr("文件夹")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.builders.small.scale(0.9).build()
        }

        StyledText {
            Layout.preferredWidth: 118
            horizontalAlignment: Text.AlignRight
            text: row.modelData ? (host.mtimeFor(row.modelData.name) || "—") : "—"
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.builders.small.scale(0.9).build()
        }

        StyledText {
            visible: row.isCut
            text: qsTr("剪切")
            color: Colours.palette.m3tertiary
            font: Tokens.font.body.builders.small.weight(Font.Bold).build()
        }
    }
}
