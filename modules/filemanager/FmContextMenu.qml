pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property var state
    required property var actions

    property string anchorPath: ""
    property bool anchorIsDir: false
    property string anchorName: ""
    property bool expanded: false
    // flyout: "" | "sort" | "compress"
    property string flyout: ""
    property int menuEpoch: 0
    property real requestX: 0
    property real requestY: 0
    property real flyoutAnchorY: 0

    anchors.fill: parent
    z: 10000
    visible: expanded
    enabled: expanded

    function openAt(x: real, y: real, path: string, isDir: bool, name: string): void {
        anchorPath = path || "";
        anchorIsDir = !!isDir;
        anchorName = name || "";
        requestX = x;
        requestY = y;
        flyout = "";
        flyoutAnchorY = 0;
        if (path && root.state.selection.indexOf(path) < 0)
            root.state.setSelection([path]);

        const items = menuItems();
        const estH = items.length * 38 + Tokens.padding.small * 2 + 4;
        const estW = 240;
        panel.x = clampX(x, estW);
        panel.y = clampY(y, estH);
        expanded = true;
        menuEpoch = menuEpoch + 1;
        Qt.callLater(reposition);
    }

    function clampX(x: real, w: real): real {
        const margin = 8;
        let px = x;
        if (px + w + margin > width)
            px = Math.max(margin, width - w - margin);
        if (px < margin)
            px = margin;
        return px;
    }

    function clampY(y: real, h: real): real {
        const margin = 8;
        let py = y;
        if (py + h + margin > height) {
            py = y - h;
            if (py < margin)
                py = Math.max(margin, height - h - margin);
        }
        if (py < margin)
            py = margin;
        return py;
    }

    function reposition(): void {
        if (!expanded)
            return;
        const w = Math.max(panel.width, panel.implicitWidth, 200);
        const h = Math.max(panel.height, panel.implicitHeight, 40);
        panel.x = clampX(requestX, w);
        panel.y = clampY(requestY, h);
        placeFlyout();
    }

    function placeFlyout(): void {
        if (!flyout.length)
            return;
        const gap = 4;
        const fw = Math.max(flyPanel.implicitWidth, 180);
        const fh = Math.max(flyPanel.implicitHeight, 40);
        let fx = panel.x + panel.width + gap;
        if (fx + fw + 8 > width)
            fx = panel.x - fw - gap;
        if (fx < 8)
            fx = 8;

        let fy = panel.y + flyoutAnchorY;
        if (fy + fh + 8 > height)
            fy = Math.max(8, height - fh - 8);
        if (fy < 8)
            fy = 8;

        flyPanel.x = fx;
        flyPanel.y = fy;
    }

    function openFlyout(kind: string, rowY: real): void {
        flyout = kind;
        flyoutAnchorY = rowY;
        menuEpoch = menuEpoch + 1;
        Qt.callLater(placeFlyout);
    }

    function close(): void {
        expanded = false;
        flyout = "";
    }

    function targets(): list<string> {
        if (root.state.selection.length)
            return root.state.selection;
        if (anchorPath.length)
            return [anchorPath];
        return [];
    }

    function hasTargets(): bool {
        return targets().length > 0;
    }

    function canExtract(): bool {
        const t = targets();
        return t.length > 0 && root.actions.anyArchive(t);
    }

    function menuItems(): var {
        const items = [
            { id: "open", label: qsTr("打开"), submenu: "" },
            { id: "refresh", label: qsTr("刷新"), submenu: "" },
            { id: "sort-menu", label: qsTr("排序"), submenu: "sort" },
            { id: "copy", label: qsTr("复制"), submenu: "" },
            { id: "cut", label: qsTr("剪切"), submenu: "" },
            { id: "paste", label: qsTr("粘贴"), submenu: "" },
            { id: "rename", label: qsTr("重命名"), submenu: "" },
            { id: "mkdir", label: qsTr("新建文件夹"), submenu: "" }
        ];
        if (anchorIsDir && anchorPath.length) {
            if (root.state.isFavorite(anchorPath))
                items.push({ id: "unpin", label: qsTr("取消侧栏固定"), submenu: "" });
            else
                items.push({ id: "pin", label: qsTr("固定到侧栏"), submenu: "" });
        }

        if (hasTargets())
            items.push({ id: "compress-menu", label: qsTr("压缩为"), submenu: "compress" });

        if (canExtract()) {
            items.push({ id: "extract-here", label: qsTr("解压到此处"), submenu: "" });
            items.push({ id: "extract-folder", label: qsTr("解压到新文件夹"), submenu: "" });
        }

        if (root.state.isTrash()) {
            if (hasTargets())
                items.push({ id: "delete", label: qsTr("永久删除"), submenu: "" });
            items.push({ id: "empty-trash", label: qsTr("清空回收站"), submenu: "" });
        } else {
            items.push({ id: "trash", label: qsTr("移到回收站"), submenu: "" });
            if (hasTargets())
                items.push({ id: "delete", label: qsTr("永久删除"), submenu: "" });
        }
        items.push({ id: "props", label: qsTr("属性"), submenu: "" });
        return items;
    }

    function sortFlyoutItems(): var {
        return [
            { id: "sort-name", label: qsTr("名称"), mark: root.state.sortBy === "name" },
            { id: "sort-size", label: qsTr("大小"), mark: root.state.sortBy === "size" },
            { id: "sort-type", label: qsTr("类型"), mark: root.state.sortBy === "type" },
            { id: "sort-mtime", label: qsTr("修改时间"), mark: root.state.sortBy === "mtime" },
            { id: "sep", label: "", mark: false },
            { id: "sort-dir", label: root.state.sortReverse ? qsTr("升序") : qsTr("降序"), mark: false },
            { id: "sort-folders", label: qsTr("文件夹优先"), mark: root.state.foldersFirst }
        ];
    }

    function compressFlyoutItems(): var {
        return [
            { id: "compress:zip", label: "ZIP (.zip)", mark: false },
            { id: "compress:7z", label: "7z (.7z)", mark: false },
            { id: "compress:tar.gz", label: "tar.gz", mark: false },
            { id: "compress:tar.xz", label: "tar.xz", mark: false },
            { id: "compress:tar.zst", label: "tar.zst", mark: false }
        ];
    }

    function runMainAction(id: string): void {
        const t = root.targets();
        if (id === "open") {
            if (root.anchorIsDir && root.anchorName)
                root.actions.openEntry(true, root.anchorName, root.anchorPath);
            else
                root.actions.openPaths(t);
        } else if (id === "refresh") {
            root.state.bumpRefresh();
            root.state.statusText = qsTr("已刷新");
        } else if (id === "copy") {
            root.actions.copy(t);
        } else if (id === "cut") {
            root.actions.cut(t);
        } else if (id === "paste") {
            root.actions.paste();
        } else if (id === "rename") {
            const p = root.anchorPath || (t.length === 1 ? t[0] : "");
            if (p && typeof root.actions.requestRename === "function")
                root.actions.requestRename(p);
        } else if (id === "mkdir") {
            if (typeof root.actions.requestMkdir === "function")
                root.actions.requestMkdir();
            else
                root.actions.mkdir("");
        } else if (id === "pin") {
            root.state.pinPath(root.anchorPath, root.anchorName);
        } else if (id === "unpin") {
            root.state.unpinPath(root.anchorPath);
        } else if (id === "extract-here") {
            root.actions.extract(t, "here");
        } else if (id === "extract-folder") {
            root.actions.extract(t, "folder");
        } else if (id === "trash") {
            if (typeof root.actions.requestTrash === "function")
                root.actions.requestTrash(t);
            else
                root.actions.trash(t);
        } else if (id === "delete") {
            if (typeof root.actions.requestDelete === "function")
                root.actions.requestDelete(t);
            else
                root.actions.deletePermanent(t);
        } else if (id === "empty-trash") {
            if (typeof root.actions.requestEmptyTrash === "function")
                root.actions.requestEmptyTrash();
            else
                root.actions.emptyTrash();
        } else if (id === "props") {
            root.actions.properties(t[0] || root.state.cwdPath());
        }
        root.close();
    }

    function runFlyoutAction(id: string): void {
        if (id === "sep")
            return;
        if (id === "sort-name") {
            root.state.setSortBy("name");
            return;
        }
        if (id === "sort-size") {
            root.state.setSortBy("size");
            return;
        }
        if (id === "sort-type") {
            root.state.setSortBy("type");
            return;
        }
        if (id === "sort-mtime") {
            root.state.setSortBy("mtime");
            return;
        }
        if (id === "sort-dir") {
            root.state.toggleSortReverse();
            return;
        }
        if (id === "sort-folders") {
            root.state.toggleFoldersFirst();
            return;
        }
        if (id.startsWith("compress:")) {
            const fmt = id.slice("compress:".length);
            root.actions.compress(root.targets(), fmt);
            root.close();
        }
    }

    onWidthChanged: if (expanded)
        reposition()
    onHeightChanged: if (expanded)
        reposition()

    onFlyoutChanged: {
        menuEpoch = menuEpoch + 1;
        if (expanded)
            Qt.callLater(placeFlyout);
    }

    Connections {
        target: root.state
        function onSortByChanged(): void {
            if (root.expanded)
                root.menuEpoch = root.menuEpoch + 1;
        }
        function onSortReverseChanged(): void {
            if (root.expanded)
                root.menuEpoch = root.menuEpoch + 1;
        }
        function onFoldersFirstChanged(): void {
            if (root.expanded)
                root.menuEpoch = root.menuEpoch + 1;
        }
    }

    function pointInItem(item: Item, mx: real, my: real): bool {
        if (!item || !item.visible)
            return false;
        const local = mapToItem(item, mx, my);
        return local.x >= 0 && local.y >= 0 && local.x <= item.width && local.y <= item.height;
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        onClicked: mouse => {
            if (root.pointInItem(panel, mouse.x, mouse.y) || root.pointInItem(flyPanel, mouse.x, mouse.y))
                mouse.accepted = false;
            else
                root.close();
        }
    }

    StyledRect {
        id: panel

        implicitWidth: 240
        implicitHeight: col.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainerHigh
        border.width: 1
        border.color: Colours.palette.m3outlineVariant
        layer.enabled: true
        z: 1

        onImplicitHeightChanged: if (root.expanded)
            root.reposition()
        onXChanged: if (root.expanded)
            root.placeFlyout()
        onYChanged: if (root.expanded)
            root.placeFlyout()

        ColumnLayout {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.small
            spacing: 2

            Repeater {
                model: {
                    const _ = root.menuEpoch;
                    return root.expanded ? root.menuItems() : [];
                }

                StyledRect {
                    id: row
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    implicitHeight: 36
                    radius: Tokens.rounding.medium
                    color: (modelData.submenu && root.flyout === modelData.submenu)
                        ? Colours.palette.m3secondaryContainer
                        : "transparent"

                    StateLayer {
                        color: (row.modelData.submenu && root.flyout === row.modelData.submenu)
                            ? Colours.palette.m3onSecondaryContainer
                            : Colours.palette.m3onSurface
                        onClicked: {
                            const md = row.modelData;
                            if (md.submenu && md.submenu.length) {
                                const rowTop = row.mapToItem(panel, 0, 0).y;
                                if (root.flyout === md.submenu)
                                    root.flyout = "";
                                else
                                    root.openFlyout(md.submenu, rowTop);
                                return;
                            }
                            root.flyout = "";
                            root.runMainAction(md.id);
                        }
                    }

                    StyledText {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.right: chevron.visible ? chevron.left : parent.right
                        anchors.rightMargin: Tokens.padding.small
                        text: row.modelData.label
                        elide: Text.ElideRight
                        color: (row.modelData.submenu && root.flyout === row.modelData.submenu)
                            ? Colours.palette.m3onSecondaryContainer
                            : Colours.palette.m3onSurface
                        font: Tokens.font.body.small
                    }

                    MaterialIcon {
                        id: chevron
                        visible: !!(row.modelData.submenu && row.modelData.submenu.length)
                        anchors.right: parent.right
                        anchors.rightMargin: Tokens.padding.small
                        anchors.verticalCenter: parent.verticalCenter
                        text: "chevron_right"
                        color: (row.modelData.submenu && root.flyout === row.modelData.submenu)
                            ? Colours.palette.m3onSecondaryContainer
                            : Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small
                    }
                }
            }
        }
    }

    StyledRect {
        id: flyPanel

        visible: root.expanded && root.flyout.length > 0
        z: 2
        implicitWidth: Math.max(180, flyCol.implicitWidth + Tokens.padding.small * 2)
        implicitHeight: flyCol.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainerHigh
        border.width: 1
        border.color: Colours.palette.m3outlineVariant
        layer.enabled: true

        onImplicitHeightChanged: if (root.expanded && root.flyout.length)
            root.placeFlyout()
        onImplicitWidthChanged: if (root.expanded && root.flyout.length)
            root.placeFlyout()

        ColumnLayout {
            id: flyCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.small
            spacing: 2

            Repeater {
                model: {
                    const _ = root.menuEpoch;
                    if (!root.expanded || !root.flyout.length)
                        return [];
                    if (root.flyout === "sort")
                        return root.sortFlyoutItems();
                    if (root.flyout === "compress")
                        return root.compressFlyoutItems();
                    return [];
                }

                Item {
                    id: flyRow
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: modelData.id === "sep" ? 9 : 36
                    implicitWidth: 180

                    StyledRect {
                        visible: flyRow.modelData.id === "sep"
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 1
                        color: Colours.palette.m3outlineVariant
                    }

                    StyledRect {
                        visible: flyRow.modelData.id !== "sep"
                        anchors.fill: parent
                        radius: Tokens.rounding.medium
                        color: "transparent"

                        StateLayer {
                            color: Colours.palette.m3onSurface
                            onClicked: root.runFlyoutAction(flyRow.modelData.id)
                        }

                        StyledText {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Tokens.padding.medium
                            anchors.right: markIcon.visible ? markIcon.left : parent.right
                            anchors.rightMargin: Tokens.padding.small
                            text: flyRow.modelData.label
                            elide: Text.ElideRight
                            color: Colours.palette.m3onSurface
                            font: Tokens.font.body.small
                        }

                        MaterialIcon {
                            id: markIcon
                            visible: !!flyRow.modelData.mark
                            anchors.right: parent.right
                            anchors.rightMargin: Tokens.padding.small
                            anchors.verticalCenter: parent.verticalCenter
                            text: "check"
                            color: Colours.palette.m3primary
                            fontStyle: Tokens.font.icon.small
                        }
                    }
                }
            }
        }
    }
}
