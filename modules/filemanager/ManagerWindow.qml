pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

FloatingWindow {
    id: root

    property alias state: nState
    property alias actions: nActions

    signal requestClose

    color: Colours.tPalette.m3surface
    surfaceFormat.opaque: false
    title: qsTr("文件")
    implicitWidth: 1000
    implicitHeight: 640
    minimumSize.width: 480
    minimumSize.height: 360

    onVisibleChanged: {
        if (!visible)
            requestClose();
    }

    ManagerState {
        id: nState
        onSettingsChanged: settingsView.setText(nState.settingsJson())
    }

    FmActions {
        id: nActions
        state: nState
        showProperties: path => props.openFor(path)
        jobUi: jobOverlay
        confirmUi: confirmDlg
        nameUi: nameDlg
    }

    FmDevices {
        id: nDevices
        onMountFinished: (ok, message, path) => {
            mountDlg.busy = false;
            if (ok) {
                mountDlg.close();
                nState.statusText = message || qsTr("挂载成功");
                if (path)
                    nState.openAbsolutePath(path);
            } else if (String(message).startsWith("need-auth:")) {
                const detail = String(message).slice("need-auth:".length);
                mountDlg.openFor(nDevices.pendingDevice, nDevices.pendingName, detail);
            } else {
                nState.statusText = message || qsTr("挂载失败");
                if (mountDlg.expanded)
                    mountDlg.detail = message || qsTr("挂载失败或已取消");
            }
        }
    }

    FileView {
        id: settingsView
        printErrors: false
        path: `${Paths.state}/filemanager.json`
        onLoaded: {
            try {
                nState.applySettings(JSON.parse(text()));
            } catch (e) {}
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => setText(nState.settingsJson()));
        }
    }

    Item {
        id: chrome
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                if (sortOverlay.visible) {
                    sortOverlay.close();
                    event.accepted = true;
                    return;
                }
                if (toolbar.searchExpanded) {
                    toolbar.collapseSearch(true);
                    event.accepted = true;
                    return;
                }
                if (nameDlg.expanded) {
                    nameDlg.close();
                    event.accepted = true;
                    return;
                }
                if (quickLook.expanded) {
                    quickLook.close();
                    event.accepted = true;
                    return;
                }
                if (jobOverlay.expanded) {
                    event.accepted = true;
                    return;
                }
                if (confirmDlg.expanded) {
                    confirmDlg.close();
                    event.accepted = true;
                    return;
                }
                if (mountDlg.expanded) {
                    mountDlg.close();
                    event.accepted = true;
                    return;
                }
                if (props.expanded) {
                    props.close();
                    event.accepted = true;
                    return;
                }
                if (ctx.expanded) {
                    ctx.close();
                    event.accepted = true;
                    return;
                }
            }
            if (event.key === Qt.Key_F5) {
                nState.bumpRefresh();
                nState.statusText = qsTr("已刷新");
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_F2) {
                let path = nState.selection.length === 1 ? nState.selection[0] : "";
                if (!path && folder.visible)
                    path = folder.currentPath();
                if (path)
                    nActions.requestRename(path);
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Delete) {
                const paths = nState.selection;
                if (paths.length) {
                    if (event.modifiers & Qt.ShiftModifier)
                        nActions.requestDelete(paths);
                    else
                        nActions.requestTrash(paths);
                    event.accepted = true;
                    return;
                }
            }
            if (event.key === Qt.Key_Space && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                if (quickLook.expanded) {
                    quickLook.close();
                    event.accepted = true;
                    return;
                }
                let meta = null;
                if (folder.visible && typeof folder.currentMeta === "function")
                    meta = folder.currentMeta();
                if (!meta || !meta.path) {
                    if (nState.selection.length === 1) {
                        const p = nState.selection[0];
                        meta = {
                            path: p,
                            name: p.split("/").pop() || p,
                            isDir: false,
                            isImage: false
                        };
                    }
                }
                if (meta && meta.path)
                    quickLook.toggle(meta.path, meta.name, meta.isDir, meta.isImage);
                event.accepted = true;
                return;
            }
            if (!(event.modifiers & Qt.ControlModifier))
                return;
            if (event.key === Qt.Key_C) {
                nActions.copy(nState.selection);
                event.accepted = true;
            } else if (event.key === Qt.Key_X) {
                nActions.cut(nState.selection);
                event.accepted = true;
            } else if (event.key === Qt.Key_V) {
                nActions.paste();
                event.accepted = true;
            } else if ((event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_N) {
                nActions.requestMkdir();
                event.accepted = true;
            } else if (event.key === Qt.Key_N) {
                // New file manager window at same path
                Quickshell.execDetached(["qs", "-c", "caelestia", "ipc", "call", "filemanager", "openNew", nState.cwdPath()]);
                event.accepted = true;
            } else if (event.key === Qt.Key_H) {
                nState.toggleShowHidden();
                event.accepted = true;
            } else if (event.key === Qt.Key_F) {
                if (toolbar.visible)
                    toolbar.focusSearch();
                event.accepted = true;
            } else if (event.key === Qt.Key_1) {
                nState.setViewMode("grid");
                event.accepted = true;
            } else if (event.key === Qt.Key_2) {
                nState.setViewMode("list");
                event.accepted = true;
            }
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            FmSidebar {
                Layout.fillHeight: true
                state: nState
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                FmHeader {
                    Layout.fillWidth: true
                    state: nState
                }

                FmToolbar {
                    id: toolbar
                    Layout.fillWidth: true
                    state: nState
                    actions: nActions
                    visible: !nState.isThisPC || nState.searchScope === "global"
                    sortMenuOpen: sortOverlay.visible
                    onSortMenuOpenRequested: (x, y) => {
                        // x,y are bottom-right of sort button in toolbar coords
                        const p = toolbar.mapToItem(chrome, x, y);
                        sortOverlay.openAt(p.x, p.y);
                    }
                    onSortMenuCloseRequested: sortOverlay.close()
                }

                Item {
                    id: contentHost
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    FmThisPC {
                        id: thisPc
                        anchors.fill: parent
                        visible: nState.isThisPC && nState.searchScope !== "global"
                        state: nState
                        devices: nDevices
                        onOpenDevice: device => {
                            if (device?.path)
                                nState.openAbsolutePath(device.path);
                        }
                        onRequestMount: device => {
                            if (!device)
                                return;
                            // Block: device=/dev/...; Phone MTP: uri=mtp://...
                            if (!device.device && !device.uri)
                                return;
                            nState.statusText = qsTr("尝试挂载 %1…").arg(device.name || "");
                            nDevices.mountDevice(device.device || "", device.name || "", device.uri || "");
                        }
                    }

                    FmFolderView {
                        id: folder
                        anchors.fill: parent
                        visible: !nState.isThisPC && nState.searchScope !== "global"
                        state: nState
                        actions: nActions
                        onContextMenuRequested: (x, y, path, isDir, name) => {
                            const p = folder.mapToItem(chrome, x, y);
                            ctx.openAt(p.x, p.y, path, isDir, name);
                        }
                    }

                    FmSearchResults {
                        id: globalSearch
                        anchors.fill: parent
                        visible: nState.searchScope === "global"
                        state: nState
                        actions: nActions
                    }
                }

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: statusRow.implicitHeight + Tokens.padding.small * 2
                    color: Colours.tPalette.m3surfaceContainer

                    RowLayout {
                        id: statusRow
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        spacing: Tokens.spacing.medium

                        StyledText {
                            Layout.fillWidth: true
                            text: nState.statusText
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.builders.small.build()
                            elide: Text.ElideMiddle
                        }

                        StyledText {
                            visible: nState.clipboardMode === "cut" && nState.clipboardPaths.length > 0
                            text: qsTr("剪切板 · 移走 %1").arg(nState.clipboardPaths.length)
                            color: Colours.palette.m3tertiary
                            font: Tokens.font.body.builders.small.weight(Font.Bold).build()
                        }
                        StyledText {
                            visible: nState.clipboardMode === "copy" && nState.clipboardPaths.length > 0
                            text: qsTr("剪切板 · 复制 %1").arg(nState.clipboardPaths.length)
                            color: Colours.palette.m3primary
                            font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                        }
                    }
                }
            }
        }

        FmContextMenu {
            id: ctx
            anchors.fill: parent
            z: 15000
            state: nState
            actions: nActions
        }

        // Sort menu above folder view (opaque, not clipped by toolbar)
        Item {
            id: sortOverlay
            anchors.fill: parent
            z: 16000
            visible: false

            function openAt(anchorRightX: real, anchorTopY: real): void {
                // Align menu's right edge to anchorRightX, top to anchorTopY
                const mw = sortPanel.implicitWidth;
                const mh = sortPanel.implicitHeight;
                let x = anchorRightX - mw;
                let y = anchorTopY;
                x = Math.max(8, Math.min(x, width - mw - 8));
                y = Math.max(8, Math.min(y, height - mh - 8));
                sortPanel.x = x;
                sortPanel.y = y;
                visible = true;
            }

            function close(): void {
                visible = false;
            }

            // Dim/click-away catcher (opaque enough to block list interaction)
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: sortOverlay.close()
                onWheel: wheel => {
                    sortOverlay.close();
                    wheel.accepted = false;
                }
            }

            StyledRect {
                id: sortPanel
                // Solid surface (not translucent palette) so list never shows through
                color: Colours.palette.m3surfaceContainerHigh
                radius: Tokens.rounding.large
                border.width: 1
                border.color: Colours.palette.m3outlineVariant
                implicitWidth: sortCol.implicitWidth + Tokens.padding.small * 2
                implicitHeight: sortCol.implicitHeight + Tokens.padding.small * 2
                // Elevate
                z: 1

                // Block clicks through to dismiss layer when using menu
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: {} // swallow
                }

                ColumnLayout {
                    id: sortCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Tokens.padding.small
                    spacing: 2

                    SortMenuRow {
                        label: qsTr("名称")
                        sortKey: "name"
                    }
                    SortMenuRow {
                        label: qsTr("大小")
                        sortKey: "size"
                    }
                    SortMenuRow {
                        label: qsTr("类型")
                        sortKey: "type"
                    }
                    SortMenuRow {
                        label: qsTr("修改时间")
                        sortKey: "mtime"
                    }

                    StyledRect {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        Layout.topMargin: 4
                        Layout.bottomMargin: 4
                        color: Colours.palette.m3outlineVariant
                    }

                    SortMenuRow {
                        label: nState.sortReverse ? qsTr("升序") : qsTr("降序")
                        sortKey: "__dir__"
                        iconName: nState.sortReverse ? "arrow_upward" : "arrow_downward"
                    }
                    SortMenuRow {
                        label: qsTr("文件夹优先")
                        sortKey: "__folders__"
                        checkable: true
                        checked: nState.foldersFirst
                    }
                }
            }

            component SortMenuRow: Item {
                id: srow
                property string label
                property string sortKey
                property string iconName: ""
                property bool checkable: false
                property bool checked: false

                Layout.fillWidth: true
                implicitHeight: 34
                implicitWidth: Math.max(180, rowInner.implicitWidth + Tokens.padding.medium * 2)

                readonly property bool activeKey: !checkable && sortKey !== "__dir__" && nState.sortBy === sortKey

                StyledRect {
                    anchors.fill: parent
                    radius: Tokens.rounding.medium
                    color: srow.activeKey ? Colours.palette.m3secondaryContainer : "transparent"

                    StateLayer {
                        color: srow.activeKey ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                        onClicked: {
                            if (srow.sortKey === "__dir__")
                                nState.toggleSortReverse();
                            else if (srow.sortKey === "__folders__")
                                nState.toggleFoldersFirst();
                            else
                                nState.setSortBy(srow.sortKey);
                            // keep open for multi-tweak
                        }
                    }

                    RowLayout {
                        id: rowInner
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.small
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            visible: srow.iconName.length > 0
                            text: srow.iconName
                            color: srow.activeKey ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                            fontStyle: Tokens.font.icon.small
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: srow.label
                            color: srow.activeKey ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                            font: Tokens.font.body.builders.small.weight(srow.activeKey ? Font.Bold : Font.Normal).build()
                        }

                        MaterialIcon {
                            visible: srow.activeKey || (srow.checkable && srow.checked)
                            text: srow.checkable ? "check" : (nState.sortReverse ? "arrow_downward" : "arrow_upward")
                            color: srow.activeKey ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3primary
                            fontStyle: Tokens.font.icon.small
                        }
                    }
                }
            }
        }

        FmProperties {
            id: props
            anchors.fill: parent
        }

        FmMountDialog {
            id: mountDlg
            anchors.fill: parent
            onCancelled: {
                close();
                nState.statusText = qsTr("已取消挂载");
            }
            onConfirmed: (device, name) => {
                // pkexec will show system password dialog
                nDevices.mountWithPassword(device, name, "");
            }
        }

        FmConfirmDialog {
            id: confirmDlg
            anchors.fill: parent
            onAccepted: (paths, mode) => {
                if (mode === "empty-trash")
                    nActions.emptyTrash();
                else if (mode === "delete")
                    nActions.deletePermanent(paths);
                else
                    nActions.trash(paths);
            }
        }

        FmNameDialog {
            id: nameDlg
            anchors.fill: parent
            onAccepted: (mode, sourcePath, name) => {
                if (mode === "rename")
                    nActions.rename(sourcePath, name);
                else if (mode === "mkdir")
                    nActions.mkdir(name);
            }
        }

        FmJobOverlay {
            id: jobOverlay
            anchors.fill: parent
        }

        FmQuickLook {
            id: quickLook
            anchors.fill: parent
        }
    }

    Behavior on color {
        CAnim {}
    }

    function openPath(path: string): void {
        if (!path)
            nState.navigateToThisPC();
        else
            nState.openAbsolutePath(path);
        visible = true;
    }
}
