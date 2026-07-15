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
    property string checkedAtIso: ""
    readonly property int updateCount: components.filter(item => item.status === "有更新" || item.status === "需要修复" || item.status === "未安装").length

    title: qsTr("Villode updates")

    property Process checkProcess: Process {
        id: checkProcess
        command: ["villode-caelestia-update", "--check-json"]
        stdout: StdioCollector {
            onStreamFinished: root.parseUpdatesJson(text)
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
                root.errorText = qsTr("Could not check for updates. Check your network connection.");
        }
    }

    function checkUpdates(): void {
        if (checkProcess.running)
            return;
        root.checking = true;
        root.errorText = "";
        checkProcess.running = true;
    }

    function launchUpdate(): void {
        const terminal = [...GlobalConfig.general.apps.terminal];
        // The updater only syncs installed components by default; the button is
        // labelled "Install" when 未安装 rows exist, so opt into installing them.
        const hasMissing = root.components.some(item => item.status === "未安装");
        const updateCmd = hasMissing ? "villode-caelestia-update --install-missing" : "villode-caelestia-update";
        Quickshell.execDetached([Quickshell.shellPath("assets/villode_terminal_exec.sh"), String(terminal.length), ...terminal, "--", "sh", "-lc", updateCmd + "; code=$?; echo; if [ $code -eq 0 ]; then echo '更新完成。'; else echo '更新失败，退出码：'$code; fi; echo '按回车键关闭…'; read -r; exit $code"]);
    }

    function parseUpdatesJson(text: string): void {
        try {
            const data = JSON.parse(text);
            const rows = [];
            for (const c of (data.components || [])) {
                rows.push({
                    id: c.id || "",
                    name: c.name || c.id || qsTr("Component"),
                    installed: c.installed || "—",
                    latest: c.latest || "—",
                    installedFull: c.installedFull || "",
                    latestFull: c.latestFull || "",
                    status: c.status || qsTr("Unknown"),
                    installedAt: c.installedAt || "",
                    releasedAt: c.releasedAt || "",
                    changes: Array.isArray(c.changes) ? c.changes : []
                });
            }
            root.components = rows;
            root.checkedOnce = true;
            root.checkedAtIso = data.checkedAt || "";
            root.lastChecked = root.formatDateTime(data.checkedAt) || Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm");
            root.errorText = "";
        } catch (e) {
            root.parseUpdatesTsv(text);
        }
    }

    function parseUpdatesTsv(text: string): void {
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
                installedFull: "",
                latestFull: "",
                status: fields[4],
                installedAt: "",
                releasedAt: "",
                changes: []
            });
        }
        root.components = rows;
        root.checkedOnce = true;
        root.lastChecked = Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm");
    }

    function formatDateTime(iso: string): string {
        if (!iso)
            return "";
        const m = String(iso).match(/^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2})/);
        if (m)
            return `${m[1]} ${m[2]}`;
        return iso;
    }

    function hasUpdate(status: string): bool {
        return status === "有更新" || status === "需要修复" || status === "未安装";
    }

    function statusLabel(status: string): string {
        if (status === "有更新")
            return qsTr("Update available");
        if (status === "需要修复")
            return qsTr("Repair required");
        if (status === "未安装")
            return qsTr("Not installed");
        if (status === "已是最新")
            return qsTr("Up to date");
        return status;
    }

    function statusColour(status: string): color {
        if (status === "有更新")
            return Colours.palette.m3primary;
        if (status === "需要修复")
            return Colours.palette.m3tertiary;
        if (status === "未安装")
            return Colours.palette.m3secondary;
        return Colours.palette.m3outline;
    }

    function actionLabel(): string {
        const n = root.updateCount;
        if (n <= 0)
            return qsTr("Update");
        const hasInstall = root.components.some(item => item.status === "未安装");
        const hasUpdate = root.components.some(item => item.status === "有更新" || item.status === "需要修复");
        if (hasInstall && hasUpdate)
            return qsTr("Install / update (%1)").arg(n);
        if (hasInstall)
            return qsTr("Install (%1)").arg(n);
        return qsTr("Update (%1)").arg(n);
    }

    function componentIcon(id: string): string {
        switch (id) {
        case "shell":
            return "terminal";
        case "zh":
            return "translate";
        case "dock":
            return "dock_to_bottom";
        case "desktop":
            return "wallpaper";
        case "launcher":
            return "apps";
        case "cursor":
            return "mouse";
        default:
            return "extension";
        }
    }

    Component.onCompleted: checkUpdates()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // ── 摘要：单行信息 + 右侧操作 ──
        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: summaryRow.implicitHeight + Tokens.padding.large * 2

            RowLayout {
                id: summaryRow
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: root.checking ? "sync" : root.errorText ? "error" : root.updateCount > 0 ? "system_update_alt" : "verified"
                    color: root.errorText
                        ? Colours.palette.m3error
                        : root.updateCount > 0
                          ? Colours.palette.m3primary
                          : Colours.palette.m3secondary
                    fontStyle: Tokens.font.icon.large

                    RotationAnimator on rotation {
                        running: root.checking
                        from: 0
                        to: 360
                        duration: 900
                        loops: Animation.Infinite
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: root.checking
                            ? qsTr("Checking for updates...")
                            : root.errorText
                              ? qsTr("Update check failed")
                              : root.updateCount > 0
                                ? qsTr("%1 components can be installed or updated").arg(root.updateCount)
                                : qsTr("Everything is up to date")
                        font: Tokens.font.body.large
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.errorText || (root.lastChecked ? qsTr("Last checked %1").arg(root.lastChecked) : qsTr("Villode release channel"))
                        color: root.errorText ? Colours.palette.m3error : Colours.palette.m3outline
                        font: Tokens.font.label.small
                        elide: Text.ElideRight
                    }
                }

                IconTextButton {
                    icon: "refresh"
                    text: root.checking ? qsTr("Checking") : qsTr("Check")
                    type: IconTextButton.Tonal
                    enabled: !root.checking
                    onClicked: root.checkUpdates()
                }

                IconTextButton {
                    icon: "system_update"
                    text: root.actionLabel()
                    type: IconTextButton.Filled
                    enabled: !root.checking && root.updateCount > 0
                    onClicked: root.launchUpdate()
                }
            }
        }

        SectionHeader {
            text: qsTr("Components")
        }

        // ── 组件列表：折叠行 + 展开详情 ──
        Repeater {
            model: root.components

            ConnectedRect {
                id: card

                required property var modelData
                required property int index

                property bool expanded: root.hasUpdate(modelData.status)

                Layout.fillWidth: true
                first: card.index === 0
                last: card.index === root.components.length - 1
                implicitHeight: cardCol.implicitHeight + Tokens.padding.medium * 2

                ColumnLayout {
                    id: cardCol
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.small

                    // 主行：点整行展开
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: mainRow.implicitHeight

                        StateLayer {
                            anchors.fill: parent
                            radius: Tokens.rounding.medium
                            onClicked: card.expanded = !card.expanded
                        }

                        RowLayout {
                            id: mainRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: Tokens.spacing.medium

                            MaterialIcon {
                                text: root.componentIcon(card.modelData.id)
                                color: root.statusColour(card.modelData.status)
                                fontStyle: Tokens.font.icon.medium
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    text: card.modelData.name
                                    font: Tokens.font.body.small
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: {
                                        if (card.modelData.status === "未安装")
                                            return card.modelData.latest && card.modelData.latest !== "—"
                                                ? qsTr("Available %1").arg(card.modelData.latest)
                                                : qsTr("Not installed");
                                        if (card.modelData.installed === card.modelData.latest)
                                            return qsTr("Version %1").arg(card.modelData.installed);
                                        return `${card.modelData.installed} → ${card.modelData.latest}`;
                                    }
                                    color: Colours.palette.m3outline
                                    font: Tokens.font.label.small
                                    elide: Text.ElideRight
                                }
                            }

                            StyledText {
                                text: root.statusLabel(card.modelData.status)
                                color: root.statusColour(card.modelData.status)
                                font: Tokens.font.label.medium
                            }

                            MaterialIcon {
                                text: card.expanded ? "expand_less" : "expand_more"
                                color: Colours.palette.m3onSurfaceVariant
                                fontStyle: Tokens.font.icon.small
                            }
                        }
                    }

                    // 详情：时间 + 变更（仅展开时）
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: Tokens.font.icon.medium.pointSize + Tokens.spacing.medium
                        spacing: Tokens.spacing.extraSmall
                        visible: card.expanded

                        // 时间键值
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.large

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.small

                                StyledText {
                                    text: qsTr("Last updated")
                                    color: Colours.palette.m3outline
                                    font: Tokens.font.label.small
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.formatDateTime(card.modelData.installedAt) || "—"
                                    font: Tokens.font.label.small
                                    elide: Text.ElideRight
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.small

                                StyledText {
                                    text: qsTr("Latest release")
                                    color: Colours.palette.m3outline
                                    font: Tokens.font.label.small
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.formatDateTime(card.modelData.releasedAt) || "—"
                                    font: Tokens.font.label.small
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        // 分隔
                        StyledRect {
                            Layout.fillWidth: true
                            Layout.topMargin: Tokens.spacing.extraSmall
                            Layout.bottomMargin: Tokens.spacing.extraSmall
                            implicitHeight: 1
                            color: Colours.palette.m3outlineVariant
                            opacity: 0.45
                        }

                        StyledText {
                            text: card.modelData.status === "未安装"
                                ? qsTr("Component information")
                                : root.hasUpdate(card.modelData.status) ? qsTr("Changes in this update") : qsTr("Recent changes")
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                        }

                        Repeater {
                            model: card.modelData.changes

                            RowLayout {
                                required property string modelData
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.small

                                StyledText {
                                    Layout.alignment: Qt.AlignTop
                                    text: "•"
                                    color: root.statusColour(card.modelData.status)
                                    font: Tokens.font.body.small
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: parent.modelData
                                    color: Colours.palette.m3onSurfaceVariant
                                    font: Tokens.font.body.small
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        StyledText {
                            visible: !card.modelData.changes || card.modelData.changes.length === 0
                            text: qsTr("No change notes")
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                        }
                    }
                }
            }
        }

        StyledText {
            visible: root.checkedOnce && root.components.length === 0 && !root.checking
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.large
            text: root.errorText || qsTr("No installed Villode components were detected.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.medium
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.large
            Layout.maximumWidth: root.cappedWidth * 0.9
            text: qsTr("Install missing components or update installed ones. Only versions locked by the release manifest are used, and user configuration is preserved. Select a component for details.")
            color: Colours.palette.m3outline
            font: Tokens.font.label.small
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }
}
