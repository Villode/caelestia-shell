pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Lock screen & power")

    // Draft values (minutes). Rebuilt from GlobalConfig on load / after save.
    property bool lockEnabled: true
    property int lockMinutes: 15
    property bool screenOffEnabled: true
    property int screenOffMinutes: 20
    property bool sleepEnabled: true
    property int sleepMinutes: 30
    property string sleepAction: "suspendThenHibernate" // suspend | suspendThenHibernate | hibernate

    readonly property list<MenuItem> sleepActionItems: [
        MenuItem {
            text: qsTr("Sleep")
        },
        MenuItem {
            text: qsTr("Suspend then hibernate")
        },
        MenuItem {
            text: qsTr("Hibernate")
        }
    ]
    readonly property list<string> sleepActionValues: ["suspend", "suspendThenHibernate", "hibernate"]

    function sleepActionIndex(): int {
        const i = root.sleepActionValues.indexOf(root.sleepAction);
        return i >= 0 ? i : 1;
    }

    function actionKind(entry: var): string {
        if (!entry)
            return "";
        const a = entry.idleAction;
        if (a === "lock")
            return "lock";
        if (a === "dpms off")
            return "dpms";
        if (typeof a === "string") {
            const s = a.toLowerCase();
            if (s === "suspend" || s === "suspendthenhibernate" || s === "hibernate")
                return "sleep";
        }
        if (Array.isArray(a) && a.length) {
            const s = String(a[0]).toLowerCase();
            if (s.includes("suspend") || s.includes("hibernate"))
                return "sleep";
        }
        return "other";
    }

    function sleepActionFromEntry(entry: var): string {
        const a = entry?.idleAction;
        const raw = Array.isArray(a) ? String(a[0] || "") : String(a || "");
        const s = raw.toLowerCase();
        if (s === "hibernate")
            return "hibernate";
        if (s === "suspend")
            return "suspend";
        return "suspendThenHibernate";
    }

    function loadFromConfig(): void {
        const list = GlobalConfig.general.idle.timeouts || [];
        let sawLock = false;
        let sawDpms = false;
        let sawSleep = false;
        for (const t of list) {
            const kind = root.actionKind(t);
            const en = t.enabled !== false;
            const mins = Math.max(1, Math.round((Number(t.timeout) || 60) / 60));
            if (kind === "lock") {
                sawLock = true;
                root.lockEnabled = en;
                root.lockMinutes = mins;
            } else if (kind === "dpms") {
                sawDpms = true;
                root.screenOffEnabled = en;
                root.screenOffMinutes = mins;
            } else if (kind === "sleep") {
                sawSleep = true;
                root.sleepEnabled = en;
                root.sleepMinutes = mins;
                root.sleepAction = root.sleepActionFromEntry(t);
            }
        }
        if (!sawLock)
            root.lockEnabled = false;
        if (!sawDpms)
            root.screenOffEnabled = false;
        if (!sawSleep)
            root.sleepEnabled = false;
    }

    function applyTimeouts(): void {
        const next = [];
        if (root.lockEnabled) {
            next.push({
                timeout: root.lockMinutes * 60,
                idleAction: "lock",
                enabled: true
            });
        }
        if (root.screenOffEnabled) {
            next.push({
                timeout: root.screenOffMinutes * 60,
                idleAction: "dpms off",
                returnAction: "dpms on",
                enabled: true
            });
        }
        if (root.sleepEnabled) {
            next.push({
                timeout: root.sleepMinutes * 60,
                idleAction: [root.sleepAction],
                enabled: true
            });
        }
        // Sort by timeout ascending so monitors fire in order
        next.sort((a, b) => a.timeout - b.timeout);
        GlobalConfig.general.idle.timeouts = next;
    }

    function formatMinutes(m: int): string {
        if (m < 60)
            return qsTr("%1 minutes").arg(m);
        const h = Math.floor(m / 60);
        const r = m % 60;
        return r ? qsTr("%1 hours %2 minutes").arg(h).arg(r) : qsTr("%1 hours").arg(h);
    }

    Component.onCompleted: loadFromConfig()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // —— 行为 ——
        SectionHeader {
            first: true
            text: qsTr("Behaviour")
        }

        ToggleRow {
            first: true
            text: qsTr("Lock before sleep")
            subtext: qsTr("Lock before the system sleeps or hibernates")
            checked: GlobalConfig.general.idle.lockBeforeSleep
            onToggled: GlobalConfig.general.idle.lockBeforeSleep = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Keep awake while media is playing")
            subtext: qsTr("Do not lock or turn off displays while audio or video is playing")
            checked: GlobalConfig.general.idle.inhibitWhenAudio
            onToggled: GlobalConfig.general.idle.inhibitWhenAudio = checked
        }

        // —— 空闲超时 ——
        SectionHeader {
            text: qsTr("Idle timeouts")
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.largeIncreased
            Layout.rightMargin: Tokens.padding.largeIncreased
            Layout.bottomMargin: Tokens.spacing.extraSmall
            text: qsTr("Actions run in order after inactivity. Times are measured from when idle begins; disabling an item disables that action.")
            color: Colours.palette.m3outline
            font: Tokens.font.label.small
            wrapMode: Text.WordWrap
        }

        ToggleRow {
            first: true
            text: qsTr("Automatic lock")
            subtext: root.lockEnabled ? qsTr("Lock after %1 of inactivity").arg(root.formatMinutes(root.lockMinutes)) : qsTr("Disabled")
            checked: root.lockEnabled
            onToggled: {
                root.lockEnabled = checked;
                root.applyTimeouts();
            }
        }

        StepperRow {
            visible: root.lockEnabled
            label: qsTr("Lock delay")
            subtext: root.formatMinutes(root.lockMinutes)
            value: root.lockMinutes
            from: 1
            to: 180
            stepSize: 1
            onMoved: v => {
                root.lockMinutes = Math.round(v);
                root.applyTimeouts();
            }
        }

        ToggleRow {
            text: qsTr("Turn off displays")
            subtext: root.screenOffEnabled ? qsTr("Turn off displays after %1 of inactivity").arg(root.formatMinutes(root.screenOffMinutes)) : qsTr("Disabled")
            checked: root.screenOffEnabled
            onToggled: {
                root.screenOffEnabled = checked;
                root.applyTimeouts();
            }
        }

        StepperRow {
            visible: root.screenOffEnabled
            label: qsTr("Display-off delay")
            subtext: root.formatMinutes(root.screenOffMinutes)
            value: root.screenOffMinutes
            from: 1
            to: 180
            stepSize: 1
            onMoved: v => {
                root.screenOffMinutes = Math.round(v);
                root.applyTimeouts();
            }
        }

        ToggleRow {
            // Always present; when sleep extras are hidden this is the group bottom.
            last: !root.sleepEnabled
            text: qsTr("Automatic sleep")
            subtext: root.sleepEnabled ? qsTr("%1 after %2 of inactivity").arg(root.sleepActionItems[root.sleepActionIndex()].text).arg(root.formatMinutes(root.sleepMinutes)) : qsTr("Disabled")
            checked: root.sleepEnabled
            onToggled: {
                root.sleepEnabled = checked;
                root.applyTimeouts();
            }
        }

        StepperRow {
            visible: root.sleepEnabled
            label: qsTr("Sleep delay")
            subtext: root.formatMinutes(root.sleepMinutes)
            value: root.sleepMinutes
            from: 1
            to: 180
            stepSize: 1
            onMoved: v => {
                root.sleepMinutes = Math.round(v);
                root.applyTimeouts();
            }
        }

        SelectRow {
            // Bottom of the idle group when sleep is enabled.
            last: true
            visible: root.sleepEnabled
            label: qsTr("Sleep method")
            subtext: qsTr("Sleep suspends to memory; hibernate writes to disk; suspend then hibernate does both in sequence")
            menuItems: root.sleepActionItems
            active: root.sleepActionItems[root.sleepActionIndex()]
            onSelected: item => {
                const i = root.sleepActionItems.indexOf(item);
                if (i >= 0) {
                    root.sleepAction = root.sleepActionValues[i];
                    root.applyTimeouts();
                }
            }
        }

        // —— 锁屏选项 ——
        SectionHeader {
            text: qsTr("Lock screen")
        }

        ToggleRow {
            first: true
            text: qsTr("Fingerprint unlock")
            subtext: qsTr("Allow fingerprint unlock when a fingerprint is configured")
            checked: GlobalConfig.lock.enableFprint
            onToggled: GlobalConfig.lock.enableFprint = checked
        }

        StepperRow {
            last: true
            label: qsTr("Maximum fingerprint attempts")
            subtext: qsTr("Fall back to password after %1 failed attempts").arg(GlobalConfig.lock.maxFprintTries)
            value: GlobalConfig.lock.maxFprintTries
            from: 1
            to: 10
            stepSize: 1
            onMoved: v => GlobalConfig.lock.maxFprintTries = Math.round(v)
        }

        // —— 说明 ——
        SectionHeader {
            text: qsTr("Information")
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: helpText.implicitHeight + Tokens.padding.large * 2

            StyledText {
                id: helpText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                text: qsTr("These settings are handled by the Shell idle monitor and take effect immediately.\nTurning off displays does not end the session; sleep suspends the system. Use Keep awake in Control Centre to temporarily inhibit automatic sleep.")
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
                wrapMode: Text.WordWrap
            }
        }
    }
}
