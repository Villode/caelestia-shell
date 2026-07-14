pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Display")

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
            text: qsTr("Displays")
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
                    text: qsTr("Select a display to change its settings")
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
                            readonly property bool dimmed: !!modelData.disabled

                            x: rx
                            y: ry
                            width: rw
                            height: rh
                            radius: Tokens.rounding.medium
                            opacity: dimmed ? 0.45 : 1
                            color: selected ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest
                            border.width: selected ? 0 : 1
                            border.color: Colours.palette.m3outlineVariant

                            StateLayer {
                                radius: parent.radius
                                onClicked: Displays.selectMonitor(modelData.name)
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 0

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: String(modelData.index)
                                    color: selected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                                    font: Tokens.font.title.large
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    visible: modelData.disabled || Displays.isMirrored(modelData)
                                    text: modelData.disabled ? qsTr("Off") : qsTr("Mirror")
                                    color: selected ? Colours.palette.m3onPrimary : Colours.palette.m3outline
                                    font: Tokens.font.label.small
                                }
                            }
                        }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: Displays.monitors.length === 0
                        text: qsTr("No displays detected")
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
                                return qsTr("No display");
                            const label = root.mon.description || root.mon.name;
                            const state = root.mon.disabled ? qsTr("(disabled)") : (Displays.isMirrored(root.mon) ? qsTr("(mirrored)") : "");
                            return qsTr("Display %1 · %2%3").arg(root.mon.index).arg(label).arg(state);
                        }
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }

                    IconTextButton {
                        text: qsTr("Identify")
                        icon: "pin_drop"
                        isToggle: false
                        type: IconTextButton.Tonal
                        enabled: Displays.monitors.length > 0 && !Displays.busy
                        onClicked: Displays.identifyMonitors()
                    }

                    IconTextButton {
                        text: qsTr("Detect")
                        icon: "refresh"
                        isToggle: false
                        type: IconTextButton.Tonal
                        enabled: !Displays.busy
                        onClicked: {
                            Displays.refresh();
                            Displays.statusMessage = qsTr("Displays detected again.");
                        }
                    }
                }

                // Win11 projection modes
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small
                    visible: Displays.monitors.length > 0

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Multiple displays")
                        font: Tokens.font.body.small
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.extraSmall

                        ProjectionChip {
                            modeId: "internal"
                            iconName: "laptop_windows"
                            label: qsTr("PC screen only")
                            sublabel: qsTr("Turn off other displays")
                        }

                        ProjectionChip {
                            modeId: "duplicate"
                            iconName: "content_copy"
                            label: qsTr("Duplicate")
                            sublabel: qsTr("Mirror the primary display")
                        }

                        ProjectionChip {
                            modeId: "extend"
                            iconName: "width_wide"
                            label: qsTr("Extend")
                            sublabel: qsTr("Join displays into a larger desktop")
                        }

                        ProjectionChip {
                            modeId: "external"
                            iconName: "desktop_windows"
                            label: qsTr("Second screen only")
                            sublabel: qsTr("Turn off the PC screen")
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: !Displays.multiMonitor
                        text: qsTr("Only one display is detected. Connect a second display to change projection mode.")
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                        wrapMode: Text.WordWrap
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: Displays.multiMonitor
                        text: {
                            const mode = Displays.projectionMode();
                            const labels = {
                                internal: qsTr("Current: PC screen only"),
                                external: qsTr("Current: Second screen only"),
                                duplicate: qsTr("Current: Duplicate"),
                                extend: qsTr("Current: Extend"),
                                single: qsTr("Current: Single display")
                            };
                            const m = Displays.selected;
                            const pos = m ? qsTr(" · Selected %1 @ %2,%3").arg(m.name).arg(m.x).arg(m.y) : "";
                            return (labels[mode] || mode) + pos;
                        }
                        color: Colours.palette.m3primary
                        font: Tokens.font.label.small
                        wrapMode: Text.WordWrap
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
                    text: mon?.disabled ? "desktop_access_disabled" : "monitor"
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
                        text: {
                            if (!mon)
                                return qsTr("Waiting for detection");
                            if (mon.disabled)
                                return qsTr("Disabled · Re-enable from multiple display modes");
                            if (Displays.isMirrored(mon))
                                return qsTr("Mirrored from %1 · %2 × %3").arg(mon.mirrorOf).arg(mon.width).arg(mon.height);
                            return qsTr("%1 × %2 · %3 Hz · Scale %4").arg(mon.width).arg(mon.height).arg(Math.round(mon.refreshRate)).arg(root.formatScalePercent(root.scaleValue));
                        }
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                        elide: Text.ElideRight
                    }
                }
            }
        }

        component ProjectionChip: IconTextButton {
            required property string modeId
            required property string iconName
            required property string label
            property string sublabel

            icon: iconName
            text: label
            isToggle: false
            checked: Displays.projectionMode() === modeId
            type: IconTextButton.Tonal
            enabled: Displays.multiMonitor && !Displays.busy
            onClicked: {
                if (Displays.projectionMode() !== modeId)
                    Displays.applyProjectionMode(modeId);
            }

            ToolTip.visible: hovered && !!sublabel
            ToolTip.delay: 400
            ToolTip.text: sublabel
        }

        SectionHeader {
            text: qsTr("Scale & layout")
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
                        text: qsTr("Display scale")
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
                        text: mon ? qsTr("Logical %1 × %2").arg(Math.round(mon.width / root.draftDisplayScale)).arg(Math.round(mon.height / root.draftDisplayScale)) : ""
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
            label: qsTr("Resolution & refresh rate")
            subtext: currentMode ? Displays.formatMode(currentMode) : qsTr("No available modes")
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
            label: qsTr("UI scale")
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
