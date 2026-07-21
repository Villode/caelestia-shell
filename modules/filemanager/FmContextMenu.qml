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
    property bool showCompressFormats: false
    property real requestX: 0
    property real requestY: 0

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
        showCompressFormats = false;
        if (path && root.state.selection.indexOf(path) < 0)
            root.state.setSelection([path]);

        const items = menuItems();
        const estH = items.length * 38 + Tokens.padding.small * 2 + 4;
        const estW = 240;
        panel.x = clampX(x, estW);
        panel.y = clampY(y, estH);
        expanded = true;
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
    }

    function close(): void {
        expanded = false;
        showCompressFormats = false;
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
            { id: "open", label: qsTr("打开") },
            { id: "copy", label: qsTr("复制") },
            { id: "cut", label: qsTr("剪切") },
            { id: "paste", label: qsTr("粘贴") },
            { id: "rename", label: qsTr("重命名") },
            { id: "mkdir", label: qsTr("新建文件夹") }
        ];
        if (anchorIsDir && anchorPath.length) {
            if (root.state.isFavorite(anchorPath))
                items.push({ id: "unpin", label: qsTr("取消侧栏固定") });
            else
                items.push({ id: "pin", label: qsTr("固定到侧栏") });
        }

        if (hasTargets()) {
            if (showCompressFormats) {
                items.push({ id: "compress-back", label: qsTr("‹ 压缩格式") });
                items.push({ id: "compress:zip", label: qsTr("  ZIP (.zip)") });
                items.push({ id: "compress:7z", label: qsTr("  7z (.7z)") });
                items.push({ id: "compress:tar.gz", label: qsTr("  tar.gz") });
                items.push({ id: "compress:tar.xz", label: qsTr("  tar.xz") });
                items.push({ id: "compress:tar.zst", label: qsTr("  tar.zst") });
            } else {
                items.push({ id: "compress-menu", label: qsTr("压缩为…") });
            }
        }

        if (canExtract()) {
            items.push({ id: "extract-here", label: qsTr("解压到此处") });
            items.push({ id: "extract-folder", label: qsTr("解压到新文件夹") });
        }

        if (root.state.isTrash()) {
            if (hasTargets())
                items.push({ id: "delete", label: qsTr("永久删除") });
            items.push({ id: "empty-trash", label: qsTr("清空回收站") });
        } else {
            items.push({ id: "trash", label: qsTr("移到回收站") });
            if (hasTargets())
                items.push({ id: "delete", label: qsTr("永久删除") });
        }
        items.push({ id: "props", label: qsTr("属性") });
        return items;
    }

    onWidthChanged: if (expanded)
        reposition()
    onHeightChanged: if (expanded)
        reposition()

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        onClicked: mouse => {
            const local = mapToItem(panel, mouse.x, mouse.y);
            if (local.x < 0 || local.y < 0 || local.x > panel.width || local.y > panel.height)
                root.close();
            else
                mouse.accepted = false;
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

        onImplicitHeightChanged: if (root.expanded)
            root.reposition()

        ColumnLayout {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.small
            spacing: 2

            Repeater {
                model: root.expanded ? root.menuItems() : []

                StyledRect {
                    id: row
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 36
                    radius: Tokens.rounding.medium
                    color: "transparent"

                    StateLayer {
                        color: Colours.palette.m3onSurface
                        onClicked: {
                            const id = row.modelData.id;
                            const t = root.targets();
                            if (id === "compress-menu") {
                                root.showCompressFormats = true;
                                Qt.callLater(root.reposition);
                                return;
                            }
                            if (id === "compress-back") {
                                root.showCompressFormats = false;
                                Qt.callLater(root.reposition);
                                return;
                            }
                            if (id.startsWith("compress:")) {
                                const fmt = id.slice("compress:".length);
                                root.actions.compress(t, fmt);
                                root.close();
                                return;
                            }
                            if (id === "extract-here") {
                                root.actions.extract(t, "here");
                                root.close();
                                return;
                            }
                            if (id === "extract-folder") {
                                root.actions.extract(t, "folder");
                                root.close();
                                return;
                            }
                            if (id === "open") {
                                if (root.anchorIsDir && root.anchorName)
                                    root.actions.openEntry(true, root.anchorName, root.anchorPath);
                                else
                                    root.actions.openPaths(t);
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
                    }

                    StyledText {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Tokens.padding.medium
                        text: row.modelData.label
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.body.small
                    }
                }
            }
        }
    }
}
