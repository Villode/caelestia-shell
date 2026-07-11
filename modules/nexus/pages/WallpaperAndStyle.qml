pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.images
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property real maximumTransparency: 0.75
    property string requestedMode
    readonly property string desiredMode: requestedMode || (Colours.light ? "light" : "dark")
    property Connections colourConnections: Connections {
        function onCurrentLightChanged(): void {
            root.requestedMode = Colours.light ? "light" : "dark";
        }

        target: Colours
    }

    title: "壁纸和样式"

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.large

        StyledClippingRect {
            id: wallWrapper

            Layout.alignment: Qt.AlignHCenter
            implicitWidth: {
                const screen = root.nState.screen;
                return implicitHeight / screen.height * screen.width;
            }
            implicitHeight: {
                const screen = root.nState.screen;
                const cWidth = root.cappedWidth;
                return Math.min(Math.round(cWidth * 0.4), cWidth / screen.width * screen.height);
            }

            color: Colours.tPalette.m3surfaceContainer
            radius: Tokens.rounding.large

            Loader {
                anchors.centerIn: parent
                opacity: Config.background.wallpaperEnabled ? 0 : 1
                active: opacity > 0

                sourceComponent: ColumnLayout {
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "hide_image"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.extraLarge
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Wallpaper disabled")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.large
                    }
                }

                Behavior on opacity {
                    Anim {
                        type: Anim.SlowEffects
                    }
                }
            }

            Item {
                anchors.fill: parent
                opacity: Config.background.wallpaperEnabled ? 1 : 0

                Behavior on opacity {
                    Anim {
                        type: Anim.SlowEffects
                    }
                }

                Loader {
                    id: wallIndicatorLoader

                    anchors.centerIn: parent

                    opacity: 0
                    active: opacity > 0

                    sourceComponent: StyledRect {
                        implicitWidth: wallLoadingIndicator.implicitSize + Tokens.padding.largeIncreased * 2
                        implicitHeight: wallLoadingIndicator.implicitSize + Tokens.padding.largeIncreased * 2

                        color: Colours.palette.m3primaryContainer
                        radius: Tokens.rounding.full

                        LoadingIndicator {
                            id: wallLoadingIndicator

                            anchors.centerIn: parent
                            containsIcon: true
                            implicitSize: Math.min(wallWrapper.implicitWidth, wallWrapper.implicitHeight) * 0.4
                        }
                    }

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }

                Timer {
                    id: wallLoadDebounceTimer

                    interval: 100
                    onTriggered: {
                        if (wallImg.status !== Image.Ready)
                            wallIndicatorLoader.opacity = 1;
                    }
                }

                FadeImage {
                    id: wallImg

                    anchors.fill: parent
                    source: Wallpapers.current
                    preventInit: wallIndicatorLoader.opacity > 0
                    fadeOutAnim: Anim.DefaultEffects
                    fadeInAnim: Anim.SlowEffects

                    onSourceChanged: wallLoadDebounceTimer.restart()

                    onStatusChanged: {
                        if (status === Image.Ready) {
                            wallLoadDebounceTimer.stop();
                            wallIndicatorLoader.opacity = 0;
                        }
                    }
                }
            }
        }

        ButtonRow {
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacing.small

            IconTextButton {
                icon: "wallpaper"
                text: "选择壁纸"
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                type: IconTextButton.Tonal
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                disabled: !Config.background.wallpaperEnabled
                onClicked: root.nState.openSubPage(1) // Wallpaper page
            }
        }

        SectionHeader {
            text: "外观"
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            implicitHeight: themeLayout.implicitHeight + Tokens.padding.large * 2

            RowLayout {
                id: themeLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.large

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        text: "主题模式"
                        font: Tokens.font.body.medium
                    }

                    StyledText {
                        text: "自动模式会按照本地时间切换明暗"
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                    }
                }

                ButtonRow {
                    spacing: 0

                    IconTextButton {
                        icon: "dark_mode"
                        text: "深色"
                        isToggle: false
                        checked: !Colours.autoMode && !Colours.light
                        type: IconTextButton.Tonal
                        onClicked: {
                            root.requestedMode = "dark";
                            Colours.setAutoMode(false);
                            Colours.setMode("dark");
                        }
                    }

                    IconTextButton {
                        icon: "light_mode"
                        text: "亮色"
                        isToggle: false
                        checked: !Colours.autoMode && Colours.light
                        type: IconTextButton.Tonal
                        onClicked: {
                            root.requestedMode = "light";
                            Colours.setAutoMode(false);
                            Colours.setMode("light");
                        }
                    }

                    IconTextButton {
                        icon: "brightness_auto"
                        text: "自动"
                        isToggle: false
                        checked: Colours.autoMode
                        type: IconTextButton.Tonal
                        onClicked: {
                            root.requestedMode = "";
                            Colours.setAutoMode(true);
                        }
                    }
                }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            implicitHeight: colourLayout.implicitHeight + Tokens.padding.large * 2

            RowLayout {
                id: colourLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.large

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        text: "主题色"
                        font: Tokens.font.body.medium
                    }

                    StyledText {
                        text: "选择一套预设强调色"
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                    }
                }

                ButtonRow {
                    spacing: Tokens.spacing.extraSmall

                    PresetButton {
                        presetName: "blue"
                        presetColour: "#366385"
                        text: "海蓝"
                    }

                    PresetButton {
                        presetName: "teal"
                        presetColour: "#1c6a66"
                        text: "青绿"
                    }

                    PresetButton {
                        presetName: "violet"
                        presetColour: "#7657a8"
                        text: "紫罗兰"
                    }

                    PresetButton {
                        presetName: "green"
                        presetColour: "#437653"
                        text: "森林"
                    }

                    PresetButton {
                        presetName: "rose"
                        presetColour: "#9a526f"
                        text: "玫瑰"
                    }
                }
            }
        }

        SliderRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            last: true
            icon: "opacity"
            label: "透明度"
            value: GlobalConfig.appearance.transparency.enabled ? Math.min(root.maximumTransparency, 1 - GlobalConfig.appearance.transparency.base) / root.maximumTransparency : 0
            valueLabel: `${Math.round(value * root.maximumTransparency * 100)}%`
            onMoved: v => {
                GlobalConfig.appearance.transparency.enabled = v > 0.005;
                GlobalConfig.appearance.transparency.base = 1 - v * root.maximumTransparency;
            }
        }
    }

    component PresetButton: IconTextButton {
        required property string presetName
        required property color presetColour

        icon: "circle"
        isToggle: false
        checked: Colours.preset === presetName
        type: IconTextButton.Tonal
        activeColour: presetColour
        inactiveColour: Qt.alpha(presetColour, 0.18)
        activeOnColour: "white"
        inactiveOnColour: Colours.palette.m3onSurfaceVariant
        onClicked: {
            Colours.setPreset(presetName, root.desiredMode);
        }
    }
}
