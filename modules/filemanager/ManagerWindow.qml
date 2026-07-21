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
                nActions.mkdir();
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
                    visible: !nState.isThisPC
                }

                Item {
                    id: contentHost
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    FmThisPC {
                        id: thisPc
                        anchors.fill: parent
                        visible: nState.isThisPC
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
                        visible: !nState.isThisPC
                        state: nState
                        actions: nActions
                        onContextMenuRequested: (x, y, path, isDir, name) => {
                            // Map into full-window chrome so menu can use status bar space and not clip
                            const p = folder.mapToItem(chrome, x, y);
                            ctx.openAt(p.x, p.y, path, isDir, name);
                        }
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
