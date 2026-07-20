pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

// In-window modal sheet (not a separate FloatingWindow)
Item {
    id: root

    property string targetPath: ""
    property string fileName: ""
    property string kindLabel: ""
    property string sizeLabel: qsTr("…")
    property string mtimeLabel: qsTr("…")
    property string modeLabel: ""
    property bool expanded: false

    anchors.fill: parent
    z: 20000
    visible: expanded
    enabled: expanded

    function openFor(path: string): void {
        targetPath = path || "";
        if (!targetPath.length)
            return;
        const parts = targetPath.split("/");
        fileName = parts[parts.length - 1] || targetPath;
        sizeLabel = qsTr("…");
        mtimeLabel = qsTr("…");
        modeLabel = "";
        kindLabel = qsTr("文件");
        expanded = true;
        infoProc.running = false;
        infoProc.running = true;
    }

    function close(): void {
        expanded = false;
    }

    function humanSize(bytes: real): string {
        if (bytes < 1024)
            return `${Math.round(bytes)} B`;
        const units = ["KB", "MB", "GB", "TB"];
        let v = bytes / 1024;
        let i = 0;
        while (v >= 1024 && i < units.length - 1) {
            v /= 1024;
            i++;
        }
        return `${v.toFixed(v >= 10 ? 0 : 1)} ${units[i]}`;
    }

    function formatUnix(ts: real): string {
        if (!ts || isNaN(ts))
            return "—";
        const d = new Date(ts * 1000);
        if (isNaN(d.getTime()))
            return "—";
        const p = n => String(n).padStart(2, "0");
        return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
    }

    Process {
        id: infoProc
        // %Y = mtime epoch (avoids long locale %y with ns/tz)
        command: ["stat", "-c", "%F\n%s\n%Y\n%a\n%U:%G", root.targetPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                if (lines.length >= 1) {
                    const f = lines[0];
                    if (f.includes("directory") || f.includes("目录"))
                        root.kindLabel = qsTr("文件夹");
                    else if (f.includes("symbolic") || f.includes("链接"))
                        root.kindLabel = qsTr("符号链接");
                    else
                        root.kindLabel = qsTr("文件");
                }
                if (lines.length >= 2) {
                    const n = Number(lines[1]);
                    if (!isNaN(n))
                        root.sizeLabel = root.humanSize(n);
                }
                if (lines.length >= 3)
                    root.mtimeLabel = root.formatUnix(Number(lines[2]));
                if (lines.length >= 4)
                    root.modeLabel = lines[3].trim();
                if (lines.length >= 5)
                    root.modeLabel = (root.modeLabel ? root.modeLabel + " · " : "") + lines[4].trim();
            }
        }
    }

    // Dim backdrop
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    // Centered card
    StyledRect {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 420)
        height: Math.min(parent.height - 48, 400)
        radius: Tokens.rounding.large
        color: Colours.palette.m3surface
        border.width: 1
        border.color: Colours.palette.m3outlineVariant

        // Block clicks through card
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.medium

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.kindLabel.includes(qsTr("文件夹")) ? "folder" : "draft"
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.builders.extraLarge.scale(1.8).build()
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.fileName
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.body.builders.large.weight(Font.Bold).build()
                    elide: Text.ElideMiddle
                    wrapMode: Text.WrapAnywhere
                    maximumLineCount: 2
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.kindLabel
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }
            }

            StyledRect {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Tokens.rounding.large
                color: Colours.palette.m3surfaceContainer

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    spacing: Tokens.spacing.small

                    RowLayout {
                        Layout.fillWidth: true
                        StyledText {
                            text: qsTr("位置")
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.small
                        }
                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            text: Paths.shortenHome(root.targetPath)
                            color: Colours.palette.m3onSurface
                            font: Tokens.font.body.small
                            elide: Text.ElideMiddle
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        StyledText {
                            text: qsTr("大小")
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.small
                        }
                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            text: root.sizeLabel
                            color: Colours.palette.m3onSurface
                            font: Tokens.font.body.small
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        StyledText {
                            text: qsTr("修改时间")
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.small
                        }
                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            text: root.mtimeLabel
                            color: Colours.palette.m3onSurface
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        StyledText {
                            text: qsTr("权限")
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.small
                        }
                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            text: root.modeLabel || "—"
                            color: Colours.palette.m3onSurface
                            font: Tokens.font.body.small
                        }
                    }

                    Item { Layout.fillHeight: true }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        StyledRect {
                            implicitHeight: 36
                            implicitWidth: copyLabel.implicitWidth + Tokens.padding.large * 2
                            radius: Tokens.rounding.full
                            color: Colours.palette.m3secondaryContainer

                            StateLayer {
                                color: Colours.palette.m3onSecondaryContainer
                                onClicked: Quickshell.execDetached(["wl-copy", root.targetPath])
                            }
                            StyledText {
                                id: copyLabel
                                anchors.centerIn: parent
                                text: qsTr("复制路径")
                                color: Colours.palette.m3onSecondaryContainer
                                font: Tokens.font.body.small
                            }
                        }

                        Item { Layout.fillWidth: true }

                        StyledRect {
                            implicitHeight: 36
                            implicitWidth: doneLabel.implicitWidth + Tokens.padding.large * 2
                            radius: Tokens.rounding.full
                            color: Colours.palette.m3primary

                            StateLayer {
                                color: Colours.palette.m3onPrimary
                                onClicked: root.close()
                            }
                            StyledText {
                                id: doneLabel
                                anchors.centerIn: parent
                                text: qsTr("完成")
                                color: Colours.palette.m3onPrimary
                                font: Tokens.font.body.builders.small.weight(Font.Bold).build()
                            }
                        }
                    }
                }
            }
        }
    }
}
