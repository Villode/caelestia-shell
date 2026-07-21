pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

// Portal Open/Save picker — same chrome as QML file manager (sidebar/header/toolbar/grid).
Scope {
    id: root

    property var win: null

    function openPicker(opts: var): void {
        if (win) {
            try {
                win.visible = false;
                win.destroy();
            } catch (e) {}
            win = null;
        }
        win = pickerComp.createObject(root, {
            mode: opts.mode || "open",
            dialogTitle: opts.title || qsTr("选择文件"),
            resultFile: opts.resultFile || "",
            filterLabel: opts.filterLabel || qsTr("所有文件"),
            filters: opts.filters || ["*"],
            startDir: opts.startDir || "",
            suggestedName: opts.suggestedName || "",
            multiple: !!opts.multiple,
            acceptDirectories: !!opts.acceptDirectories
        });
        if (win) {
            win.pickerClosed.connect(() => {
                win = null;
            });
            win.visible = true;
        }
    }

    Component {
        id: pickerComp
        FloatingWindow {
            id: dlg

            property string mode: "open" // open | save | folder
            property string dialogTitle: qsTr("选择文件")
            property string resultFile: ""
            property string filterLabel: qsTr("所有文件")
            property list<string> filters: ["*"]
            property string startDir: ""
            property string suggestedName: ""
            property bool multiple: false
            property bool acceptDirectories: false
            property bool done: false

            signal pickerClosed

            readonly property bool selectionValid: {
                if (mode === "save") {
                    const name = (nameField.text || "").trim();
                    return name.length > 0 && !name.includes("/");
                }
                if (acceptDirectories || mode === "folder")
                    return !nState.isThisPC && nState.cwdPath().length > 0;
                // open file(s)
                const sel = nState.selection || [];
                if (!sel.length)
                    return false;
                if (multiple)
                    return true;
                return sel.length >= 1;
            }

            function writeResult(uris: var, cancelled: bool): void {
                if (done)
                    return;
                done = true;
                if (!resultFile || !resultFile.length) {
                    visible = false;
                    pickerClosed();
                    return;
                }
                let body = "";
                if (!cancelled && uris && uris.length) {
                    for (let i = 0; i < uris.length; i++)
                        body += uris[i] + "\n";
                }
                const content = (cancelled ? "CANCEL\n" : "OK\n") + body;
                Quickshell.execDetached([
                    "python3", "-c",
                    "import sys; open(sys.argv[1],'w',encoding='utf-8').write(sys.argv[2])",
                    resultFile,
                    content
                ]);
                visible = false;
                pickerClosed();
            }

            function toUri(path: string): string {
                if (path.startsWith("file://"))
                    return path;
                return "file://" + path;
            }

            function accept(): void {
                if (!selectionValid)
                    return;
                if (mode === "save") {
                    const name = (nameField.text || "").trim();
                    writeResult([toUri(nState.cwdPath() + "/" + name)], false);
                    return;
                }
                if (acceptDirectories || mode === "folder") {
                    const sel = nState.selection || [];
                    // if a single directory is selected, use it; else current folder
                    if (sel.length === 1) {
                        writeResult([toUri(sel[0])], false);
                        return;
                    }
                    writeResult([toUri(nState.cwdPath())], false);
                    return;
                }
                const sel = nState.selection || [];
                if (!sel.length)
                    return;
                const uris = [];
                for (let i = 0; i < sel.length; i++)
                    uris.push(toUri(sel[i]));
                writeResult(uris, false);
            }

            function reject(): void {
                writeResult([], true);
            }

            // Lightweight actions for FolderView (open/activate only; no file ops in portal)
            QtObject {
                id: nActions
                function openEntry(isDir: bool, name: string, path: string): void {
                    if (isDir) {
                        nState.openAbsolutePath(path);
                        return;
                    }
                    if (dlg.mode === "save") {
                        nameField.text = name || "";
                        nState.setSelection([path]);
                        return;
                    }
                    if (dlg.acceptDirectories || dlg.mode === "folder")
                        return;
                    nState.setSelection([path]);
                    if (!dlg.multiple)
                        dlg.accept();
                }
                function openPaths(paths: list<string>): void {
                    if (paths && paths.length)
                        openEntry(true, "", paths[0]);
                }
                function copy(paths: list<string>): void {}
                function cut(paths: list<string>): void {}
                function paste(): void {}
                function mkdir(): void {}
                function trash(paths: list<string>): void {}
                function deletePermanent(paths: list<string>): void {}
                function requestTrash(paths: list<string>): void {}
                function requestDelete(paths: list<string>): void {}
                function requestEmptyTrash(): void {}
                function emptyTrash(): void {}
                function compress(paths: list<string>, fmt: string): void {}
                function extract(paths: list<string>, mode: string): void {}
                function anyArchive(paths: list<string>): bool { return false; }
                function properties(path: string): void {}
            }

            implicitWidth: 1000
            implicitHeight: 640
            minimumSize.width: 480
            minimumSize.height: 360
            color: Colours.tPalette.m3surface
            surfaceFormat.opaque: false
            title: dialogTitle

            Component.onCompleted: {
                // Apply portal filters as name filter when single simple pattern
                if (filters && filters.length === 1 && filters[0] !== "*")
                    nState.nameFilter = filters[0];
                if (startDir && startDir.length)
                    nState.openAbsolutePath(startDir);
                else
                    nState.navigateToPlace("Home");
                if (mode === "save" && suggestedName)
                    nameField.text = suggestedName;
                nState.statusText = dialogTitle;
            }

            onVisibleChanged: {
                if (!visible && !done)
                    reject();
            }

            ManagerState {
                id: nState
            }

            FmDevices {
                id: nDevices
                onMountFinished: (ok, message, path) => {
                    if (ok && path)
                        nState.openAbsolutePath(path);
                    else if (!ok)
                        nState.statusText = message || qsTr("挂载失败");
                }
            }

            Item {
                id: chrome
                anchors.fill: parent
                focus: true

                Keys.onEscapePressed: dlg.reject()
                Keys.onReturnPressed: {
                    if (dlg.selectionValid)
                        dlg.accept();
                }
                Keys.onEnterPressed: {
                    if (dlg.selectionValid)
                        dlg.accept();
                }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
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
                                Layout.fillWidth: true
                                state: nState
                                actions: null
                                visible: !nState.isThisPC
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                FmThisPC {
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
                                        if (!device.device && !device.uri)
                                            return;
                                        nDevices.mountDevice(device.device || "", device.name || "", device.uri || "");
                                    }
                                }

                                FmFolderView {
                                    anchors.fill: parent
                                    visible: !nState.isThisPC
                                    state: nState
                                    actions: nActions
                                }
                            }

                            // Save filename
                            StyledRect {
                                visible: dlg.mode === "save"
                                Layout.fillWidth: true
                                implicitHeight: nameRow.implicitHeight + Tokens.padding.medium * 2
                                color: Colours.tPalette.m3surfaceContainer

                                RowLayout {
                                    id: nameRow
                                    anchors.fill: parent
                                    anchors.margins: Tokens.padding.medium
                                    spacing: Tokens.spacing.medium

                                    StyledText {
                                        text: qsTr("文件名：")
                                        color: Colours.palette.m3onSurfaceVariant
                                        font: Tokens.font.body.small
                                    }

                                    StyledRect {
                                        Layout.fillWidth: true
                                        implicitHeight: nameField.implicitHeight + Tokens.padding.small * 2
                                        radius: Tokens.rounding.medium
                                        color: Colours.tPalette.m3surfaceContainerHigh

                                        TextInput {
                                            id: nameField
                                            anchors.fill: parent
                                            anchors.margins: Tokens.padding.small
                                            color: Colours.palette.m3onSurface
                                            font: Tokens.font.body.small
                                            clip: true
                                            selectByMouse: true
                                            Keys.onReturnPressed: dlg.accept()
                                        }
                                    }
                                }
                            }

                            // Footer: status + Open/Cancel
                            StyledRect {
                                Layout.fillWidth: true
                                implicitHeight: btnRow.implicitHeight + Tokens.padding.medium * 2
                                color: Colours.tPalette.m3surfaceContainer

                                RowLayout {
                                    id: btnRow
                                    anchors.fill: parent
                                    anchors.margins: Tokens.padding.medium
                                    spacing: Tokens.spacing.small

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: {
                                            if (dlg.mode === "save")
                                                return qsTr("选择目录并输入文件名");
                                            if (dlg.acceptDirectories || dlg.mode === "folder")
                                                return qsTr("选择文件夹，或进入目录后点「选择文件夹」");
                                            const n = (nState.selection || []).length;
                                            if (n)
                                                return qsTr("已选 %1 项 · %2").arg(n).arg(dlg.filterLabel);
                                            return dlg.filterLabel || nState.statusText;
                                        }
                                        color: Colours.palette.m3onSurfaceVariant
                                        font: Tokens.font.body.small
                                        elide: Text.ElideRight
                                    }

                                    StyledRect {
                                        implicitWidth: okLbl.implicitWidth + Tokens.padding.large * 2
                                        implicitHeight: okLbl.implicitHeight + Tokens.padding.medium
                                        radius: Tokens.rounding.full
                                        color: dlg.selectionValid ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest

                                        StateLayer {
                                            radius: parent.radius
                                            disabled: !dlg.selectionValid
                                            color: Colours.palette.m3onPrimary
                                            onClicked: dlg.accept()
                                        }
                                        StyledText {
                                            id: okLbl
                                            anchors.centerIn: parent
                                            text: dlg.mode === "save"
                                                ? qsTr("保存")
                                                : (dlg.acceptDirectories || dlg.mode === "folder" ? qsTr("选择文件夹") : qsTr("打开"))
                                            color: dlg.selectionValid ? Colours.palette.m3onPrimary : Colours.palette.m3outline
                                            font: Tokens.font.body.builders.small.weight(Font.Bold).build()
                                        }
                                    }

                                    StyledRect {
                                        implicitWidth: cancelLbl.implicitWidth + Tokens.padding.large * 2
                                        implicitHeight: cancelLbl.implicitHeight + Tokens.padding.medium
                                        radius: Tokens.rounding.full
                                        color: "transparent"
                                        border.width: 1
                                        border.color: Colours.palette.m3outlineVariant

                                        StateLayer {
                                            radius: parent.radius
                                            onClicked: dlg.reject()
                                        }
                                        StyledText {
                                            id: cancelLbl
                                            anchors.centerIn: parent
                                            text: qsTr("取消")
                                            color: Colours.palette.m3onSurface
                                            font: Tokens.font.body.small
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Behavior on color {
                CAnim {}
            }
        }
    }

    FileView {
        id: requestView
        printErrors: false
        path: ""
        onLoaded: {
            try {
                const o = JSON.parse(text());
                const filters = (o.filters && o.filters.length) ? o.filters : ["*"];
                root.openPicker({
                    mode: o.mode || "open",
                    title: o.title || qsTr("选择文件"),
                    resultFile: o.resultFile || "",
                    filters: filters,
                    filterLabel: (o.filterLabel || filters.join(", ")),
                    startDir: o.startDir || "",
                    suggestedName: o.suggestedName || "untitled",
                    multiple: !!o.multiple,
                    acceptDirectories: !!o.acceptDirectories || o.mode === "folder"
                });
            } catch (e) {
                console.warn("filechooser request parse failed", e);
            }
        }
    }

    IpcHandler {
        target: "filechooser"

        function request(jsonPath: string): void {
            if (!jsonPath || !jsonPath.length)
                return;
            requestView.path = "";
            Qt.callLater(() => {
                requestView.path = jsonPath;
                requestView.reload();
            });
        }

        function open(title: string, resultFile: string, filtersCsv: string, startDir: string, multiple: string): void {
            const filters = (filtersCsv && filtersCsv.length && filtersCsv !== "*")
                ? filtersCsv.split(",").map(s => s.trim()).filter(s => s.length)
                : ["*"];
            root.openPicker({
                mode: "open",
                title: title || qsTr("打开文件"),
                resultFile: resultFile,
                filters: filters,
                filterLabel: filters.join(", "),
                startDir: startDir || "",
                multiple: multiple === "1" || multiple === "true",
                acceptDirectories: false
            });
        }

        function save(title: string, resultFile: string, filtersCsv: string, startDir: string, suggestedName: string): void {
            const filters = (filtersCsv && filtersCsv.length && filtersCsv !== "*")
                ? filtersCsv.split(",").map(s => s.trim()).filter(s => s.length)
                : ["*"];
            root.openPicker({
                mode: "save",
                title: title || qsTr("保存文件"),
                resultFile: resultFile,
                filters: filters,
                filterLabel: filters.join(", "),
                startDir: startDir || "",
                suggestedName: suggestedName || "untitled",
                acceptDirectories: false
            });
        }

        function folder(title: string, resultFile: string, startDir: string): void {
            root.openPicker({
                mode: "folder",
                title: title || qsTr("选择文件夹"),
                resultFile: resultFile,
                startDir: startDir || "",
                acceptDirectories: true,
                filters: ["*"]
            });
        }
    }
}
