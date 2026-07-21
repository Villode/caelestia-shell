pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.images
import qs.services
import qs.utils

Item {
    id: root

    required property var state
    required property var actions

    property string pendingQuery: ""
    property int searchToken: 0

    function kickSearch(q: string): void {
        pendingQuery = (q || "").trim();
        debounce.restart();
    }

    function cancelSearch(): void {
        debounce.stop();
        if (findProc.running)
            findProc.signal(15);
        root.state.setGlobalResults([], "", false);
    }

    function shellQuote(s: string): string {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    function runFind(): void {
        const q = pendingQuery;
        if (!q.length) {
            root.state.setGlobalResults([], "", false);
            return;
        }
        searchToken = searchToken + 1;
        const token = searchToken;
        root.state.setGlobalResults([], q, true);

        const home = Paths.home;
        const lit = q.replace(/[\0\n\r]/g, "");
        const pattern = "*" + lit + "*";
        findProc.command = [
            "bash", "-lc",
            "find " + shellQuote(home) +
            " \\( -path " + shellQuote(home + "/.cache") + " -o " +
            " -path " + shellQuote(home + "/.local/share/Trash") + " -o " +
            " -path " + shellQuote(home + "/.cargo") + " -o " +
            " -path " + shellQuote(home + "/.rustup") + " -o " +
            " -path " + shellQuote(home + "/.npm") + " -o " +
            " -name .git -o -name node_modules -o -name __pycache__ \\) -prune -o " +
            " \\( -type f -o -type d \\) -iname " + shellQuote(pattern) +
            " -printf '%y\\t%p\\n' 2>/dev/null | head -n 400"
        ];
        findProc._token = token;
        findProc.running = true;
    }

    function iconForPath(path: string, isDir: bool): string {
        if (isDir)
            return Quickshell.iconPath("inode-directory");
        const base = path.split("/").pop() || "";
        const i = base.lastIndexOf(".");
        if (i > 0) {
            const suf = base.slice(i + 1).toLowerCase();
            const map = {
                png: "image-png", jpg: "image-jpeg", jpeg: "image-jpeg", gif: "image-gif", webp: "image-webp",
                pdf: "application-pdf", txt: "text-plain", md: "text-markdown",
                zip: "application-zip", "7z": "application-x-7z-compressed",
                mp3: "audio-mpeg", mp4: "video-mp4", mkv: "video-x-matroska"
            };
            if (map[suf])
                return Quickshell.iconPath(map[suf], "application-x-zerosize");
        }
        return Quickshell.iconPath("application-x-zerosize");
    }

    function openHit(path: string, isDir: bool): void {
        if (!path)
            return;
        if (isDir) {
            root.state.setSearchScope("local");
            root.state.clearNameFilter();
            root.state.openAbsolutePath(path);
        } else {
            root.actions.openPaths([path]);
        }
    }

    function revealParent(path: string): void {
        if (!path)
            return;
        const i = path.lastIndexOf("/");
        if (i <= 0)
            return;
        root.state.setSearchScope("local");
        root.state.clearNameFilter();
        root.state.openAbsolutePath(path.slice(0, i));
    }

    Timer {
        id: debounce
        interval: 320
        repeat: false
        onTriggered: root.runFind()
    }

    Process {
        id: findProc
        property int _token: 0
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (findProc._token !== root.searchToken)
                    return;
                const q = root.pendingQuery;
                const lines = text.split("\n");
                const out = [];
                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i].trim();
                    if (!line.length)
                        continue;
                    const tab = line.indexOf("\t");
                    let typeCh = "f";
                    let p = line;
                    if (tab >= 0) {
                        typeCh = line.slice(0, tab);
                        p = line.slice(tab + 1);
                    }
                    if (!p.length)
                        continue;
                    const slash = p.lastIndexOf("/");
                    const name = slash >= 0 ? p.slice(slash + 1) : p;
                    const parent = slash > 0 ? p.slice(0, slash) : "/";
                    out.push({
                        path: p,
                        name: name,
                        parent: parent,
                        isDir: typeCh === "d"
                    });
                    if (out.length >= 400)
                        break;
                }
                root.state.setGlobalResults(out, q, false);
            }
        }
        onExited: code => {
            if (findProc._token !== root.searchToken)
                return;
            if (root.state.globalSearchBusy)
                root.state.setGlobalResults(root.state.globalResults, root.pendingQuery, false);
        }
    }

    Connections {
        target: root.state
        function onNameFilterChanged(): void {
            if (root.state.searchScope !== "global")
                return;
            root.kickSearch(root.state.nameFilter);
        }
        function onSearchScopeChanged(): void {
            if (root.state.searchScope === "global")
                root.kickSearch(root.state.nameFilter);
            else
                root.cancelSearch();
        }
    }

    ListView {
        id: list
        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        anchors.topMargin: header.implicitHeight + Tokens.padding.medium + Tokens.spacing.small
        clip: true
        spacing: 2
        model: root.state.globalResults
        delegate: resultDelegate

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: list
        }
    }

    RowLayout {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.medium
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: root.state.globalSearchBusy ? "hourglass_top" : "travel_explore"
            color: Colours.palette.m3primary
            fontStyle: Tokens.font.icon.medium
        }
        StyledText {
            Layout.fillWidth: true
            text: {
                if (root.state.globalSearchBusy)
                    return qsTr("正在主目录中搜索「%1」…").arg(root.state.globalSearchQuery || root.state.nameFilter);
                if (!(root.state.nameFilter || "").length)
                    return qsTr("输入关键词，在主目录中全局搜索");
                return qsTr("「%1」· %2 个结果（最多 400）").arg(root.state.globalSearchQuery || root.state.nameFilter).arg(root.state.globalResults.length);
            }
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.builders.small.build()
            elide: Text.ElideMiddle
        }
        StyledText {
            text: qsTr("主目录")
            color: Colours.palette.m3outline
            font: Tokens.font.body.builders.small.scale(0.9).build()
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        visible: !root.state.globalSearchBusy && root.state.globalResults.length === 0
        z: 1
        MaterialIcon {
            Layout.alignment: Qt.AlignHCenter
            text: (root.state.nameFilter || "").length ? "search_off" : "travel_explore"
            color: Colours.palette.m3outline
            fontStyle: Tokens.font.icon.builders.extraLarge.scale(1.5).weight(Font.Medium).build()
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: (root.state.nameFilter || "").length
                ? qsTr("无全局结果「%1」").arg(root.state.nameFilter)
                : qsTr("全局搜索主目录下的文件与文件夹")
            color: Colours.palette.m3outline
            font: Tokens.font.body.builders.large.weight(Font.Medium).build()
        }
    }

    Component {
        id: resultDelegate
        StyledRect {
            id: row
            required property var modelData
            required property int index
            width: ListView.view ? ListView.view.width : 200
            implicitHeight: 48
            radius: Tokens.rounding.medium
            color: ListView.isCurrentItem ? Qt.alpha(Colours.palette.m3secondaryContainer, 0.6) : "transparent"

            StateLayer {
                color: Colours.palette.m3onSurface
                onClicked: {
                    list.currentIndex = row.index;
                    root.openHit(row.modelData.path, !!row.modelData.isDir);
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.medium
                anchors.rightMargin: Tokens.padding.medium
                spacing: Tokens.spacing.medium

                CachingIconImage {
                    implicitSize: 28
                    source: root.iconForPath(row.modelData.path, !!row.modelData.isDir)
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        text: row.modelData.name || ""
                        elide: Text.ElideMiddle
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: row.modelData.parent || ""
                        elide: Text.ElideMiddle
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.builders.small.scale(0.85).build()
                    }
                }

                Item {
                    implicitWidth: 28
                    implicitHeight: 28
                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "folder_open"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small
                    }
                    StateLayer {
                        radius: Tokens.rounding.full
                        onClicked: root.revealParent(row.modelData.path)
                    }
                }
            }
        }
    }
}
