pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.filedialog
import qs.services
import qs.utils

// Portal / external Open-Save picker. Reuses filedialog visuals; writes URIs to resultFile.
Scope {
    id: root

    property var win: null

    function finish(paths: var, cancelled: bool): void {
        // win closes itself after writing
        if (win) {
            win = null;
        }
    }

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
            property list<string> cwd: ["Home"]
            property string typedName: suggestedName
            property bool done: false

            signal pickerClosed

            readonly property bool selectionValid: {
                if (mode === "save") {
                    const name = (nameField.text || "").trim();
                    return name.length > 0 && !name.includes("/");
                }
                if (acceptDirectories || mode === "folder") {
                    // current folder always valid; or selected dir
                    const file = folderContents.currentItem?.modelData;
                    if (file && file.isDir)
                        return true;
                    return cwdPath().length > 0;
                }
                const file = folderContents.currentItem?.modelData;
                if (!file || file.isDir)
                    return false;
                if (filters.includes("*"))
                    return true;
                return filters.includes(file.suffix);
            }

            function cwdPath(): string {
                if (!cwd.length)
                    return Paths.home;
                if (cwd[0] === "Home" && cwd.length === 1)
                    return Paths.home;
                if (cwd[0] === "Home")
                    return Paths.home + "/" + cwd.slice(1).join("/");
                return cwd.join("/");
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
                // status line first for the portal backend
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

            // Called by FolderContents on double-click file
            function accepted(path: string): void {
                if (mode === "save") {
                    if (path && path.length) {
                        const base = path.split("/").pop();
                        if (base)
                            typedName = base;
                    }
                    accept();
                    return;
                }
                if (acceptDirectories || mode === "folder") {
                    writeResult([toUri(path || cwdPath())], false);
                    return;
                }
                writeResult([toUri(path)], false);
            }

            function rejected(): void {
                reject();
            }

            function accept(): void {
                if (!selectionValid)
                    return;
                if (mode === "save") {
                    const name = (nameField.text || "").trim();
                    const path = cwdPath() + "/" + name;
                    writeResult([toUri(path)], false);
                    return;
                }
                if (acceptDirectories || mode === "folder") {
                    const file = folderContents.currentItem?.modelData;
                    if (file && file.isDir)
                        writeResult([toUri(file.path)], false);
                    else
                        writeResult([toUri(cwdPath())], false);
                    return;
                }
                const file = folderContents.currentItem?.modelData;
                if (file && !file.isDir)
                    writeResult([toUri(file.path)], false);
            }

            function reject(): void {
                writeResult([], true);
            }

            implicitWidth: 1000
            implicitHeight: 640
            minimumSize.width: 480
            minimumSize.height: 360
            color: Colours.tPalette.m3surface
            surfaceFormat.opaque: false
            title: dialogTitle

            Component.onCompleted: {
                if (startDir && startDir.length) {
                    // map absolute path under home to cwd segments when possible
                    const home = Paths.home;
                    if (startDir === home || startDir === home + "/")
                        cwd = ["Home"];
                    else if (startDir.startsWith(home + "/")) {
                        const rest = startDir.slice(home.length + 1).split("/").filter(s => s.length);
                        cwd = ["Home"].concat(rest);
                    }
                }
                if (mode === "save" && suggestedName)
                    typedName = suggestedName;
            }

            onVisibleChanged: {
                if (!visible && !done)
                    reject();
            }

            // Escape
            Item {
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: dlg.reject()
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    // Lightweight places sidebar (reuse filedialog Sidebar API: dialog.cwd)
                    Sidebar {
                        Layout.fillHeight: true
                        dialog: dlg
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 0

                        HeaderBar {
                            Layout.fillWidth: true
                            dialog: dlg
                        }

                        FolderContents {
                            id: folderContents
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            dialog: dlg
                        }

                        // Save name field
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
                                        text: dlg.typedName
                                        color: Colours.palette.m3onSurface
                                        font: Tokens.font.body.small
                                        clip: true
                                        selectByMouse: true
                                        onTextChanged: dlg.typedName = text
                                        Keys.onReturnPressed: dlg.accept()
                                    }
                                }
                            }
                        }

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
                                    visible: !dlg.acceptDirectories && dlg.mode !== "save" && dlg.mode !== "folder"
                                    text: qsTr("筛选：")
                                    color: Colours.palette.m3onSurfaceVariant
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: dlg.mode === "save"
                                        ? qsTr("选择目录并输入文件名")
                                        : `${dlg.filterLabel}`
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
                                        text: dlg.mode === "save" ? qsTr("保存") : (dlg.acceptDirectories || dlg.mode === "folder" ? qsTr("选择文件夹") : qsTr("打开"))
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

        // Preferred: qs ipc call filechooser request <jsonPath>
        // JSON: {mode,title,resultFile,filters,startDir,suggestedName,multiple,acceptDirectories}
        function request(jsonPath: string): void {
            if (!jsonPath || !jsonPath.length)
                return;
            // force reload even if same path
            requestView.path = "";
            Qt.callLater(() => {
                requestView.path = jsonPath;
                requestView.reload();
            });
        }

        // Debug helpers (avoid spaces in title/path when using these)
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
