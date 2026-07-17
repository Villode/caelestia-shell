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
    property string channelSource: ""
    property bool networkDegraded: false
    property string lastStderr: ""
    // System package (Arch rolling) section — separate from Villode components.
    property list<var> systemPackages: []
    property int systemPackageCount: 0
    property bool systemTruncated: false
    property list<string> systemRisky: []
    property string systemWarning: ""
    property string systemSummary: ""
    property bool systemChecking: false
    property string systemError: ""
    property string systemLastChecked: ""
    property bool systemExpanded: false
    readonly property int updateCount: components.filter(item => item.status === "有更新" || item.status === "需要修复" || item.status === "未安装").length

    title: qsTr("Villode updates")

    property Process checkProcess: Process {
        id: checkProcess
        // Bound the whole check so a stuck git never freezes the settings UI.
        // The updater itself also applies per-attempt git timeouts + mirrors.
        command: ["timeout", "--signal=TERM", "--kill-after=5", "90", "villode-caelestia-update", "--check-json"]
        stdout: StdioCollector {
            onStreamFinished: root.parseUpdatesJson(text)
        }
        stderr: StdioCollector {
            onStreamFinished: root.lastStderr = text.trim()
        }
        onExited: code => { // qmllint disable signal-handler-parameters
            root.checking = false;
            if (code === 0)
                return;
            if (code === 124 || code === 137)
                root.errorText = qsTr("Update check timed out. GitHub may be slow or unreachable; try again later or configure a mirror (VILLODE_GITHUB_MIRRORS).");
            else if (root.lastStderr)
                root.errorText = root.lastStderr;
            else
                root.errorText = qsTr("Could not check for updates. Check your network connection, or set VILLODE_GITHUB_MIRRORS / use offline mode.");
        }
    }

    property Process systemCheckProcess: Process {
        id: systemCheckProcess
        command: ["timeout", "--signal=TERM", "--kill-after=5", "120", "villode-system-update", "--check-json"]
        stdout: StdioCollector {
            onStreamFinished: root.parseSystemJson(text)
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    root.systemError = text.trim();
            }
        }
        onExited: code => { // qmllint disable signal-handler-parameters
            root.systemChecking = false;
            if (code === 0)
                return;
            if (code === 124 || code === 137)
                root.systemError = qsTr("System package check timed out. Network or package mirrors may be slow.");
            else if (!root.systemError)
                root.systemError = qsTr("Could not check system packages. Is pacman available?");
        }
    }

    function checkUpdates(): void {
        if (checkProcess.running)
            return;
        root.checking = true;
        root.errorText = "";
        root.lastStderr = "";
        root.networkDegraded = false;
        checkProcess.running = true;
        root.checkSystemUpdates();
    }

    function checkSystemUpdates(): void {
        if (systemCheckProcess.running)
            return;
        root.systemChecking = true;
        root.systemError = "";
        systemCheckProcess.running = true;
    }

    function launchUpdate(): void {
        const terminal = [...GlobalConfig.general.apps.terminal];
        // The updater only syncs installed components by default; the button is
        // labelled "Install" when 未安装 rows exist, so opt into installing them.
        const hasMissing = root.components.some(item => item.status === "未安装");
        const updateCmd = hasMissing ? "villode-caelestia-update --install-missing" : "villode-caelestia-update";
        const banner = "echo '【Villode 组件更新】只同步锁定组件，不会执行 pacman -Syu 系统滚动更新。'; echo '[Villode components] Locked components only — not a full system upgrade.'; echo;";
        Quickshell.execDetached([Quickshell.shellPath("assets/villode_terminal_exec.sh"), String(terminal.length), ...terminal, "--", "sh", "-lc", banner + updateCmd + "; code=$?; echo; if [ $code -eq 0 ]; then echo '组件更新完成。'; else echo '组件更新失败，退出码：'$code; fi; echo '按回车键关闭…'; read -r; exit $code"]);
    }

    function launchSystemUpdate(): void {
        const terminal = [...GlobalConfig.general.apps.terminal];
        const cmd = "villode-system-update --apply";
        Quickshell.execDetached([Quickshell.shellPath("assets/villode_terminal_exec.sh"), String(terminal.length), ...terminal, "--", "sh", "-lc", cmd + "; code=$?; echo; echo '按回车键关闭…'; read -r; exit $code"]);
    }

    function parseSystemJson(text: string): void {
        try {
            const data = JSON.parse(text);
            const rows = [];
            for (const p of (data.packages || [])) {
                rows.push({
                    name: p.name || "",
                    old: p.old || "—",
                    new: p.new || "—"
                });
            }
            root.systemPackages = rows;
            root.systemPackageCount = data.packageCount || rows.length;
            root.systemTruncated = !!data.truncated;
            root.systemRisky = Array.isArray(data.riskyPackages) ? data.riskyPackages : [];
            root.systemWarning = data.warningZh || data.warning || "";
            root.systemSummary = data.summaryZh || data.summary || "";
            root.systemLastChecked = root.formatDateTime(data.checkedAt) || Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm");
            root.systemError = "";
            if (root.systemPackageCount > 0)
                root.systemExpanded = true;
        } catch (e) {
            root.systemError = qsTr("Could not parse system package list.");
        }
    }

    function channelSourceLabel(source: string): string {
        switch (source) {
        case "online-github":
            return qsTr("GitHub");
        case "online-mirror":
            return qsTr("GitHub mirror");
        case "stale-cache":
            return qsTr("Local cache (GitHub unreachable)");
        case "offline-cache":
            return qsTr("Offline cache");
        case "offline-release":
            return qsTr("Installed release channel");
        default:
            return source ? source : qsTr("Villode release channel");
        }
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
            root.channelSource = data.channelSource || "";
            root.networkDegraded = !!data.networkDegraded;
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

    function summaryHint(): string {
        if (root.errorText)
            return root.errorText;
        const source = root.channelSourceLabel(root.channelSource);
        const shellUp = root.components.some(item => item.id === "shell" && (item.status === "有更新" || item.status === "需要修复"));
        const cursorUp = root.components.some(item => item.id === "cursor" && (item.status === "有更新" || item.status === "需要修复"));
        let note = "";
        if (shellUp && cursorUp)
            note = qsTr("Shell and cursor share one pin — one update covers both");
        if (root.lastChecked) {
            const base = root.networkDegraded
                ? qsTr("Last checked %1 · %2").arg(root.lastChecked).arg(source)
                : qsTr("Last checked %1 · source %2").arg(root.lastChecked).arg(source);
            return note ? `${base} · ${note}` : base;
        }
        return note || source;
    }

    function componentBlurb(item: var): string {
        if (item.status === "未安装")
            return item.latest && item.latest !== "—"
                ? qsTr("Available %1").arg(item.latest)
                : qsTr("Not installed");
        if (item.installed === item.latest)
            return qsTr("Version %1").arg(item.installed);
        let line = `${item.installed} → ${item.latest}`;
        if (item.id === "cursor")
            line = qsTr("%1 (ships with Shell)").arg(line);
        return line;
    }

    function changeLines(item: var): var {
        const list = Array.isArray(item.changes) ? item.changes.slice() : [];
        if (list.length > 0)
            return list;
        if (item.status === "有更新" || item.status === "需要修复")
            return [qsTr("No detailed changelog offline; version pin will update from %1 to %2").arg(item.installed || "—").arg(item.latest || "—")];
        if (item.status === "未安装")
            return [qsTr("Not installed yet")];
        return [qsTr("No change notes")];
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
                        text: root.summaryHint()
                        color: root.errorText ? Colours.palette.m3error : (root.networkDegraded ? Colours.palette.m3tertiary : Colours.palette.m3outline)
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
            text: qsTr("Villode components")
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.largeIncreased
            Layout.rightMargin: Tokens.padding.largeIncreased
            text: qsTr("Component updates only change Villode Shell / Dock / … to versions locked by the release channel. They do not run pacman -Syu.")
            color: Colours.palette.m3outline
            font: Tokens.font.label.small
            wrapMode: Text.WordWrap
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
                                    text: root.componentBlurb(card.modelData)
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
                            model: root.changeLines(card.modelData)

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

        // ── 系统软件包（Arch 滚动，与组件更新分离）──
        SectionHeader {
            text: qsTr("System packages")
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: sysCol.implicitHeight + Tokens.padding.large * 2

            ColumnLayout {
                id: sysCol
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: root.systemChecking ? "sync" : root.systemError ? "error" : root.systemPackageCount > 0 ? "package_2" : "verified"
                        color: root.systemError
                            ? Colours.palette.m3error
                            : root.systemPackageCount > 0
                              ? Colours.palette.m3tertiary
                              : Colours.palette.m3secondary
                        fontStyle: Tokens.font.icon.large

                        RotationAnimator on rotation {
                            running: root.systemChecking
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
                            text: root.systemChecking
                                ? qsTr("Checking system packages...")
                                : root.systemError
                                  ? qsTr("System package check failed")
                                  : root.systemPackageCount > 0
                                    ? qsTr("%1 system packages can be upgraded").arg(root.systemPackageCount)
                                    : qsTr("System packages appear up to date")
                            font: Tokens.font.body.large
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.systemError || root.systemSummary || qsTr("Arch rolling: pacman -Syu (separate from Villode components)")
                            color: root.systemError ? Colours.palette.m3error : Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    IconTextButton {
                        icon: "refresh"
                        text: root.systemChecking ? qsTr("Checking") : qsTr("Check")
                        type: IconTextButton.Tonal
                        enabled: !root.systemChecking
                        onClicked: root.checkSystemUpdates()
                    }

                    IconTextButton {
                        icon: "upgrade"
                        text: root.systemPackageCount > 0
                            ? qsTr("System upgrade (%1)").arg(root.systemPackageCount)
                            : qsTr("System upgrade")
                        type: IconTextButton.Filled
                        enabled: !root.systemChecking
                        onClicked: root.launchSystemUpdate()
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.systemWarning.length > 0 || root.systemPackageCount > 0
                    text: root.systemWarning || qsTr("Full system upgrade may include kernel, drivers and core libraries. Review the package list in the terminal before confirming.")
                    color: Colours.palette.m3tertiary
                    font: Tokens.font.label.small
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.systemRisky.length > 0
                    text: qsTr("Notable packages: %1").arg(root.systemRisky.slice(0, 12).join(", ") + (root.systemRisky.length > 12 ? "…" : ""))
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                    wrapMode: Text.WordWrap
                }

                // Toggle package list
                Item {
                    Layout.fillWidth: true
                    implicitHeight: toggleRow.implicitHeight
                    visible: root.systemPackageCount > 0

                    StateLayer {
                        anchors.fill: parent
                        radius: Tokens.rounding.medium
                        onClicked: root.systemExpanded = !root.systemExpanded
                    }

                    RowLayout {
                        id: toggleRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: Tokens.spacing.small

                        StyledText {
                            Layout.fillWidth: true
                            text: root.systemExpanded
                                ? qsTr("Hide package list")
                                : qsTr("Show package list (%1)").arg(root.systemPackageCount)
                            color: Colours.palette.m3primary
                            font: Tokens.font.label.medium
                        }

                        MaterialIcon {
                            text: root.systemExpanded ? "expand_less" : "expand_more"
                            color: Colours.palette.m3primary
                            fontStyle: Tokens.font.icon.small
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall
                    visible: root.systemExpanded && root.systemPackages.length > 0

                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: Colours.palette.m3outlineVariant
                        opacity: 0.45
                    }

                    Repeater {
                        model: root.systemPackages

                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.small

                            StyledText {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                text: parent.modelData.name
                                font: Tokens.font.label.medium
                                elide: Text.ElideRight
                            }

                            StyledText {
                                text: `${parent.modelData.old} → ${parent.modelData.new}`
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.small
                                elide: Text.ElideRight
                            }
                        }
                    }

                    StyledText {
                        visible: root.systemTruncated
                        text: qsTr("List truncated in the UI; full list is shown in the terminal before upgrade.")
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                    }

                    StyledText {
                        visible: root.systemLastChecked.length > 0
                        text: qsTr("Last checked %1").arg(root.systemLastChecked)
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                    }
                }
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.medium
            Layout.maximumWidth: root.cappedWidth * 0.9
            text: qsTr("System upgrade runs sudo pacman -Syu in a terminal and asks for confirmation. It is optional and independent of Villode component updates.")
            color: Colours.palette.m3outline
            font: Tokens.font.label.small
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }
}
