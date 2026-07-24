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

// Phone-style software update: hero + always-visible component list + system card + in-page progress dialog.
PageBase {
    id: root

    property list<var> components: []
    property bool checking
    property bool checkedOnce
    property string errorText
    property string lastChecked
    property string channelSource: ""
    property bool networkDegraded: false
    property string lastStderr: ""

    property list<var> systemPackages: []
    property int systemPackageCount: 0
    property bool systemTruncated: false
    property list<string> systemRisky: []
    property bool systemChecking: false
    property string systemError: ""
    property string systemLastChecked: ""
    property bool systemListOpen: true

    // In-page update dialog (no terminal)
    property bool updateDialogOpen: false
    onUpdateDialogOpenChanged: {
        if (root.flickable)
            root.flickable.interactive = !root.updateDialogOpen;
        if (!root.updateDialogOpen && root.flickable)
            root.flickable.interactive = true;
    }
    property string updateDialogKind: "" // villode | system
    property string updateDialogTitle: ""
    property string updateDialogDetail: ""
    property string updateDialogLog: ""
    property real updateDialogProgress: -1
    property bool updateDialogRunning: false
    property bool updateDialogDone: false
    property bool updateDialogFailed: false
    property int updateDialogDoneCount: 0
    property int updateDialogTotalHint: 0

    readonly property int updateCount: components.filter(item => root.hasUpdate(item.status)).length
    readonly property int totalPending: updateCount + systemPackageCount
    readonly property bool busy: checking || systemChecking || updateDialogRunning

    title: qsTr("Software update")

    property Process checkProcess: Process {
        id: checkProcess
        command: ["timeout", "--signal=TERM", "--kill-after=5", "90", "villode-caelestia-update", "--check-json"]
        stdout: StdioCollector {
            onStreamFinished: root.parseUpdatesJson(text)
        }
        stderr: StdioCollector {
            onStreamFinished: root.lastStderr = text.trim()
        }
        onExited: code => {
            root.checking = false;
            if (code === 0)
                return;
            if (code === 124 || code === 137)
                root.errorText = qsTr("Check timed out. Network may be slow.");
            else if (root.lastStderr)
                root.errorText = root.lastStderr.split("\n").filter(l => l.trim()).slice(-1)[0] || root.lastStderr;
            else
                root.errorText = qsTr("Could not check for updates.");
            if (root.components.length === 0)
                root.seedPlaceholderComponents();
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
                    root.systemError = text.trim().split("\n").filter(l => l.trim()).slice(-1)[0] || text.trim();
            }
        }
        onExited: code => {
            root.systemChecking = false;
            if (code === 0)
                return;
            if (code === 124 || code === 137)
                root.systemError = qsTr("System check timed out.");
            else if (!root.systemError)
                root.systemError = qsTr("Could not check system packages.");
        }
    }

    property Process applyProcess: Process {
        id: applyProcess
        command: ["true"]
        running: false
        environment: ({
                LANG: "C.UTF-8",
                LC_ALL: "C.UTF-8",
                TERM: "dumb"
            })
        stdout: SplitParser {
            onRead: line => root.onApplyLine(line)
        }
        stderr: SplitParser {
            onRead: line => root.onApplyLine(line)
        }
        onExited: code => {
            root.updateDialogRunning = false;
            root.updateDialogDone = true;
            if (code === 0) {
                root.updateDialogFailed = false;
                root.updateDialogProgress = 100;
                root.updateDialogDetail = qsTr("Finished");
                root.appendLog(qsTr("Done."));
                root.checkUpdates();
            } else {
                root.updateDialogFailed = true;
                root.updateDialogDetail = qsTr("Failed (exit %1)").arg(code);
                root.appendLog(qsTr("Failed, exit code %1").arg(code));
            }
        }
    }

    function checkUpdates(): void {
        if (checkProcess.running)
            return;
        root.checking = true;
        root.errorText = "";
        root.lastStderr = "";
        root.networkDegraded = false;
        if (root.components.length === 0)
            root.seedPlaceholderComponents();
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

    function seedPlaceholderComponents(): void {
        const ids = [
            ["shell", qsTr("Desktop shell")],
            ["zh", qsTr("Chinese language pack")],
            ["dock", qsTr("Dock")],
            ["desktop", qsTr("Desktop")],
            ["launcher", qsTr("Launcher")],
            ["cursor", qsTr("Pointer zoom")]
        ];
        const rows = [];
        for (const pair of ids) {
            rows.push({
                id: pair[0],
                name: pair[1],
                installed: "—",
                latest: "—",
                installedFull: "",
                latestFull: "",
                status: qsTr("Checking…"),
                installedAt: "",
                releasedAt: "",
                changes: []
            });
        }
        root.components = rows;
    }

    function openUpdateDialog(kind: string): void {
        if (root.updateDialogRunning)
            return;
        root.updateDialogKind = kind;
        root.updateDialogOpen = true;
        root.updateDialogRunning = false;
        root.updateDialogDone = false;
        root.updateDialogFailed = false;
        root.updateDialogProgress = -1;
        root.updateDialogLog = "";
        root.updateDialogDoneCount = 0;
        root.updateDialogTotalHint = kind === "system" ? root.systemPackageCount : root.updateCount;
        if (kind === "system") {
            root.updateDialogTitle = qsTr("System upgrade");
            root.updateDialogDetail = qsTr("Review packages, then start. Polkit may ask for your password.");
        } else {
            root.updateDialogTitle = qsTr("Update Villode");
            root.updateDialogDetail = qsTr("Updates desktop components only — not a full system upgrade.");
        }
    }

    function closeUpdateDialog(): void {
        if (root.updateDialogRunning)
            return;
        root.updateDialogOpen = false;
    }

    function startUpdateFromDialog(): void {
        if (root.updateDialogRunning)
            return;
        root.updateDialogRunning = true;
        root.updateDialogDone = false;
        root.updateDialogFailed = false;
        root.updateDialogProgress = 0;
        root.updateDialogLog = "";
        root.updateDialogDoneCount = 0;
        root.appendLog(qsTr("Starting…"));

        if (root.updateDialogKind === "system") {
            root.updateDialogDetail = qsTr("Running system upgrade…");
            root.updateDialogTotalHint = Math.max(1, root.systemPackageCount);
            applyProcess.command = ["villode-system-update", "--apply", "--yes"];
        } else {
            root.updateDialogDetail = qsTr("Updating Villode components…");
            const hasMissing = root.components.some(item => item.status === "未安装");
            applyProcess.command = hasMissing
                ? ["villode-caelestia-update", "--install-missing"]
                : ["villode-caelestia-update"];
            root.updateDialogTotalHint = Math.max(1, root.updateCount || root.components.length);
        }
        applyProcess.running = true;
    }

    function appendLog(line: string): void {
        const t = String(line || "").trim();
        if (!t)
            return;
        const prev = root.updateDialogLog;
        const next = prev ? (prev + "\n" + t) : t;
        // keep last ~40 lines
        const lines = next.split("\n");
        root.updateDialogLog = lines.slice(Math.max(0, lines.length - 40)).join("\n");
    }

    function onApplyLine(line: string): void {
        const s = String(line || "").replace(/\r/g, "").trim();
        if (!s)
            return;
        root.appendLog(s);

        if (s.startsWith("VILLODE_PROGRESS ")) {
            if (s.includes("phase=auth"))
                root.updateDialogDetail = qsTr("Waiting for password…");
            else if (s.includes("phase=upgrade"))
                root.updateDialogDetail = qsTr("Installing packages…");
            else if (s.includes("phase=done")) {
                root.updateDialogProgress = 100;
                root.updateDialogDetail = qsTr("Finished");
            } else if (s.includes("phase=failed"))
                root.updateDialogDetail = qsTr("Failed");
            else if (s.includes("phase=list")) {
                const m = s.match(/count=(\d+)/);
                if (m)
                    root.updateDialogTotalHint = Math.max(1, parseInt(m[1], 10) || 1);
            }
            return;
        }

        // pacman: (3/120) upgrading foo
        let m = s.match(/^\((\d+)\/(\d+)\)/);
        if (m) {
            const cur = parseInt(m[1], 10);
            const tot = parseInt(m[2], 10);
            root.updateDialogDoneCount = cur;
            root.updateDialogTotalHint = tot;
            if (tot > 0)
                root.updateDialogProgress = Math.min(99, Math.round((cur / tot) * 100));
            root.updateDialogDetail = s;
            return;
        }
        if (/^downloading\b/i.test(s) || s.includes("正在下载")) {
            root.updateDialogDetail = s;
            if (root.updateDialogProgress < 0)
                root.updateDialogProgress = 5;
            return;
        }
        if (/^installing\b|^upgrading\b|^removing\b/i.test(s) || s.includes("正在升级") || s.includes("正在安装")) {
            root.updateDialogDetail = s;
            if (root.updateDialogProgress >= 0 && root.updateDialogProgress < 95)
                root.updateDialogProgress = Math.min(95, root.updateDialogProgress + 1);
            return;
        }
        // villode component lines
        if (s.includes("更新") || s.includes("同步") || s.includes("安装") || /update|sync|install/i.test(s)) {
            root.updateDialogDetail = s;
            if (root.updateDialogProgress < 0)
                root.updateDialogProgress = 10;
            else if (root.updateDialogProgress < 90)
                root.updateDialogProgress = Math.min(90, root.updateDialogProgress + 3);
        }
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
            root.systemLastChecked = root.formatDateTime(data.checkedAt) || Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm");
            root.systemError = "";
            if (root.systemPackageCount > 0)
                root.systemListOpen = true;
        } catch (e) {
            root.systemError = qsTr("Could not parse system package list.");
        }
    }

    function channelSourceLabel(source: string): string {
        switch (source) {
        case "online-github":
            return qsTr("Online");
        case "online-mirror":
            return qsTr("Mirror");
        case "stale-cache":
            return qsTr("Cached (offline)");
        case "offline-cache":
            return qsTr("Offline cache");
        case "offline-release":
            return qsTr("Installed channel");
        default:
            return qsTr("Release channel");
        }
    }

    function parseUpdatesJson(text: string): void {
        try {
            const data = JSON.parse(text);
            const rows = [];
            for (const c of (data.components || [])) {
                rows.push({
                    id: c.id || "",
                    name: root.componentDisplayName(c.id, c.name),
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
            root.components = rows.length ? rows : root.components;
            if (rows.length === 0)
                root.seedPlaceholderComponents();
            root.checkedOnce = true;
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
                name: root.componentDisplayName(fields[0], fields[1]),
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
        if (rows.length)
            root.components = rows;
        else if (root.components.length === 0)
            root.seedPlaceholderComponents();
        root.checkedOnce = true;
        root.lastChecked = Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm");
    }

    function componentDisplayName(id: string, fallback: string): string {
        switch (id) {
        case "shell":
            return qsTr("Desktop shell");
        case "zh":
            return qsTr("Chinese language pack");
        case "dock":
            return qsTr("Dock");
        case "desktop":
            return qsTr("Desktop");
        case "launcher":
            return qsTr("Launcher");
        case "cursor":
            return qsTr("Pointer zoom");
        default:
            return fallback || id || qsTr("Component");
        }
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
            return qsTr("Needs repair");
        if (status === "未安装")
            return qsTr("Not installed");
        if (status === "已是最新")
            return qsTr("Up to date");
        if (status === qsTr("Checking…") || status === "Checking…")
            return qsTr("Checking…");
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

    function heroTitle(): string {
        if (root.updateDialogRunning)
            return qsTr("Updating…");
        if (root.busy)
            return qsTr("Checking for updates…");
        if (root.errorText && root.updateCount <= 0 && root.systemPackageCount <= 0)
            return qsTr("Could not check");
        if (root.totalPending > 0)
            return qsTr("%1 updates available").arg(root.totalPending);
        return qsTr("You're up to date");
    }

    function heroSubtitle(): string {
        if (root.updateDialogRunning)
            return root.updateDialogDetail || qsTr("Please wait");
        if (root.busy)
            return qsTr("Please wait");
        if (root.errorText && root.totalPending <= 0)
            return root.errorText;
        const parts = [];
        if (root.updateCount > 0)
            parts.push(qsTr("%1 Villode").arg(root.updateCount));
        if (root.systemPackageCount > 0)
            parts.push(qsTr("%1 system").arg(root.systemPackageCount));
        if (parts.length)
            return parts.join(" · ");
        if (root.lastChecked)
            return qsTr("Last checked %1").arg(root.lastChecked);
        return qsTr("Use Check to refresh");
    }

    function componentListRight(item: var): string {
        // Compact right column like system package "old → new"
        if (!item)
            return "";
        const st = item.status || "";
        if (st === "有更新" || st === "需要修复") {
            if (item.installed && item.latest && item.installed !== "—" && item.latest !== "—")
                return `${item.installed} → ${item.latest}`;
            return root.statusLabel(st);
        }
        if (st === "未安装") {
            if (item.latest && item.latest !== "—")
                return item.latest;
            return root.statusLabel(st);
        }
        if (item.installed && item.installed !== "—")
            return item.installed;
        return root.statusLabel(st);
    }

    function componentBlurb(item: var): string {
        if (item.status === "未安装")
            return item.latest && item.latest !== "—" ? qsTr("Available %1").arg(item.latest) : qsTr("Not installed");
        if (item.installed === item.latest || item.status === "已是最新")
            return qsTr("Version %1").arg(item.installed);
        if (item.id === "cursor")
            return qsTr("%1 → %2 · with shell").arg(item.installed).arg(item.latest);
        if (item.installed === "—" && item.latest === "—")
            return qsTr("Checking…");
        return `${item.installed} → ${item.latest}`;
    }

    function changeLines(item: var): var {
        const list = Array.isArray(item.changes) ? item.changes.slice() : [];
        if (list.length > 0)
            return list;
        if (item.status === "有更新" || item.status === "需要修复")
            return [qsTr("Updates to version %1").arg(item.latest || "—")];
        if (item.status === "未安装")
            return [qsTr("Not installed yet")];
        if (item.status === "已是最新")
            return [qsTr("Already on the latest release channel version")];
        return [qsTr("No details")];
    }

    function componentIcon(id: string): string {
        switch (id) {
        case "shell":
            return "widgets";
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


    function riskyPreview(): string {
        const list = root.systemRisky;
        const n = Math.min(8, list.length);
        let parts = [];
        for (let i = 0; i < n; ++i)
            parts.push(list[i]);
        return parts.join(", ") + (list.length > 8 ? "…" : "");
    }

    function systemPackagesPreview() {
        const src = root.systemPackages;
        const n = Math.min(40, src.length);
        let out = [];
        for (let i = 0; i < n; ++i)
            out.push(src[i]);
        return out;
    }


    Component.onCompleted: {
        root.seedPlaceholderComponents();
        root.checkUpdates();
    }

    // Single contentChild for PageBase — fill flickable width, center capped content
    Item {
        id: pageBody
        // Match flickable viewport width so content can center (no empty strip only on one side)
        width: Math.max(root.flickable.width, root.cappedWidth)
        implicitHeight: contentCol.implicitHeight

        ColumnLayout {
            id: contentCol
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: root.cappedWidth
            spacing: Tokens.spacing.medium

            ConnectedRect {
                Layout.fillWidth: true
                first: true
                last: true
                implicitHeight: heroCol.implicitHeight + Tokens.padding.extraLarge * 2

                ColumnLayout {
                    id: heroCol
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.extraLarge
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.busy ? "sync" : root.totalPending > 0 ? "system_update_alt" : root.errorText ? "error" : "check_circle"
                        color: root.errorText && root.totalPending <= 0
                            ? Colours.palette.m3error
                            : root.totalPending > 0
                              ? Colours.palette.m3primary
                              : Colours.palette.m3secondary
                        fontStyle: Tokens.font.icon.builders.large.scale(2.2).build()

                        RotationAnimator on rotation {
                            running: root.busy
                            from: 0
                            to: 360
                            duration: 900
                            loops: Animation.Infinite
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        text: root.heroTitle()
                        font: Tokens.font.headline.small
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        text: root.heroSubtitle()
                        color: Colours.palette.m3outline
                        font: Tokens.font.body.medium
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: Tokens.spacing.small
                        spacing: Tokens.spacing.small

                        IconTextButton {
                            icon: "refresh"
                            text: qsTr("Check")
                            type: IconTextButton.Tonal
                            enabled: !root.busy
                            onClicked: root.checkUpdates()
                        }

                        IconTextButton {
                            visible: root.updateCount > 0
                            icon: "download"
                            text: qsTr("Update Villode")
                            type: IconTextButton.Filled
                            enabled: !root.busy
                            onClicked: root.openUpdateDialog("villode")
                        }
                    }
                }
            }

            SectionHeader {
                text: qsTr("Villode")
            }

            // Same card style as system: header + simple list rows
            ConnectedRect {
                Layout.fillWidth: true
                first: true
                last: true
                implicitHeight: villodeCol.implicitHeight + Tokens.padding.large * 2

                ColumnLayout {
                    id: villodeCol
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.medium

                        MaterialIcon {
                            text: "widgets"
                            color: root.updateCount > 0 ? Colours.palette.m3primary : Colours.palette.m3outline
                            fontStyle: Tokens.font.icon.large
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: qsTr("Desktop components")
                                font: Tokens.font.body.large
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.updateCount > 0
                                    ? qsTr("%1 items · safe component update").arg(root.updateCount)
                                    : qsTr("Shell, dock, launcher and more")
                                color: Colours.palette.m3outline
                                font: Tokens.font.label.small
                                elide: Text.ElideRight
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        IconTextButton {
                            icon: "refresh"
                            text: qsTr("Check")
                            type: IconTextButton.Tonal
                            enabled: !root.busy
                            onClicked: root.checkUpdates()
                        }

                        IconTextButton {
                            visible: root.updateCount > 0
                            icon: "download"
                            text: qsTr("Update Villode")
                            type: IconTextButton.Filled
                            enabled: !root.busy
                            onClicked: root.openUpdateDialog("villode")
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        StyledText {
                            text: root.updateCount > 0 ? qsTr("%1 new").arg(root.updateCount) : qsTr("OK")
                            color: root.updateCount > 0 ? Colours.palette.m3primary : Colours.palette.m3outline
                            font: Tokens.font.label.medium
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.extraSmall
                        visible: root.components.length > 0

                        StyledRect {
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: Colours.palette.m3outlineVariant
                            opacity: 0.45
                        }

                        Repeater {
                            model: root.components

                            RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.small

                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    font: Tokens.font.label.medium
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    text: root.componentListRight(modelData)
                                    color: root.statusColour(modelData.status)
                                    font: Tokens.font.label.small
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: root.cappedWidth * 0.42
                                    horizontalAlignment: Text.AlignRight
                                }
                            }
                        }
                    }
                }
            }

            SectionHeader {
                text: qsTr("System")
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
                    spacing: Tokens.spacing.medium

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.medium

                        MaterialIcon {
                            text: root.systemChecking ? "sync" : root.systemPackageCount > 0 ? "package_2" : "verified"
                            color: root.systemError
                                ? Colours.palette.m3error
                                : root.systemPackageCount > 0
                                  ? Colours.palette.m3tertiary
                                  : Colours.palette.m3outline
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
                                text: qsTr("System packages")
                                font: Tokens.font.body.large
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.systemChecking
                                    ? qsTr("Checking…")
                                    : root.systemError
                                      ? root.systemError
                                      : root.systemPackageCount > 0
                                        ? qsTr("%1 packages · full system upgrade").arg(root.systemPackageCount)
                                        : qsTr("No system upgrades found")
                                color: root.systemError ? Colours.palette.m3error : Colours.palette.m3outline
                                font: Tokens.font.label.small
                                elide: Text.ElideRight
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.systemPackageCount > 0
                        text: qsTr("May include kernel, drivers and libraries. You will confirm in a dialog — no terminal.")
                        color: Colours.palette.m3tertiary
                        font: Tokens.font.label.small
                        wrapMode: Text.WordWrap
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.systemRisky.length > 0
                        text: qsTr("Includes: %1").arg(root.riskyPreview())
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                        wrapMode: Text.WordWrap
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        IconTextButton {
                            icon: "refresh"
                            text: qsTr("Check")
                            type: IconTextButton.Tonal
                            enabled: !root.systemChecking && !root.updateDialogRunning
                            onClicked: root.checkSystemUpdates()
                        }

                        IconTextButton {
                            icon: "upgrade"
                            text: qsTr("Upgrade system")
                            type: IconTextButton.Filled
                            enabled: !root.systemChecking && !root.updateDialogRunning
                            onClicked: root.openUpdateDialog("system")
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        IconTextButton {
                            visible: root.systemPackages.length > 0
                            icon: root.systemListOpen ? "expand_less" : "expand_more"
                            text: root.systemListOpen ? qsTr("Hide") : qsTr("List")
                            type: IconTextButton.Text
                            onClicked: root.systemListOpen = !root.systemListOpen
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.extraSmall
                        visible: root.systemListOpen && root.systemPackages.length > 0

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
                            text: qsTr("List truncated; full set will install during upgrade.")
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                        }
                    }
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Tokens.spacing.small
                Layout.maximumWidth: root.cappedWidth * 0.92
                text: qsTr("Villode updates only your desktop components. System upgrade is optional and separate.")
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }

        // Fixed-viewport modal (scroll locked while open)
        Item {
            id: updateDialogLayer
            z: 100000
            visible: root.updateDialogOpen
            enabled: root.updateDialogOpen
            // Pin to visible flickable viewport within content coordinates
            x: root.flickable ? root.flickable.contentX : 0
            y: root.flickable ? root.flickable.contentY : 0
            width: root.flickable ? root.flickable.width : pageBody.width
            height: root.flickable ? root.flickable.height : 600

            Rectangle {
                anchors.fill: parent
                color: Qt.alpha(Colours.palette.m3scrim, 0.55)

                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                    onClicked: {
                        if (!root.updateDialogRunning)
                            root.closeUpdateDialog();
                    }
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width - Tokens.padding.extraLarge * 2, 440)
                height: Math.min(parent.height - Tokens.padding.extraLarge * 2, dlgCol.implicitHeight + Tokens.padding.extraLarge * 2)
                radius: Tokens.rounding.large
                color: Colours.palette.m3surfaceContainerHigh
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.5)
                clip: true

                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                    onClicked: {}
                }

                ColumnLayout {
                    id: dlgCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Tokens.padding.extraLarge
                    spacing: Tokens.spacing.medium

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.medium

                        MaterialIcon {
                            text: root.updateDialogFailed ? "error" : root.updateDialogDone ? "check_circle" : root.updateDialogRunning ? "sync" : "system_update_alt"
                            color: root.updateDialogFailed
                                ? Colours.palette.m3error
                                : root.updateDialogDone
                                  ? Colours.palette.m3secondary
                                  : Colours.palette.m3primary
                            fontStyle: Tokens.font.icon.large

                            RotationAnimator on rotation {
                                running: root.updateDialogRunning
                                from: 0
                                to: 360
                                duration: 900
                                loops: Animation.Infinite
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                Layout.fillWidth: true
                                text: root.updateDialogTitle
                                font: Tokens.font.title.medium
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.updateDialogDetail
                                color: Colours.palette.m3outline
                                font: Tokens.font.body.small
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    StyledProgressBar {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 10
                        value: root.updateDialogProgress < 0 ? 0 : root.updateDialogProgress / 100
                        indeterminate: root.updateDialogRunning && root.updateDialogProgress < 0
                        visible: root.updateDialogRunning || root.updateDialogDone
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.updateDialogRunning || root.updateDialogDone
                        text: root.updateDialogProgress >= 0
                            ? qsTr("%1% · %2 / %3").arg(Math.round(root.updateDialogProgress)).arg(root.updateDialogDoneCount).arg(Math.max(root.updateDialogDoneCount, root.updateDialogTotalHint))
                            : qsTr("Working…")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.extraSmall
                        visible: root.updateDialogKind === "system" && !root.updateDialogRunning && !root.updateDialogDone && root.systemPackages.length > 0

                        StyledText {
                            text: qsTr("%1 packages will be upgraded").arg(root.systemPackageCount)
                            font: Tokens.font.label.medium
                        }

                        Flickable {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.min(160, Math.max(44, root.systemPackages.length * 22))
                            contentHeight: pkgPreviewCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ColumnLayout {
                                id: pkgPreviewCol
                                width: parent.width
                                spacing: 2

                                Repeater {
                                    model: root.systemPackagesPreview()

                                    StyledText {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        text: modelData.name + "  " + modelData.old + " → " + modelData.new
                                        color: Colours.palette.m3onSurfaceVariant
                                        font: Tokens.font.label.small
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }

                    Flickable {
                        id: logFlick
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.updateDialogLog.length ? 140 : 0
                        visible: root.updateDialogLog.length > 0
                        contentHeight: logText.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        StyledText {
                            id: logText
                            width: logFlick.width
                            text: root.updateDialogLog
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                            wrapMode: Text.WrapAnywhere
                        }

                        onContentHeightChanged: contentY = Math.max(0, contentHeight - height)
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Tokens.spacing.small
                        spacing: Tokens.spacing.small

                        Item {
                            Layout.fillWidth: true
                        }

                        IconTextButton {
                            text: root.updateDialogRunning ? qsTr("Running…") : qsTr("Cancel")
                            type: IconTextButton.Text
                            enabled: !root.updateDialogRunning
                            visible: !root.updateDialogDone
                            onClicked: root.closeUpdateDialog()
                        }

                        IconTextButton {
                            text: root.updateDialogDone ? qsTr("Close") : qsTr("Start update")
                            type: IconTextButton.Filled
                            enabled: !root.updateDialogRunning
                            onClicked: {
                                if (root.updateDialogDone)
                                    root.closeUpdateDialog();
                                else
                                    root.startUpdateFromDialog();
                            }
                        }
                    }
                }
            }
        }
    }
}
