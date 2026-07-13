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

    title: "锁屏与电源"

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
            text: "睡眠"
        },
        MenuItem {
            text: "睡眠后休眠"
        },
        MenuItem {
            text: "休眠"
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
            return `${m} 分钟`;
        const h = Math.floor(m / 60);
        const r = m % 60;
        return r ? `${h} 小时 ${r} 分钟` : `${h} 小时`;
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
            text: "行为"
        }

        ToggleRow {
            first: true
            text: "睡眠前锁定屏幕"
            subtext: "系统进入睡眠/休眠前先锁屏，唤醒时需要解锁"
            checked: GlobalConfig.general.idle.lockBeforeSleep
            onToggled: GlobalConfig.general.idle.lockBeforeSleep = checked
        }

        ToggleRow {
            last: true
            text: "播放媒体时保持唤醒"
            subtext: "有音频/视频播放时，不触发自动锁屏与关闭屏幕"
            checked: GlobalConfig.general.idle.inhibitWhenAudio
            onToggled: GlobalConfig.general.idle.inhibitWhenAudio = checked
        }

        // —— 空闲超时 ——
        SectionHeader {
            text: "空闲超时"
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.largeIncreased
            Layout.rightMargin: Tokens.padding.largeIncreased
            Layout.bottomMargin: Tokens.spacing.extraSmall
            text: "无人操作一段时间后依次执行。时间从空闲开始累计；关闭某项即禁用该动作。"
            color: Colours.palette.m3outline
            font: Tokens.font.label.small
            wrapMode: Text.WordWrap
        }

        ToggleRow {
            first: true
            text: "自动锁屏"
            subtext: root.lockEnabled ? `空闲 ${root.formatMinutes(root.lockMinutes)} 后锁定` : "已关闭"
            checked: root.lockEnabled
            onToggled: {
                root.lockEnabled = checked;
                root.applyTimeouts();
            }
        }

        StepperRow {
            visible: root.lockEnabled
            label: "锁屏等待"
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
            text: "关闭屏幕"
            subtext: root.screenOffEnabled ? `空闲 ${root.formatMinutes(root.screenOffMinutes)} 后关闭显示器` : "已关闭"
            checked: root.screenOffEnabled
            onToggled: {
                root.screenOffEnabled = checked;
                root.applyTimeouts();
            }
        }

        StepperRow {
            visible: root.screenOffEnabled
            label: "关屏等待"
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
            text: "自动睡眠"
            subtext: root.sleepEnabled ? `空闲 ${root.formatMinutes(root.sleepMinutes)} 后${root.sleepActionItems[root.sleepActionIndex()].text}` : "已关闭"
            checked: root.sleepEnabled
            onToggled: {
                root.sleepEnabled = checked;
                root.applyTimeouts();
            }
        }

        StepperRow {
            visible: root.sleepEnabled
            label: "睡眠等待"
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
            label: "睡眠方式"
            subtext: "睡眠：挂起内存；休眠：写入磁盘；睡眠后休眠：先睡再转休眠"
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
            text: "锁屏"
        }

        ToggleRow {
            first: true
            text: "指纹解锁"
            subtext: "锁屏时允许使用指纹（需系统已配置指纹）"
            checked: GlobalConfig.lock.enableFprint
            onToggled: GlobalConfig.lock.enableFprint = checked
        }

        StepperRow {
            last: true
            label: "指纹最大尝试次数"
            subtext: `失败 ${GlobalConfig.lock.maxFprintTries} 次后回退到密码`
            value: GlobalConfig.lock.maxFprintTries
            from: 1
            to: 10
            stepSize: 1
            onMoved: v => GlobalConfig.lock.maxFprintTries = Math.round(v)
        }

        // —— 说明 ——
        SectionHeader {
            text: "说明"
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
                text: "这些设置由 Shell 的空闲监控处理，写入配置后立即生效。\n「关闭屏幕」仅关闭显示输出，不会退出会话；「睡眠」会挂起系统。可在控制中心临时开启「防止休眠」以抑制自动睡眠。"
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
                wrapMode: Text.WordWrap
            }
        }
    }
}
