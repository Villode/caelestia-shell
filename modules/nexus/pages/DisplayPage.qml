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

    property int draftShellScale: 100

    readonly property var mon: Displays.selected
    readonly property string currentMode: mon ? Displays.currentModeString(mon) : ""
    readonly property real scaleValue: mon?.scale || 1
    readonly property int scalePercent: Math.round(scaleValue * 100)
    readonly property int shellScalePercent: Math.round(Displays.shellUiScale * 100)
    readonly property list<real> scaleChoices: mon ? Displays.scaleChoicesForMonitor(mon, currentMode) : [1]

    readonly property Timer shellScaleTimer: Timer {
        interval: 120
        onTriggered: {
            if (root.draftShellScale !== root.shellScalePercent)
                Displays.setShellUiScalePercent(root.draftShellScale);
        }
    }

    function syncDraftsFromLive(): void {
        draftShellScale = shellScalePercent;
    }

    function formatScalePercent(scale: real): string {
        const pct = Math.round(scale * 1000) / 10;
        if (Number.isInteger(pct))
            return `${pct}%`;
        // Keep one decimal for values like 83.3%
        return `${pct}%`;
    }

    function isActiveScale(scale: real): bool {
        return Math.abs(scale - root.scaleValue) < 1e-3;
    }

    Component.onCompleted: {
        Displays.refresh();
        syncDraftsFromLive();
    }

    onShellScalePercentChanged: draftShellScale = shellScalePercent

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

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

        // Display scale — chip row instead of long-dropdown + wall of text
        ConnectedRect {
            Layout.fillWidth: true
            first: true
            enabled: !!mon && scaleChoices.length > 0 && !Displays.busy
            implicitHeight: displayScaleLayout.implicitHeight + Tokens.padding.large * 2
            opacity: enabled ? 1 : 0.55

            ColumnLayout {
                id: displayScaleLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: "zoom_in"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.medium
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: "显示缩放"
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: mon ? `逻辑分辨率约 ${Math.round(mon.width / root.scaleValue)} × ${Math.round(mon.height / root.scaleValue)}` : "影响全部应用与桌面"
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    StyledText {
                        text: root.formatScalePercent(root.scaleValue)
                        color: Colours.palette.m3primary
                        font: Tokens.font.title.medium
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    Repeater {
                        model: root.scaleChoices

                        IconTextButton {
                            required property real modelData

                            text: root.formatScalePercent(modelData)
                            isToggle: false
                            checked: root.isActiveScale(modelData)
                            type: IconTextButton.Tonal
                            enabled: !!root.mon && !Displays.busy
                            // Hide empty icon so chips stay compact (percentage only).
                            iconLabel.visible: false
                            onClicked: {
                                if (!root.isActiveScale(modelData))
                                    Displays.applyScale(modelData);
                            }
                        }
                    }
                }
            }
        }

        // Shell UI scale
        SliderRow {
            last: true
            icon: "text_fields"
            label: "界面缩放"
            valueLabel: `${root.draftShellScale}%`
            value: Math.min(1, Math.max(0, (root.draftShellScale - 50) / 200))
            enabled: !Displays.busy
            onMoved: v => {
                root.draftShellScale = Math.round((v * 200 + 50) / 5) * 5;
                root.shellScaleTimer.restart();
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
                    text: Displays.busy ? "progress_activity" : "check_circle"
                    color: Colours.palette.m3primary
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
