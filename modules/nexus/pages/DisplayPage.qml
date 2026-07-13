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
    property real draftDisplayScale: 1
    property bool displayScaleDragging: false

    readonly property var mon: Displays.selected
    readonly property string currentMode: mon ? Displays.currentModeString(mon) : ""
    readonly property real scaleValue: mon?.scale || 1
    readonly property int shellScalePercent: Math.round(Displays.shellUiScale * 100)
    readonly property list<real> scaleChoices: mon ? Displays.scaleChoicesForMonitor(mon, currentMode) : [1]
    readonly property real scaleMin: scaleChoices.length ? scaleChoices[0] : 0.5
    readonly property real scaleMax: scaleChoices.length ? scaleChoices[scaleChoices.length - 1] : 3
    readonly property var layoutBounds: Displays.layoutBounds()

    readonly property Timer shellScaleTimer: Timer {
        interval: 120
        onTriggered: {
            if (root.draftShellScale !== root.shellScalePercent)
                Displays.setShellUiScalePercent(root.draftShellScale);
        }
    }

    readonly property Timer displayScaleTimer: Timer {
        interval: 280
        onTriggered: {
            root.displayScaleDragging = false;
            if (Math.abs(root.draftDisplayScale - root.scaleValue) > 1e-4)
                Displays.applyScale(root.draftDisplayScale);
        }
    }

    function formatScalePercent(scale: real): string {
        const pct = Math.round(scale * 1000) / 10;
        return Number.isInteger(pct) ? `${pct}%` : `${pct}%`;
    }

    function snapDisplayScale(desired: real): real {
        if (!mon)
            return 1;
        const size = Displays.parseModeSize(currentMode) || {
            width: mon.width,
            height: mon.height
        };
        return Displays.nearestValidScale(size.width, size.height, desired);
    }

    function sliderFromScale(scale: real): real {
        if (scaleMax <= scaleMin)
            return 0;
        return Math.min(1, Math.max(0, (scale - scaleMin) / (scaleMax - scaleMin)));
    }

    function scaleFromSlider(v: real): real {
        const desired = scaleMin + Math.min(1, Math.max(0, v)) * (scaleMax - scaleMin);
        return snapDisplayScale(desired);
    }

    function syncDraftsFromLive(): void {
        if (!displayScaleDragging)
            draftDisplayScale = scaleValue;
        draftShellScale = shellScalePercent;
    }

    Component.onCompleted: {
        Displays.refresh();
        syncDraftsFromLive();
    }

    onScaleValueChanged: {
        if (!displayScaleDragging)
            draftDisplayScale = scaleValue;
    }

    onShellScalePercentChanged: draftShellScale = shellScalePercent

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

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

        // Windows 11-style arrangement map
        ConnectedRect {
            Layout.fillWidth: true
            first: true
            implicitHeight: arrangementLayout.implicitHeight + Tokens.padding.large * 2

            ColumnLayout {
                id: arrangementLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                StyledText {
                    Layout.fillWidth: true
                    text: "选择要更改其设置的显示器"
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                }

                Item {
                    id: arrangementMap
                    Layout.fillWidth: true
                    Layout.preferredHeight: 160

                    readonly property real pad: Tokens.padding.medium
                    readonly property real availW: Math.max(1, width - pad * 2)
                    readonly property real availH: Math.max(1, height - pad * 2)
                    readonly property real boundsW: Math.max(1, root.layoutBounds.width)
                    readonly property real boundsH: Math.max(1, root.layoutBounds.height)
                    readonly property real fit: Math.min(availW / boundsW, availH / boundsH) * 0.9
                    readonly property real contentW: boundsW * fit
                    readonly property real contentH: boundsH * fit
                    readonly property real originX: (width - contentW) / 2
                    readonly property real originY: (height - contentH) / 2

                    StyledRect {
                        anchors.fill: parent
                        radius: Tokens.rounding.large
                        color: Colours.tPalette.m3surfaceContainerHigh
                    }

                    Repeater {
                        model: Displays.monitors

                        StyledRect {
                            required property var modelData

                            readonly property var size: Displays.layoutSize(modelData)
                            readonly property real rx: arrangementMap.originX + (modelData.x - root.layoutBounds.minX) * arrangementMap.fit
                            readonly property real ry: arrangementMap.originY + (modelData.y - root.layoutBounds.minY) * arrangementMap.fit
                            readonly property real rw: Math.max(48, size.width * arrangementMap.fit)
                            readonly property real rh: Math.max(32, size.height * arrangementMap.fit)
                            readonly property bool selected: modelData.name === Displays.selectedName

                            x: rx
                            y: ry
                            width: rw
                            height: rh
                            radius: Tokens.rounding.medium
                            color: selected ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest
                            border.width: selected ? 0 : 1
                            border.color: Colours.palette.m3outlineVariant

                            StateLayer {
                                radius: parent.radius
                                onClicked: Displays.selectMonitor(modelData.name)
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: String(modelData.index)
                                color: selected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                                font: Tokens.font.title.large
                            }
                        }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: Displays.monitors.length === 0
                        text: "未检测到显示器"
                        color: Colours.palette.m3outline
                        font: Tokens.font.body.medium
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            if (!root.mon)
                                return "无显示器";
                            const label = root.mon.description || root.mon.name;
                            return `显示器 ${root.mon.index} · ${label}`;
                        }
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }

                    IconTextButton {
                        text: "标识"
                        icon: "pin_drop"
                        isToggle: false
                        type: IconTextButton.Tonal
                        enabled: Displays.monitors.length > 0 && !Displays.busy
                        onClicked: Displays.identifyMonitors()
                    }

                    IconTextButton {
                        text: "检测"
                        icon: "refresh"
                        isToggle: false
                        type: IconTextButton.Tonal
                        enabled: !Displays.busy
                        onClicked: {
                            Displays.refresh();
                            Displays.statusMessage = "已重新检测显示器。";
                        }
                    }
                }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            last: true
            implicitHeight: monInfoLayout.implicitHeight + Tokens.padding.medium * 2

            RowLayout {
                id: monInfoLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "monitor"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: mon ? mon.name : "—"
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: mon ? `${mon.width} × ${mon.height} · ${Math.round(mon.refreshRate)} Hz · 缩放 ${root.formatScalePercent(root.scaleValue)}` : "等待检测"
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                        elide: Text.ElideRight
                    }
                }
            }
        }

        SectionHeader {
            text: "缩放与布局"
        }

        // Display scale slider with legal snap
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
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: "zoom_in"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.medium
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: "显示缩放"
                        font: Tokens.font.body.small
                    }

                    StyledText {
                        text: root.formatScalePercent(root.draftDisplayScale)
                        color: Colours.palette.m3primary
                        font: Tokens.font.title.medium
                    }
                }

                StyledSlider {
                    id: displayScaleSlider
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.padding.medium * 2
                    radius: Tokens.rounding.small
                    enabled: !!root.mon && root.scaleChoices.length > 1 && !Displays.busy
                    value: root.sliderFromScale(root.draftDisplayScale)
                    onInteraction: v => {
                        root.displayScaleDragging = true;
                        root.draftDisplayScale = root.scaleFromSlider(v);
                        root.displayScaleTimer.restart();
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        text: root.formatScalePercent(root.scaleMin)
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    StyledText {
                        text: mon ? `逻辑 ${Math.round(mon.width / root.draftDisplayScale)} × ${Math.round(mon.height / root.draftDisplayScale)}` : ""
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    StyledText {
                        text: root.formatScalePercent(root.scaleMax)
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                    }
                }
            }
        }

        SelectRow {
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
