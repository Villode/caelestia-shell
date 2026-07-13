pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: "显示"

    property int draftDisplayScale: 100
    property int draftShellScale: 100
    property bool displayScaleDragging: false

    readonly property var mon: Displays.selected
    readonly property string currentMode: mon ? Displays.currentModeString(mon) : ""
    readonly property int scalePercent: mon ? Math.round((mon.scale || 1) * 100) : 100
    readonly property int shellScalePercent: Math.round(Displays.shellUiScale * 100)

    readonly property Timer displayScaleTimer: Timer {
        interval: 280
        onTriggered: {
            if (root.draftDisplayScale !== root.scalePercent)
                Displays.applyScalePercent(root.draftDisplayScale);
            root.displayScaleDragging = false;
        }
    }

    readonly property Timer shellScaleTimer: Timer {
        interval: 120
        onTriggered: {
            if (root.draftShellScale !== root.shellScalePercent)
                Displays.setShellUiScalePercent(root.draftShellScale);
        }
    }

    function syncDraftsFromLive(): void {
        if (!displayScaleDragging)
            draftDisplayScale = scalePercent;
        draftShellScale = shellScalePercent;
    }

    Component.onCompleted: {
        Displays.refresh();
        syncDraftsFromLive();
    }

    onScalePercentChanged: {
        if (!displayScaleDragging)
            draftDisplayScale = scalePercent;
    }

    onShellScalePercentChanged: draftShellScale = shellScalePercent

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Dynamic select menus for monitors and modes
        Variants {
            id: monitorVariants
            model: Displays.monitors

            MenuItem {
                required property var modelData
                text: modelData.description && modelData.description !== modelData.name ? `${modelData.description} (${modelData.name})` : modelData.name
            }
        }

        Variants {
            id: modeVariants
            model: root.mon?.availableModes ?? []

            MenuItem {
                required property string modelData
                text: Displays.formatMode(modelData)
            }
        }

        SectionHeader {
            first: true
            text: "显示器"
        }

        SelectRow {
            first: true
            last: true
            label: "当前显示器"
            subtext: mon ? `${mon.width} × ${mon.height} · ${Math.round(mon.refreshRate)} Hz` : "未检测到显示器"
            menuItems: monitorVariants.instances
            active: {
                if (!mon)
                    return null;
                return monitorVariants.instances.find(i => i.modelData.name === mon.name) ?? null;
            }
            fallbackText: mon?.name || "无"
            fallbackIcon: "monitor"
            enabled: Displays.monitors.length > 1 && !Displays.busy
            onSelected: item => {
                if (item?.modelData?.name)
                    Displays.selectMonitor(item.modelData.name);
            }
        }

        SectionHeader {
            text: "分辨率"
        }

        SelectRow {
            first: true
            last: true
            label: "分辨率与刷新率"
            subtext: currentMode ? Displays.formatMode(currentMode) : "无可用模式"
            menuItems: modeVariants.instances
            active: {
                if (!currentMode)
                    return null;
                return modeVariants.instances.find(i => i.modelData === currentMode) ?? null;
            }
            fallbackText: currentMode ? Displays.formatMode(currentMode) : "—"
            fallbackIcon: "screenshot_monitor"
            enabled: !!mon && (root.mon?.availableModes?.length || 0) > 0 && !Displays.busy
            onSelected: item => {
                if (item.modelData && item.modelData !== root.currentMode)
                    Displays.applyMode(item.modelData);
            }
        }

        SectionHeader {
            text: "缩放"
        }

        SliderRow {
            first: true
            icon: "zoom_in"
            label: "显示缩放"
            valueLabel: `${root.draftDisplayScale}%`
            // Map 50%–300% onto 0–1 for the shared slider control.
            value: Math.min(1, Math.max(0, (root.draftDisplayScale - 50) / 250))
            enabled: !!mon && !Displays.busy
            onMoved: v => {
                root.displayScaleDragging = true;
                root.draftDisplayScale = Math.round((v * 250 + 50) / 5) * 5;
                root.displayScaleTimer.restart();
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            last: true
            implicitHeight: scaleHint.implicitHeight + Tokens.padding.medium * 2

            StyledText {
                id: scaleHint
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                text: "调整 Hyprland 输出缩放（影响所有应用）。推荐 100%、125%、150% 等档位。"
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
                wrapMode: Text.WordWrap
            }
        }

        SliderRow {
            Layout.topMargin: Tokens.spacing.large - parent.spacing
            first: true
            icon: "text_fields"
            label: "界面缩放"
            valueLabel: `${root.draftShellScale}%`
            // Map 50%–250% onto 0–1.
            value: Math.min(1, Math.max(0, (root.draftShellScale - 50) / 200))
            enabled: !Displays.busy
            onMoved: v => {
                root.draftShellScale = Math.round((v * 200 + 50) / 5) * 5;
                root.shellScaleTimer.restart();
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            last: true
            implicitHeight: shellHint.implicitHeight + Tokens.padding.medium * 2

            StyledText {
                id: shellHint
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                text: "仅缩放 Caelestia Shell 的字体、间距与圆角，不改变系统分辨率。"
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
                wrapMode: Text.WordWrap
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.large - parent.spacing
            first: true
            last: true
            visible: !!Displays.statusMessage
            implicitHeight: statusLayout.implicitHeight + Tokens.padding.medium * 2

            RowLayout {
                id: statusLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: Displays.busy ? "progress_activity" : "info"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Displays.statusMessage
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
