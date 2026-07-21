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

// Lightweight Quick Look overlay (Space). Image / text / fallback meta.
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
    property string kind: "other" // image | text | other | dir
    property string textBody: ""
    property string metaLine: ""

    readonly property var textExts: [
        "txt", "md", "markdown", "json", "qml", "js", "ts", "tsx", "jsx",
        "css", "scss", "html", "htm", "xml", "yml", "yaml", "toml", "ini",
        "conf", "cfg", "log", "csv", "sh", "bash", "zsh", "py", "rs", "go",
        "c", "h", "cpp", "hpp", "java", "kt", "swift", "sql", "desktop"
    ]

    function extOf(p: string): string {
        const n = (p || "").split("/").pop() || "";
        const i = n.lastIndexOf(".");
        if (i <= 0)
            return "";
        return n.slice(i + 1).toLowerCase();
    }

    function openFor(entryPath: string, entryName: string, entryIsDir: bool, entryIsImage: bool): void {
        if (!entryPath || !entryPath.length)
            return;
        path = entryPath;
        name = entryName || entryPath.split("/").pop() || entryPath;
        isDir = !!entryIsDir;
        isImage = !!entryIsImage;
        textBody = "";
        metaLine = "";
        if (isDir) {
            kind = "dir";
            metaLine = qsTr("文件夹");
        } else if (isImage) {
            kind = "image";
            metaLine = qsTr("图片预览");
        } else {
            const ext = extOf(path);
            if (textExts.indexOf(ext) >= 0) {
                kind = "text";
                metaLine = qsTr("文本预览");
                textLoader.path = path;
                textLoader.reload();
            } else {
                kind = "other";
                metaLine = qsTr("按 Enter 用默认应用打开");
            }
        }
        expanded = true;
    }

    function close(): void {
        expanded = false;
        path = "";
        textBody = "";
    }

    function toggle(entryPath: string, entryName: string, entryIsDir: bool, entryIsImage: bool): void {
        if (expanded && path === entryPath) {
            close();
            return;
        }
        openFor(entryPath, entryName, entryIsDir, entryIsImage);
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
        width: Math.min(parent.width - 48, 920)
        height: Math.min(parent.height - 48, 640)
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainerHigh
        clip: true

        // swallow clicks
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: {}
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.medium

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: root.isDir ? "folder" : (root.kind === "image" ? "image" : (root.kind === "text" ? "description" : "draft"))
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
                text: root.metaLine
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.builders.small.build()
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Image {
                    anchors.fill: parent
                    visible: root.kind === "image"
                    source: root.kind === "image" ? Qt.resolvedUrl(root.path) : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    smooth: true
                    mipmap: true
                }

                Flickable {
                    id: textFlick
                    anchors.fill: parent
                    visible: root.kind === "text"
                    contentWidth: width
                    contentHeight: bodyText.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    StyledText {
                        id: bodyText
                        width: textFlick.width
                        text: root.textBody.length ? root.textBody : qsTr("加载中…")
                        wrapMode: Text.WrapAnywhere
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.mono.small
                    }
                    StyledScrollBar.vertical: StyledScrollBar {
                        flickable: textFlick
                    }
                }

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
                Item { Layout.fillWidth: true }
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
                    color: Colours.tPalette.m3surfaceContainerHighest
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
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Space) {
            root.close();
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.path)
                Quickshell.execDetached(["xdg-open", root.path]);
            event.accepted = true;
        }
    }
}
