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

// Phone-style software update page: one status hero + two clean cards.
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
    property bool systemListOpen: false

    readonly property int updateCount: components.filter(item => root.hasUpdate(item.status)).length
    readonly property int totalPending: updateCount + systemPackageCount
    readonly property bool busy: checking || systemChecking

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
        onExited: code => { // qmllint disable signal-handler-parameters
            root.checking = false;
            if (code === 0)
                return;
            if (code === 124 || code === 137)
                root.errorText = qsTr("Check timed out. Network may be slow.");
            else if (root.lastStderr)
                root.errorText = root.lastStderr.split("\n").filter(l => l.trim()).slice(-1)[0] || root.lastStderr;
            else
                root.errorText = qsTr("Could not check for updates.");
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
        onExited: code => { // qmllint disable signal-handler-parameters
            root.systemChecking = false;
            if (code === 0)
                return;
            if (code === 124 || code === 137)
                root.systemError = qsTr("System check timed out.");
            else if (!root.systemError)
                root.systemError = qsTr("Could not check system packages.");
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
        const hasMissing = root.components.some(item => item.status === "未安装");
        const updateCmd = hasMissing ? "villode-caelestia-update --install-missing" : "villode-caelestia-update";
        const banner = "echo '" + qsTr("Villode components only — not a full system upgrade.") + "'; echo;";
        Quickshell.execDetached([Quickshell.shellPath("assets/villode_terminal_exec.sh"), String(terminal.length), ...terminal, "--", "sh", "-lc", banner + updateCmd + "; code=$?; echo; if [ $code -eq 0 ]; then echo '" + qsTr("Done.") + "'; else echo '" + qsTr("Failed.") + " '$code; fi; echo '" + qsTr("Press Enter to close…") + "'; read -r; exit $code"]);
    }

    function launchSystemUpdate(): void {
        const terminal = [...GlobalConfig.general.apps.terminal];
        Quickshell.execDetached([Quickshell.shellPath("assets/villode_terminal_exec.sh"), String(terminal.length), ...terminal, "--", "sh", "-lc", "villode-system-update --apply; code=$?; echo; echo '" + qsTr("Press Enter to close…") + "'; read -r; exit $code"]);
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
            root.components = rows;
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
        root.components = rows;
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
        if (root.busy)
            return qsTr("Checking for updates…");
        if (root.errorText && root.updateCount <= 0 && root.systemPackageCount <= 0)
            return qsTr("Could not check");
        if (root.totalPending > 0)
            return qsTr("%1 updates available").arg(root.totalPending);
        return qsTr("You're up to date");
    }

    function heroSubtitle(): string {
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
        return qsTr("Pull to refresh is not available — use Check");
    }

    function componentBlurb(item: var): string {
        if (item.status === "未安装")
            return item.latest && item.latest !== "—" ? qsTr("Available %1").arg(item.latest) : qsTr("Not installed");
        if (item.installed === item.latest)
            return qsTr("Version %1").arg(item.installed);
        if (item.id === "cursor")
            return qsTr("%1 → %2 · with shell").arg(item.installed).arg(item.latest);
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

    Component.onCompleted: checkUpdates()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.medium

        // ── Hero status (phone-like) ──
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
                        onClicked: root.launchUpdate()
                    }
                }
            }
        }

        // ── Card: Villode ──
        SectionHeader {
            text: qsTr("Villode")
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: root.components.length === 0
            implicitHeight: villodeHead.implicitHeight + Tokens.padding.large * 2

            RowLayout {
                id: villodeHead
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
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

                StyledText {
                    text: root.updateCount > 0 ? qsTr("%1 new").arg(root.updateCount) : qsTr("OK")
                    color: root.updateCount > 0 ? Colours.palette.m3primary : Colours.palette.m3outline
                    font: Tokens.font.label.medium
                }
            }
        }

        Repeater {
            model: root.components

            ConnectedRect {
                id: card

                required property var modelData
                required property int index

                property bool expanded: false

                Layout.fillWidth: true
                first: false
                last: card.index === root.components.length - 1
                implicitHeight: cardCol.implicitHeight + Tokens.padding.medium * 2
                visible: root.hasUpdate(modelData.status) || root.updateCount === 0

                ColumnLayout {
                    id: cardCol
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.small

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
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: Tokens.font.icon.medium.pointSize + Tokens.spacing.medium
                        spacing: Tokens.spacing.extraSmall
                        visible: card.expanded

                        Repeater {
                            model: root.changeLines(card.modelData)

                            StyledText {
                                required property string modelData
                                Layout.fillWidth: true
                                text: "· " + modelData
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.body.small
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }
        }

        // ── Card: System ──
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
                    text: qsTr("May include kernel, drivers and libraries. Confirm carefully in the terminal.")
                    color: Colours.palette.m3tertiary
                    font: Tokens.font.label.small
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.systemRisky.length > 0
                    text: qsTr("Includes: %1").arg(root.systemRisky.slice(0, 8).join(", ") + (root.systemRisky.length > 8 ? "…" : ""))
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
                        enabled: !root.systemChecking
                        onClicked: root.checkSystemUpdates()
                    }

                    IconTextButton {
                        icon: "upgrade"
                        text: root.systemPackageCount > 0 ? qsTr("Upgrade system") : qsTr("Upgrade system")
                        type: IconTextButton.Filled
                        enabled: !root.systemChecking
                        onClicked: root.launchSystemUpdate()
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    IconTextButton {
                        visible: root.systemPackageCount > 0
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
                        text: qsTr("More packages will be shown in the terminal.")
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
}
