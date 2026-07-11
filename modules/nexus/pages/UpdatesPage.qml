pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    property list<var> components: []
    property bool checking
    property bool checkedOnce
    property string errorText
    property string lastChecked
    readonly property int updateCount: components.filter(item => item.status === "有更新" || item.status === "需要修复").length

    property Process checkProcess: Process {
        id: checkProcess

        command: ["villode-caelestia-update", "--check"]

        stdout: StdioCollector {
            onStreamFinished: root.parseUpdates(text)
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    root.errorText = text.trim();
            }
        }

        onExited: code => { // qmllint disable signal-handler-parameters
            root.checking = false;
            if (code !== 0 && !root.errorText)
                root.errorText = "检查更新失败，请确认网络连接。";
        }
    }

    function checkUpdates(): void {
        if (checkProcess.running)
            return;
        root.checking = true;
        root.errorText = "";
        root.components = [];
        checkProcess.running = true;
    }

    function launchUpdate(): void {
        const terminal = [...GlobalConfig.general.apps.terminal];
        Quickshell.execDetached([Quickshell.shellPath("assets/villode_terminal_exec.sh"), String(terminal.length), ...terminal, "--", "sh", "-lc", "villode-caelestia-update; code=$?; echo; if [ $code -eq 0 ]; then echo '更新完成。'; else echo '更新失败，退出码：'$code; fi; echo '按回车键关闭…'; read -r; exit $code"]);
    }

    function parseUpdates(text: string): void {
        const rows = [];
        for (const line of text.trim().split("\n")) {
            if (!line)
                continue;
            const fields = line.split("\t");
            if (fields.length < 5)
                continue;
            rows.push({
                id: fields[0],
                name: fields[1],
                installed: fields[2] || "—",
                latest: fields[3] || "—",
                status: fields[4]
            });
        }
        root.components = rows;
        root.checkedOnce = true;
        root.lastChecked = Qt.formatDateTime(new Date(), "HH:mm");
    }

    title: "Villode 更新"

    Component.onCompleted: checkUpdates()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: summaryLayout.implicitHeight + Tokens.padding.large * 2

            RowLayout {
                id: summaryLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                StyledRect {
                    implicitWidth: implicitHeight
                    implicitHeight: summaryIcon.implicitHeight + Tokens.padding.large
                    radius: Tokens.rounding.full
                    color: root.updateCount > 0 ? Colours.palette.m3primaryContainer : Colours.palette.m3secondaryContainer

                    MaterialIcon {
                        id: summaryIcon

                        anchors.centerIn: parent
                        text: root.checking ? "sync" : root.updateCount > 0 ? "system_update" : "check_circle"
                        color: root.updateCount > 0 ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSecondaryContainer
                        fontStyle: Tokens.font.icon.large

                        RotationAnimator on rotation {
                            running: root.checking
                            from: 0
                            to: 360
                            duration: 900
                            loops: Animation.Infinite
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: root.checking ? "正在检查更新…" : root.errorText ? "无法检查更新" : root.updateCount > 0 ? `发现 ${root.updateCount} 个更新或修复项` : "所有组件均为最新"
                        font: Tokens.font.body.large
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.errorText || (root.lastChecked ? `上次检查：${root.lastChecked}` : "从 Villode GitHub 发布通道获取更新")
                        color: root.errorText ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                        wrapMode: Text.Wrap
                    }
                }

                IconTextButton {
                    icon: "refresh"
                    text: "检查"
                    type: IconTextButton.Tonal
                    disabled: root.checking
                    onClicked: root.checkUpdates()
                }
            }
        }

        SectionHeader {
            text: "组件"
        }

        Repeater {
            model: root.components

            ConnectedRect {
                id: componentRow

                required property var modelData
                required property int index

                Layout.fillWidth: true
                first: componentRow.index === 0
                last: componentRow.index === root.components.length - 1
                implicitHeight: componentLayout.implicitHeight + Tokens.padding.large * 2

                RowLayout {
                    id: componentLayout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            text: componentRow.modelData.name
                            font: Tokens.font.body.medium
                        }

                        StyledText {
                            text: `已安装 ${componentRow.modelData.installed}  ·  发布 ${componentRow.modelData.latest}`
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.small
                        }
                    }

                    StyledText {
                        text: componentRow.modelData.status
                        color: componentRow.modelData.status === "有更新" || componentRow.modelData.status === "需要修复" ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.medium
                    }
                }
            }
        }

        StyledText {
            visible: root.checkedOnce && root.components.length === 0 && !root.checking
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.large
            text: root.errorText || "没有检测到已安装的 Villode 组件。"
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.medium
        }

        IconTextButton {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.large
            icon: "system_update"
            text: root.updateCount > 0 ? `更新 ${root.updateCount} 个组件` : "已是最新"
            type: IconTextButton.Filled
            disabled: root.checking || root.updateCount === 0
            onClicked: root.launchUpdate()
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.small
            Layout.maximumWidth: root.cappedWidth * 0.8
            text: "仅安装 Villode 发布清单锁定的版本。用户配置与数据不会被清除。"
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }
    }
}
