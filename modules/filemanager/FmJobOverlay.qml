pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Spacious in-window modal for compress/extract progress
Item {
    id: root

    property bool expanded: false
    property string title: qsTr("处理中…")
    property string detail: ""
    property real progress: -1 // -1 indeterminate
    property bool success: false
    property bool failed: false

    anchors.fill: parent
    z: 16000
    visible: expanded
    enabled: expanded

    function openJob(jobTitle: string, jobDetail: string): void {
        title = jobTitle || qsTr("处理中…");
        detail = jobDetail || "";
        progress = -1;
        success = false;
        failed = false;
        hideTimer.interval = 1000;
        expanded = true;
    }

    function setProgress(pct: real, text: string): void {
        if (pct >= 0)
            progress = Math.min(100, Math.max(0, pct));
        if (text && text.length)
            detail = text;
    }

    function finishOk(text: string): void {
        success = true;
        failed = false;
        progress = 100;
        if (text && text.length)
            detail = text;
        hideTimer.interval = 1000;
        hideTimer.restart();
    }

    function finishFail(text: string): void {
        success = false;
        failed = true;
        if (text && text.length)
            detail = text;
        hideTimer.interval = 2400;
        hideTimer.restart();
    }

    function close(): void {
        expanded = false;
        hideTimer.stop();
    }

    Timer {
        id: hideTimer
        interval: 1000
        repeat: false
        onTriggered: root.close()
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {}

        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Colours.palette.m3scrim, 0.42)
        }
    }

    StyledRect {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 64, 420)
        implicitHeight: body.implicitHeight + 48
        radius: Tokens.rounding.extraLarge
        color: Colours.palette.m3surfaceContainerHigh
        border.width: 1
        border.color: Colours.palette.m3outlineVariant

        ColumnLayout {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 28
            spacing: 20

            // Centered spinner / status
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 72
                Layout.preferredHeight: 72

                CircularIndicator {
                    anchors.centerIn: parent
                    implicitSize: 64
                    strokeWidth: 4
                    running: root.expanded && !root.success && !root.failed
                    visible: !root.success && !root.failed
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    visible: root.success
                    text: "check_circle"
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.builders.extraLarge.scale(1.6).build()
                    fill: 1
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    visible: root.failed
                    text: "error"
                    color: Colours.palette.m3error
                    fontStyle: Tokens.font.icon.builders.extraLarge.scale(1.6).build()
                    fill: 1
                }
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.title
                color: Colours.palette.m3onSurface
                font: Tokens.font.body.builders.large.weight(Font.DemiBold).build()
                wrapMode: Text.WordWrap
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.detail.length ? root.detail : (root.progress >= 0 ? qsTr("已完成 %1%").arg(Math.round(root.progress)) : qsTr("请稍候…"))
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
                elide: Text.ElideMiddle
                maximumLineCount: 2
                wrapMode: Text.WordWrap
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 10
                visible: !root.failed

                StyledProgressBar {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 8
                    from: 0
                    to: 100
                    value: root.progress >= 0 ? root.progress : 0
                    indeterminate: root.progress < 0 && !root.success && !root.failed
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.progress >= 0
                    text: qsTr("%1%").arg(Math.round(root.progress))
                    color: Colours.palette.m3primary
                    font: Tokens.font.body.builders.medium.weight(Font.Bold).build()
                }
            }
        }
    }
}
