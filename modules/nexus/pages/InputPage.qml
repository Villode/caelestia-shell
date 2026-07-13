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

    title: "鼠标和触摸板"

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
            text: "鼠标"
        }

        SliderRow {
            first: true
            icon: "mouse"
            label: "滚动速度"
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
            label: "指针速度"
            valueLabel: {
                const s = PointerDevices.sensitivity;
                if (Math.abs(s) < 0.01)
                    return "默认";
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
            text: "自然滚动"
            subtext: "内容随手指/滚轮方向移动（类似触控板）"
            checked: PointerDevices.naturalScroll
            enabled: !PointerDevices.busy
            onToggled: PointerDevices.setNaturalScroll(checked)
        }

        ToggleRow {
            text: "中键按住滚动"
            subtext: "按住中键并移动鼠标即可滚动（需 scroll_method=on_button_down）"
            checked: PointerDevices.middleScroll
            enabled: !PointerDevices.busy
            onToggled: PointerDevices.setMiddleScroll(checked)
        }

        ToggleRow {
            text: "中键单击锁定滚动"
            subtext: "单击中键进入滚动模式，再点一次退出（无需一直按住）"
            checked: PointerDevices.middleScrollLock
            enabled: !PointerDevices.busy && PointerDevices.middleScroll
            onToggled: PointerDevices.setMiddleScrollLock(checked)
        }

        ToggleRow {
            last: true
            text: "禁用指针加速"
            subtext: "使用匀速（flat）加速度曲线，更适合精密操作"
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
                text: `已检测鼠标：${PointerDevices.mice.map(m => m.name).join("、")}`
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
                wrapMode: Text.WordWrap
            }
        }

        // —— 侧键映射（按键录制）——
        SectionHeader {
            text: "侧键映射"
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
                    text: PointerDevices.capturing ? "正在等待按键…" : "添加鼠标按键映射"
                    font: Tokens.font.body.small
                    color: PointerDevices.capturing ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    text: PointerDevices.capturing ? (PointerDevices.captureStatus || "录制中：已暂停现有侧键功能，请按下要映射的按键（忽略左/右/中键）。") : "① 选择动作  ② 录制按键  ③ 按下侧键。录制期间不会触发已有映射。"
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
                    // capture cannot land on a newly-shown "取消" in the same slot.
                    IconTextButton {
                        Layout.fillWidth: true
                        icon: PointerDevices.capturing ? "stop" : "fiber_manual_record"
                        text: PointerDevices.capturing ? "取消录制" : "录制按键"
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
                        text: "清除全部"
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
                    text: `最近录制：${PointerDevices.keyDisplayName(PointerDevices.lastCapturedKey)}`
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
                text: "通过「录制按键」绑定标准侧键（mouse:275+）或媒体键。需鼠标在系统中上报为侧键；部分无线接收器（如部分小米型号）不兼容。"
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
                wrapMode: Text.WordWrap
            }
        }

        // —— 触摸板 ——
        SectionHeader {
            text: "触摸板"
        }

        ToggleRow {
            first: true
            last: true
            text: "启用触摸板"
            subtext: PointerDevices.touchpads.length ? `设备：${PointerDevices.touchpads.map(p => p.name).join("、")}` : "未检测到触摸板"
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
                    text: "未找到触摸板设备。外接鼠标不受触摸板开关影响。"
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
            text: "说明"
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
                    text: "滚动速度、指针速度、中键滚动与侧键映射由 Hyprland 控制，立即生效并会保存。\n中键滚动：按住中键移动鼠标。侧键：仅支持系统识别为 mouse:275/276 等标准侧键的鼠标。"
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

}
