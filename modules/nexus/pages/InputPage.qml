pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Mouse & touchpad")

    // Slider maps
    readonly property real scrollSlider: Math.min(1, Math.max(0, (PointerDevices.scrollFactor - 0.25) / 2.75))
    readonly property real sensSlider: Math.min(1, Math.max(0, (PointerDevices.sensitivity + 1) / 2))

    // Prevent the same click that starts capture from immediately acting as cancel
    // after the button label flips (layout reflow under the cursor).
    property bool recordArmed: true

    Component.onCompleted: PointerDevices.refresh()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // —— 鼠标 ——
        SectionHeader {
            first: true
            text: qsTr("Mouse")
        }

        SliderRow {
            first: true
            icon: "mouse"
            label: qsTr("Scroll speed")
            valueLabel: `${PointerDevices.scrollFactor.toFixed(2)}×`
            value: root.scrollSlider
            enabled: !PointerDevices.busy
            onMoved: v => {
                // 0.25× … 3.00×
                const factor = 0.25 + v * 2.75;
                PointerDevices.setScrollFactor(factor);
            }
        }

        SliderRow {
            icon: "swipe"
            label: qsTr("Pointer speed")
            valueLabel: {
                const s = PointerDevices.sensitivity;
                if (Math.abs(s) < 0.01)
                    return qsTr("Default");
                return (s > 0 ? "+" : "") + s.toFixed(2);
            }
            value: root.sensSlider
            enabled: !PointerDevices.busy
            onMoved: v => {
                // −1.0 … +1.0
                PointerDevices.setSensitivity(v * 2 - 1);
            }
        }

        ToggleRow {
            text: qsTr("Natural scrolling")
            subtext: qsTr("Move content in the same direction as your fingers or wheel")
            checked: PointerDevices.naturalScroll
            enabled: !PointerDevices.busy
            onToggled: PointerDevices.setNaturalScroll(checked)
        }

        ToggleRow {
            text: qsTr("Hold middle button to scroll")
            subtext: qsTr("Hold the middle button and move the mouse to scroll")
            checked: PointerDevices.middleScroll
            enabled: !PointerDevices.busy
            onToggled: PointerDevices.setMiddleScroll(checked)
        }

        ToggleRow {
            text: qsTr("Click middle button to lock scrolling")
            subtext: qsTr("Click the middle button to enter scrolling mode, then click again to exit")
            checked: PointerDevices.middleScrollLock
            enabled: !PointerDevices.busy && PointerDevices.middleScroll
            onToggled: PointerDevices.setMiddleScrollLock(checked)
        }

        ToggleRow {
            last: true
            text: qsTr("Disable pointer acceleration")
            subtext: qsTr("Use a flat acceleration profile for precise movement")
            checked: PointerDevices.flatAccel
            enabled: !PointerDevices.busy
            onToggled: PointerDevices.setFlatAccel(checked)
        }

        ConnectedRect {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            first: true
            last: true
            visible: PointerDevices.mice.length > 0
            implicitHeight: miceHint.implicitHeight + Tokens.padding.medium * 2

            StyledText {
                id: miceHint
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                text: qsTr("Detected mice: %1").arg(PointerDevices.mice.map(m => m.name).join(", "))
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
                wrapMode: Text.WordWrap
            }
        }

        // —— 侧键映射（按键录制）——
        SectionHeader {
            text: qsTr("Side-button mapping")
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: PointerDevices.buttonMaps.length === 0 && !PointerDevices.capturing
            implicitHeight: captureCol.implicitHeight + Tokens.padding.large * 2
            color: PointerDevices.capturing ? Colours.palette.m3primaryContainer : Colours.tPalette.m3surfaceContainer

            ColumnLayout {
                id: captureCol
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                StyledText {
                    Layout.fillWidth: true
                    text: PointerDevices.capturing ? qsTr("Waiting for a button...") : qsTr("Add mouse button mapping")
                    font: Tokens.font.body.small
                    color: PointerDevices.capturing ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    text: PointerDevices.capturing ? (PointerDevices.captureStatus || qsTr("Recording: existing side-button actions are paused. Press the button to map.")) : qsTr("1. Choose an action  2. Record a button  3. Press the side button. Existing mappings are paused while recording.")
                    color: PointerDevices.capturing ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3outline
                    font: Tokens.font.label.small
                    wrapMode: Text.WordWrap
                    opacity: 0.9
                }

                // Default action for next capture
                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    Repeater {
                        model: PointerDevices.sideActions

                        StyledRect {
                            required property var modelData
                            readonly property bool selected: modelData.id === PointerDevices.pendingCaptureAction

                            implicitHeight: capChip.implicitHeight + Tokens.padding.small
                            implicitWidth: capChip.implicitWidth + Tokens.padding.medium
                            radius: Tokens.rounding.full
                            color: selected ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainerHigh
                            visible: modelData.id !== "default"

                            StateLayer {
                                radius: parent.radius
                                enabled: !PointerDevices.capturing
                                onClicked: PointerDevices.pendingCaptureAction = modelData.id
                            }

                            StyledText {
                                id: capChip
                                anchors.centerIn: parent
                                text: modelData.label
                                color: selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.small
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    // One stable button (toggle label) so the click that starts
                    // capture cannot land on a newly-shown qsTr("Cancel") in the same slot.
                    IconTextButton {
                        Layout.fillWidth: true
                        icon: PointerDevices.capturing ? "stop" : "fiber_manual_record"
                        text: PointerDevices.capturing ? qsTr("Cancel recording") : qsTr("Record button")
                        type: PointerDevices.capturing ? IconTextButton.Tonal : IconTextButton.Filled
                        // ButtonBase uses `disabled`, not only Item.enabled.
                        disabled: !root.recordArmed
                        onClicked: {
                            if (!root.recordArmed)
                                return;
                            root.recordArmed = false;
                            if (PointerDevices.capturing)
                                PointerDevices.cancelButtonCapture();
                            else
                                PointerDevices.startButtonCapture(PointerDevices.pendingCaptureAction);
                            // Stay disarmed long enough for layout/process settle.
                            recordArmTimer.restart();
                        }
                    }

                    IconTextButton {
                        Layout.fillWidth: true
                        visible: !PointerDevices.capturing
                        icon: "delete"
                        text: qsTr("Clear all")
                        type: IconTextButton.Tonal
                        disabled: !root.recordArmed
                        onClicked: PointerDevices.clearAllButtonMaps()
                    }
                }

                Timer {
                    id: recordArmTimer
                    interval: 600
                    onTriggered: root.recordArmed = true
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: !!PointerDevices.lastCapturedKey
                    text: qsTr("Recently recorded: %1").arg(PointerDevices.keyDisplayName(PointerDevices.lastCapturedKey))
                    color: Colours.palette.m3primary
                    font: Tokens.font.label.medium
                    wrapMode: Text.WordWrap
                }
            }
        }

        // Existing maps
        Repeater {
            model: PointerDevices.buttonMaps

            ConnectedRect {
                id: mapRow
                required property var modelData
                required property int index

                Layout.fillWidth: true
                first: false
                last: index === PointerDevices.buttonMaps.length - 1
                implicitHeight: mapInner.implicitHeight + Tokens.padding.medium * 2

                ColumnLayout {
                    id: mapInner
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.small

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: PointerDevices.keyDisplayName(mapRow.modelData.key)
                                font: Tokens.font.body.small
                                elide: Text.ElideRight
                            }
                        }

                        StyledText {
                            text: PointerDevices.actionLabel(mapRow.modelData.action)
                            color: Colours.palette.m3primary
                            font: Tokens.font.label.medium
                        }

                        MaterialIcon {
                            text: "close"
                            color: Colours.palette.m3error
                            fontStyle: Tokens.font.icon.small
                            StateLayer {
                                anchors.centerIn: parent
                                implicitWidth: 28
                                implicitHeight: 28
                                radius: 14
                                onClicked: PointerDevices.removeButtonMap(mapRow.modelData.key)
                            }
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.extraSmall

                        Repeater {
                            model: PointerDevices.sideActions

                            StyledRect {
                                required property var modelData
                                readonly property bool selected: modelData.id === mapRow.modelData.action

                                implicitHeight: actChip.implicitHeight + Tokens.padding.extraSmall
                                implicitWidth: actChip.implicitWidth + Tokens.padding.small * 2
                                radius: Tokens.rounding.full
                                color: selected ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainerHigh
                                visible: modelData.id !== "default"

                                StateLayer {
                                    radius: parent.radius
                                    onClicked: PointerDevices.setButtonMapAction(mapRow.modelData.key, modelData.id)
                                }

                                StyledText {
                                    id: actChip
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                                    font: Tokens.font.label.small
                                }
                            }
                        }
                    }
                }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            first: true
            last: true
            implicitHeight: sideHint.implicitHeight + Tokens.padding.medium * 2

            StyledText {
                id: sideHint
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                text: qsTr("Map standard side buttons (mouse:275+) or media keys using Record button. Some wireless receivers may not expose compatible side buttons.")
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
                wrapMode: Text.WordWrap
            }
        }

        // —— 触摸板 ——
        SectionHeader {
            text: qsTr("Touchpad")
        }

        ToggleRow {
            first: true
            last: true
            text: qsTr("Enable touchpad")
            subtext: PointerDevices.touchpads.length ? qsTr("Device: %1").arg(PointerDevices.touchpads.map(p => p.name).join(", ")) : qsTr("No touchpad detected")
            checked: PointerDevices.touchpadEnabled
            enabled: PointerDevices.touchpads.length > 0 && !PointerDevices.busy
            onToggled: PointerDevices.setTouchpadEnabled(checked)
        }

        ConnectedRect {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            first: true
            last: true
            visible: !!PointerDevices.statusMessage || PointerDevices.touchpads.length === 0
            implicitHeight: hintCol.implicitHeight + Tokens.padding.medium * 2

            ColumnLayout {
                id: hintCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    Layout.fillWidth: true
                    visible: PointerDevices.touchpads.length === 0
                    text: qsTr("No touchpad device was found. External mice are unaffected.")
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: !!PointerDevices.statusMessage
                    text: PointerDevices.statusMessage
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    wrapMode: Text.WordWrap
                }
            }
        }

        SectionHeader {
            text: qsTr("Information")
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: infoCol.implicitHeight + Tokens.padding.large * 2

            ColumnLayout {
                id: infoCol
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Scroll speed, pointer speed, middle-button scrolling and side-button mappings are controlled by Hyprland and saved immediately.\nMiddle-button scrolling: hold the middle button and move the mouse. Side buttons: only standard buttons such as mouse:275/276 are supported.")
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

}
