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

    // Temperature units (index 0 = Celsius, 1 = Fahrenheit — matches Weather.formatTemp)
    readonly property list<MenuItem> tempItems: [
        MenuItem {
            text: "°C"
        },
        MenuItem {
            text: "°F"
        }
    ]

    // Clock format (index 0 = 24-hour, 1 = 12-hour — matches Time.useTwelveHourClock)
    readonly property list<MenuItem> clockItems: [
        MenuItem {
            text: "24 小时"
        },
        MenuItem {
            text: "12 小时"
        }
    ]

    title: "语言和地区"

    readonly property Timer weatherDesktopReloadTimer: Timer {
        interval: 500
        onTriggered: Quickshell.execDetached(["villode-desktop", "--reload"])
    }

    function saveWeatherLocation(location: string): void {
        const normalized = location.trim();
        weatherLocation.text = normalized;
        Weather.loc = "";
        Weather.city = normalized;

        if (GlobalConfig.services.weatherLocation === normalized)
            Weather.reload();
        else
            GlobalConfig.services.weatherLocation = normalized;

        weatherDesktopReloadTimer.restart();
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Language
        SectionHeader {
            first: true
            text: "语言"
        }

        // Read-only: the shell follows the system locale (no in-shell translations yet)
        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: localeLayout.implicitHeight + localeLayout.anchors.margins * 2

            RowLayout {
                id: localeLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: "系统语言"
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: "跟随系统区域设置（%1）".arg(Qt.locale().name)
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                        elide: Text.ElideRight
                    }
                }

                StyledText {
                    text: Qt.locale().nativeLanguageName || Qt.locale().name
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }
            }
        }

        // Weather
        SectionHeader {
            text: "天气"
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: weatherLocationLayout.implicitHeight + Tokens.padding.large * 2

            ColumnLayout {
                id: weatherLocationLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.small

                M3TextField {
                    id: weatherLocation

                    Layout.fillWidth: true
                    label: "天气位置"
                    placeholder: "城市或纬度,经度"
                    text: GlobalConfig.services.weatherLocation
                    leadingIcon: "location_on"
                    supportingText: "留空则按 IP 地址自动定位"
                    onAccepted: root.saveWeatherLocation(text)
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: -Tokens.spacing.extraSmall
                    spacing: Tokens.spacing.small

                    Item {
                        Layout.fillWidth: true
                    }

                    IconTextButton {
                        icon: "my_location"
                        text: "使用 IP"
                        type: IconTextButton.Tonal
                        onClicked: root.saveWeatherLocation("")
                    }

                    IconTextButton {
                        icon: "check"
                        text: "保存"
                        type: IconTextButton.Filled
                        onClicked: root.saveWeatherLocation(weatherLocation.text)
                    }
                }
            }
        }

        // Units
        SectionHeader {
            text: "单位"
        }

        SelectRow {
            first: true
            label: "天气温度"
            subtext: "天气预报使用的温度单位"
            menuItems: root.tempItems
            active: root.tempItems[GlobalConfig.services.useFahrenheit ? 1 : 0]
            onSelected: item => GlobalConfig.services.useFahrenheit = root.tempItems.indexOf(item) === 1
        }

        SelectRow {
            last: true
            label: "系统温度"
            subtext: "CPU 和 GPU 使用的温度单位"
            menuItems: root.tempItems
            active: root.tempItems[GlobalConfig.services.useFahrenheitPerformance ? 1 : 0]
            onSelected: item => GlobalConfig.services.useFahrenheitPerformance = root.tempItems.indexOf(item) === 1
        }

        // Time & date
        SectionHeader {
            text: "时间和日期"
        }

        SelectRow {
            first: true
            last: true
            label: "时钟格式"
            subtext: "Shell 中时间的显示方式"
            menuItems: root.clockItems
            active: root.clockItems[GlobalConfig.services.useTwelveHourClock ? 1 : 0]
            onSelected: item => GlobalConfig.services.useTwelveHourClock = root.clockItems.indexOf(item) === 1
        }
    }
}
