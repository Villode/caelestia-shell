pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: "鼠标和触摸板"

    Component.onCompleted: PointerDevices.refresh()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
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
                    text: "未找到触摸板设备。外接鼠标不受此开关影响。"
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
                    text: "关闭触摸板后仍可使用外接鼠标或触控板以外的指针设备。设置会写入 Hyprland 配置并在下次登录时保持。"
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
