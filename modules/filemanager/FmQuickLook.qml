pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

// Lightweight Quick Look overlay (Space). Image / text / archive / fallback meta.
Item {
    id: root
    anchors.fill: parent
    visible: expanded
    z: 80

    property bool expanded: false
    property string path: ""
    property string name: ""
    property bool isDir: false
    property bool isImage: false
    property string kind: "other" // image | text | archive | other | dir
    property string textBody: ""
    property string metaLine: ""
    property string imageSource: ""
    property string imageStatus: ""
    property var archiveEntries: []
    property string archiveSummary: ""
    property bool archiveLoading: false
    property bool audioPlaying: false
    property string audioStatus: ""

    readonly property var textExts: [
        "txt", "md", "markdown", "json", "qml", "js", "ts", "tsx", "jsx",
        "css", "scss", "html", "htm", "xml", "yml", "yaml", "toml", "ini",
        "conf", "cfg", "log", "csv", "sh", "bash", "zsh", "py", "rs", "go",
        "c", "h", "cpp", "hpp", "java", "kt", "swift", "sql", "desktop",
        "svg"
    ]

    readonly property var imageExts: [
        "png", "jpg", "jpeg", "jpe", "jfif", "webp", "gif", "bmp", "tif",
        "tiff", "ico", "heic", "heif", "avif", "svg"
    ]

    readonly property var archiveExts: [
        "zip", "7z", "rar", "tar", "gz", "tgz", "xz", "txz", "bz2", "tbz2",
        "zst", "tzst", "lz", "lzma", "cab", "iso", "apk", "jar", "war"
    ]

    function compoundExt(p: string): string {
        const n = ((p || "").split("/").pop() || "").toLowerCase();
        const multi = [".tar.gz", ".tar.xz", ".tar.bz2", ".tar.zst", ".tgz", ".txz", ".tbz2", ".tzst"];
        for (let i = 0; i < multi.length; i++) {
            if (n.endsWith(multi[i]))
                return multi[i].slice(1);
        }
        const i = n.lastIndexOf(".");
        if (i <= 0)
            return "";
        return n.slice(i + 1);
    }

    function isImagePath(p: string, flag: bool): bool {
        if (flag)
            return true;
        const e = compoundExt(p);
        return imageExts.indexOf(e) >= 0;
    }

    function isArchivePath(p: string): bool {
        const e = compoundExt(p);
        if (archiveExts.indexOf(e) >= 0)
            return true;
        // tar.gz style already in compoundExt
        return e.indexOf("tar.") === 0;
    }

    function isTextPath(p: string): bool {
        const e = compoundExt(p);
        if (textExts.indexOf(e) >= 0)
            return true;
        // bare "gz" alone is archive, not text
        return false;
    }

    function fileUrl(p: string): string {
        if (!p || !p.length)
            return "";
        try {
            if (typeof Paths !== "undefined" && Paths.toLocalFile) {
                // Paths helpers if available for reverse; prefer manual encode
            }
        } catch (e) {}
        // Encode each path segment so Chinese / spaces work with Image
        const parts = String(p).split("/");
        const enc = [];
        for (let i = 0; i < parts.length; i++) {
            if (i === 0 && parts[i] === "") {
                enc.push("");
                continue;
            }
            enc.push(encodeURIComponent(parts[i]));
        }
        return "file://" + enc.join("/");
    }

    function formatSize(n: real): string {
        if (!n || n <= 0)
            return "—";
        const u = ["B", "KB", "MB", "GB", "TB"];
        let v = Number(n);
        let i = 0;
        while (v >= 1024 && i < u.length - 1) {
            v /= 1024;
            i++;
        }
        return (i === 0 ? String(Math.round(v)) : v.toFixed(v >= 10 ? 0 : 1)) + " " + u[i];
    }


    function isAudioPath(p: string): bool {
        const e = compoundExt(p);
        return ["mp3", "flac", "wav", "ogg", "oga", "opus", "m4a", "aac", "wma", "aiff", "ape", "alac"].indexOf(e) >= 0;
    }

    function isVideoPath(p: string): bool {
        const e = compoundExt(p);
        return ["mp4", "mkv", "webm", "avi", "mov", "m4v", "wmv", "flv", "ts", "m2ts"].indexOf(e) >= 0;
    }

    function startAudio(p: string): void {
        stopAudio();
        audioPlaying = true;
        audioStatus = qsTr("播放中…");
        audioProc.running = false;
        // --no-video audio only; quit when done
        audioProc.command = ["mpv", "--no-video", "--force-window=no", "--really-quiet", "--", p];
        audioProc.running = true;
    }

    function stopAudio(): void {
        if (audioProc.running)
            audioProc.running = false;
        audioPlaying = false;
    }

    function openFor(entryPath: string, entryName: string, entryIsDir: bool, entryIsImage: bool): void {
        if (!entryPath || !entryPath.length)
            return;
        archiveProc.running = false;
        path = entryPath;
        name = entryName || entryPath.split("/").pop() || entryPath;
        isDir = !!entryIsDir;
        isImage = isImagePath(entryPath, !!entryIsImage);
        textBody = "";
        metaLine = "";
        imageSource = "";
        imageStatus = "";
        archiveEntries = [];
        archiveSummary = "";
        archiveLoading = false;

        // stop previous audio
        stopAudio();

        if (isDir) {
            kind = "dir";
            metaLine = qsTr("文件夹");
        } else if (isImage) {
            kind = "image";
            imageSource = fileUrl(path);
            metaLine = qsTr("图片预览");
            imageStatus = qsTr("加载中…");
        } else if (isAudioPath(path)) {
            kind = "audio";
            metaLine = qsTr("音乐预览");
            audioStatus = qsTr("准备播放…");
            startAudio(path);
        } else if (isVideoPath(path)) {
            kind = "video";
            metaLine = qsTr("视频 — 使用内置播放器窗口");
            // Open mpv window for video (still "internal" vs random app)
            Quickshell.execDetached(["mpv", "--force-window=yes", "--keep-open=yes", "--title=Villode Preview", path]);
            audioStatus = qsTr("已在内部播放器打开");
        } else if (isArchivePath(path)) {
            // Prefer entering archive as folder from openEntry; Space still lists
            kind = "archive";
            metaLine = qsTr("压缩包内容（双击可进入浏览）");
            archiveLoading = true;
            archiveSummary = qsTr("正在读取列表…");
            loadArchive(path);
        } else if (isTextPath(path)) {
            kind = "text";
            metaLine = qsTr("文本预览");
            textLoader.path = path;
            textLoader.reload();
        } else {
            kind = "other";
            metaLine = qsTr("按 Enter 用默认应用打开");
        }
        expanded = true;
        forceActiveFocus();
        if (kind === "text")
            Qt.callLater(() => {
                if (typeof bodyText !== "undefined")
                    bodyText.forceActiveFocus();
            });
    }

    function close(): void {
        stopAudio();
        expanded = false;
        path = "";
        textBody = "";
        imageSource = "";
        archiveEntries = [];
        archiveProc.running = false;
        archiveLoading = false;
        audioStatus = "";
    }

    function toggle(entryPath: string, entryName: string, entryIsDir: bool, entryIsImage: bool): void {
        if (expanded && path === entryPath) {
            close();
            return;
        }
        openFor(entryPath, entryName, entryIsDir, entryIsImage);
    }

    function loadArchive(p: string): void {
        archiveProc.running = false;
        // -ba: brief technical info; -slt would be super verbose. Use normal list + parse table.
        archiveProc.command = ["7z", "l", "-ba", "--", p];
        archiveProc.running = true;
    }

    function parseArchiveList(raw: string): void {
        const lines = String(raw || "").split("\n");
        const items = [];
        let fileCount = 0;
        let dirCount = 0;
        let totalSize = 0;
        // -ba lines: "2026-07-08 09:55:35 D....            0            0  Name"
        // or without date depending on version; also match "..... size compressed name"
        const re = /^(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s+([D.][\w.]+)\s+(\d+)\s+(\d+)\s+(.+)$/;
        const reLoose = /^(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s+(\S+)\s+(\d+)\s+(\d+)\s+(.+)$/;
        for (let i = 0; i < lines.length; i++) {
            let line = lines[i];
            if (!line || !line.length)
                continue;
            line = line.replace(/\r$/, "");
            if (line.startsWith("----------") || line.startsWith("Path =") || line.startsWith("Type =") || line.startsWith("Physical") || line.startsWith("Listing") || line.startsWith("Scanning") || line.startsWith("--") || line.indexOf("Date") === 0 && line.indexOf("Time") > 0)
                continue;
            let m = line.match(re);
            if (!m)
                m = line.match(reLoose);
            if (!m) {
                // fallback: last fields
                const parts = line.trim().split(/\s+/);
                if (parts.length < 5)
                    continue;
                // try find attr field with D.... or .....
                continue;
            }
            const attr = m[2] || "";
            const size = Number(m[3] || 0);
            const name = (m[5] || "").trim();
            if (!name.length)
                continue;
            const isD = attr.indexOf("D") === 0;
            if (isD)
                dirCount++;
            else {
                fileCount++;
                totalSize += size;
            }
            if (items.length < 400) {
                items.push({
                    name: name,
                    isDir: isD,
                    size: size,
                    sizeText: isD ? qsTr("文件夹") : formatSize(size)
                });
            }
        }

        // If -ba empty parse, retry with full `7z l` human output via already collected — try alternate parse
        if (!items.length) {
            parseArchiveListLegacy(raw);
            return;
        }

        archiveEntries = items;
        archiveLoading = false;
        const more = (fileCount + dirCount) > items.length ? qsTr("（仅显示前 %1 项）").arg(items.length) : "";
        archiveSummary = qsTr("%1 个文件 · %2 个文件夹 · 约 %3 %4").arg(fileCount).arg(dirCount).arg(formatSize(totalSize)).arg(more);
        metaLine = qsTr("压缩包内容 · %1").arg(archiveSummary);
    }

    function parseArchiveListLegacy(raw: string): void {
        const lines = String(raw || "").split("\n");
        const items = [];
        let inTable = false;
        let fileCount = 0;
        let dirCount = 0;
        let totalSize = 0;
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].replace(/\r$/, "");
            if (line.indexOf("----") === 0) {
                inTable = !inTable;
                continue;
            }
            if (!inTable)
                continue;
            if (line.indexOf("files") >= 0 && line.indexOf("folders") >= 0)
                continue;
            // Date Time Attr Size Compressed Name — name starts at col ~53 often
            if (line.length < 20)
                continue;
            const attrMatch = line.match(/\s([D.][\w.]{4})\s+(\d+)\s+(\d+)\s+(.+)$/);
            if (!attrMatch)
                continue;
            const attr = attrMatch[1];
            const size = Number(attrMatch[2] || 0);
            const name = (attrMatch[4] || "").trim();
            if (!name.length)
                continue;
            const isD = attr.charAt(0) === "D";
            if (isD)
                dirCount++;
            else {
                fileCount++;
                totalSize += size;
            }
            if (items.length < 400) {
                items.push({
                    name: name,
                    isDir: isD,
                    size: size,
                    sizeText: isD ? qsTr("文件夹") : formatSize(size)
                });
            }
        }
        archiveEntries = items;
        archiveLoading = false;
        if (!items.length) {
            archiveSummary = qsTr("无法列出压缩包内容（可尝试安装/更新 p7zip）");
            metaLine = archiveSummary;
            return;
        }
        const more = (fileCount + dirCount) > items.length ? qsTr("（仅显示前 %1 项）").arg(items.length) : "";
        archiveSummary = qsTr("%1 个文件 · %2 个文件夹 · 约 %3 %4").arg(fileCount).arg(dirCount).arg(formatSize(totalSize)).arg(more);
        metaLine = qsTr("压缩包内容 · %1").arg(archiveSummary);
    }

    Process {
        id: audioProc
        command: ["true"]
        running: false
        onExited: code => {
            root.audioPlaying = false;
            root.audioStatus = qsTr("播放结束");
        }
    }

    FileView {
        id: textLoader
        printErrors: false
        path: ""
        onLoaded: {
            let t = text();
            if (t.length > 120000)
                t = t.slice(0, 120000) + "\n…";
            root.textBody = t;
        }
        onLoadFailed: {
            root.textBody = qsTr("（无法读取文件）");
        }
    }

    Process {
        id: archiveProc
        command: ["true"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.kind !== "archive")
                    return;
                // Prefer property `text` (Quickshell StdioCollector)
                let raw = "";
                try {
                    raw = text;
                } catch (e1) {
                    try {
                        raw = text();
                    } catch (e2) {
                        raw = "";
                    }
                }
                root.parseArchiveList(raw);
            }
        }
        stderr: StdioCollector {
            id: archiveErr
        }
        onExited: code => {
            if (root.kind !== "archive")
                return;
            if (code !== 0 && !root.archiveEntries.length) {
                root.archiveLoading = false;
                let err = "";
                try {
                    err = (archiveErr.text || "").trim();
                } catch (e) {
                    err = "";
                }
                root.archiveSummary = err.length ? qsTr("读取失败：%1").arg(err.slice(0, 160)) : qsTr("无法列出压缩包内容");
                root.metaLine = root.archiveSummary;
            }
        }
    }

    // Backdrop
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Colours.palette.m3scrim, 0.55)
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    StyledRect {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, root.kind === "archive" ? 960 : 920)
        height: Math.min(parent.height - 48, 680)
        radius: Tokens.rounding.large
        // Opaque surface — translucent tPalette made text/image hard to read
        color: Colours.palette.m3surfaceContainerHigh
        border.width: 1
        border.color: Colours.palette.m3outlineVariant
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.medium

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: {
                        if (root.isDir)
                            return "folder";
                        if (root.kind === "image")
                            return "image";
                        if (root.kind === "text")
                            return "description";
                        if (root.kind === "archive")
                            return "folder_zip";
                        if (root.kind === "audio")
                            return "music_note";
                        if (root.kind === "video")
                            return "movie";
                        return "draft";
                    }
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.large
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        text: root.name
                        elide: Text.ElideMiddle
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.body.builders.large.weight(Font.Bold).build()
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.path
                        elide: Text.ElideMiddle
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.builders.small.build()
                    }
                }

                Item {
                    implicitWidth: 36
                    implicitHeight: 36
                    StateLayer {
                        radius: Tokens.rounding.full
                        onClicked: root.close()
                    }
                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "close"
                        color: Colours.palette.m3onSurface
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: root.metaLine
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.builders.small.build()
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.WordWrap
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // —— Image ——
                StyledRect {
                    anchors.fill: parent
                    visible: root.kind === "image"
                    radius: Tokens.rounding.medium
                    color: Colours.palette.m3surface
                    clip: true

                    Image {
                        id: previewImage
                        anchors.fill: parent
                        anchors.margins: 8
                        source: root.imageSource
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: true
                        smooth: true
                        mipmap: true
                        onStatusChanged: {
                            if (status === Image.Loading)
                                root.imageStatus = qsTr("加载中…");
                            else if (status === Image.Ready)
                                root.imageStatus = qsTr("%1 × %2").arg(sourceSize.width).arg(sourceSize.height);
                            else if (status === Image.Error)
                                root.imageStatus = qsTr("图片加载失败");
                        }
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: previewImage.status !== Image.Ready
                        spacing: Tokens.spacing.small
                        CircularIndicator {
                            Layout.alignment: Qt.AlignHCenter
                            implicitSize: 40
                            running: previewImage.status === Image.Loading
                            visible: previewImage.status === Image.Loading
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.imageStatus
                            color: Colours.palette.m3outline
                            font: Tokens.font.body.medium
                        }
                    }
                }

                // —— Text (selectable + copyable) ——
                StyledRect {
                    anchors.fill: parent
                    visible: root.kind === "text"
                    radius: Tokens.rounding.medium
                    color: Colours.palette.m3surface
                    border.width: 1
                    border.color: Colours.palette.m3outlineVariant
                    clip: true

                    ScrollView {
                        id: textScroll
                        anchors.fill: parent
                        anchors.margins: 8
                        clip: true

                        TextEdit {
                            id: bodyText
                            width: textScroll.availableWidth
                            readOnly: true
                            selectByMouse: true
                            selectByKeyboard: true
                            persistentSelection: true
                            wrapMode: TextEdit.WrapAnywhere
                            textFormat: TextEdit.PlainText
                            color: Colours.palette.m3onSurface
                            selectedTextColor: Colours.palette.m3onPrimary
                            selectionColor: Colours.palette.m3primary
                            font: Tokens.font.mono.small
                            text: root.textBody.length ? root.textBody : qsTr("加载中…")
                            // Allow Ctrl+C without closing preview
                            Keys.forwardTo: []
                            Keys.onPressed: event => {
                                if (event.matches(StandardKey.Copy) || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_C)) {
                                    bodyText.copy();
                                    event.accepted = true;
                                } else if (event.matches(StandardKey.SelectAll) || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_A)) {
                                    bodyText.selectAll();
                                    event.accepted = true;
                                }
                            }
                        }
                    }
                }

                // —— Archive listing ——
                Item {
                    anchors.fill: parent
                    visible: root.kind === "archive"

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: Tokens.spacing.small

                        StyledText {
                            Layout.fillWidth: true
                            visible: root.archiveLoading || root.archiveEntries.length === 0
                            text: root.archiveLoading ? qsTr("正在读取压缩包…") : (root.archiveSummary || qsTr("无内容"))
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.small
                        }

                        CircularIndicator {
                            Layout.alignment: Qt.AlignHCenter
                            implicitSize: 36
                            running: root.archiveLoading
                            visible: root.archiveLoading
                        }

                        ListView {
                            id: archiveList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: !root.archiveLoading && root.archiveEntries.length > 0
                            clip: true
                            model: root.archiveEntries
                            spacing: 2
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                            }

                            delegate: Item {
                                id: row
                                required property var modelData
                                required property int index
                                width: archiveList.width
                                height: 32

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 4
                                    anchors.rightMargin: 8
                                    spacing: 8

                                    MaterialIcon {
                                        text: row.modelData.isDir ? "folder" : "draft"
                                        color: row.modelData.isDir ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                        fontStyle: Tokens.font.icon.small
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: row.modelData.name
                                        elide: Text.ElideMiddle
                                        color: Colours.palette.m3onSurface
                                        font: Tokens.font.body.builders.small.build()
                                    }
                                    StyledText {
                                        text: row.modelData.sizeText || ""
                                        color: Colours.palette.m3onSurfaceVariant
                                        font: Tokens.font.mono.small
                                    }
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 1
                                    color: Qt.alpha(Colours.palette.m3outlineVariant, 0.35)
                                }
                            }
                        }
                    }
                }


                // —— Audio ——
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: root.kind === "audio" || root.kind === "video"
                    spacing: Tokens.spacing.medium
                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.kind === "video" ? "movie" : "music_note"
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.builders.extraLarge.scale(2).build()
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.name
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.body.builders.large.weight(Font.Bold).build()
                        elide: Text.ElideMiddle
                        Layout.maximumWidth: parent.parent.width - 48
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.audioStatus
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.medium
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Tokens.spacing.medium
                        visible: root.kind === "audio"
                        StyledRect {
                            implicitWidth: playLbl.implicitWidth + Tokens.padding.large * 2
                            implicitHeight: playLbl.implicitHeight + Tokens.padding.small * 2
                            radius: Tokens.rounding.full
                            color: Colours.palette.m3primaryContainer
                            StateLayer {
                                radius: parent.radius
                                onClicked: {
                                    if (root.audioPlaying)
                                        root.stopAudio();
                                    else
                                        root.startAudio(root.path);
                                }
                            }
                            StyledText {
                                id: playLbl
                                anchors.centerIn: parent
                                text: root.audioPlaying ? qsTr("停止") : qsTr("播放")
                                color: Colours.palette.m3onPrimaryContainer
                                font: Tokens.font.body.builders.small.weight(Font.Bold).build()
                            }
                        }
                    }
                }

                // —— Dir / other ——
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: root.kind === "other" || root.kind === "dir"
                    spacing: Tokens.spacing.medium
                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.kind === "dir" ? "folder_open" : "preview"
                        color: Colours.palette.m3outline
                        fontStyle: Tokens.font.icon.builders.extraLarge.scale(2).build()
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.kind === "dir" ? qsTr("文件夹 — Space 关闭，Enter 进入") : qsTr("无内嵌预览")
                        color: Colours.palette.m3outline
                        font: Tokens.font.body.medium
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small
                Item {
                    Layout.fillWidth: true
                }
                StyledRect {
                    implicitWidth: openLbl.implicitWidth + Tokens.padding.large * 2
                    implicitHeight: openLbl.implicitHeight + Tokens.padding.small * 2
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3secondaryContainer
                    StateLayer {
                        radius: parent.radius
                        color: Colours.palette.m3onSecondaryContainer
                        onClicked: {
                            if (root.path)
                                Quickshell.execDetached(["xdg-open", root.path]);
                        }
                    }
                    StyledText {
                        id: openLbl
                        anchors.centerIn: parent
                        text: qsTr("打开")
                        color: Colours.palette.m3onSecondaryContainer
                        font: Tokens.font.body.builders.small.weight(Font.Bold).build()
                    }
                }
                StyledRect {
                    implicitWidth: closeLbl.implicitWidth + Tokens.padding.large * 2
                    implicitHeight: closeLbl.implicitHeight + Tokens.padding.small * 2
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3surfaceContainerHighest
                    StateLayer {
                        radius: parent.radius
                        onClicked: root.close()
                    }
                    StyledText {
                        id: closeLbl
                        anchors.centerIn: parent
                        text: qsTr("关闭 (Esc / Space)")
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.body.builders.small.weight(Font.Bold).build()
                    }
                }
            }
        }
    }

    Keys.onPressed: event => {
        if (!root.expanded)
            return;
        // Esc always closes; Space closes only when text is not focused (so selection works)
        if (event.key === Qt.Key_Escape) {
            root.close();
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Space) {
            if (root.kind === "text" && bodyText.activeFocus)
                return;
            root.close();
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.kind === "text" && bodyText.activeFocus)
                return;
            if (root.path)
                Quickshell.execDetached(["xdg-open", root.path]);
            event.accepted = true;
        }
    }
}
