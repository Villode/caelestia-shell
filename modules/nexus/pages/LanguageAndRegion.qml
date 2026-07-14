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

    readonly property list<string> languageValues: ["system", "zh_CN", "en_US"]
    readonly property list<MenuItem> languageItems: [
        MenuItem {
            text: qsTr("Follow system")
        },
        MenuItem {
            text: qsTr("Simplified Chinese")
        },
        MenuItem {
            text: qsTr("English")
        }
    ]

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
            text: qsTr("24-hour")
        },
        MenuItem {
            text: qsTr("12-hour")
        }
    ]

    title: qsTr("Language and region")

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
            text: qsTr("Language")
        }

        SelectRow {
            first: true
            last: true
            label: qsTr("Display language")
            subtext: qsTr("Change the Shell language immediately")
            menuItems: root.languageItems
            active: root.languageItems[Math.max(0, root.languageValues.indexOf(GlobalConfig.services.uiLanguage))]
            onSelected: item => GlobalConfig.services.uiLanguage = root.languageValues[root.languageItems.indexOf(item)]
        }

        // Weather
        SectionHeader {
            text: qsTr("Weather")
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
                    label: qsTr("Weather location")
                    placeholder: qsTr("City or latitude,longitude")
                    text: GlobalConfig.services.weatherLocation
                    leadingIcon: "location_on"
                    supportingText: qsTr("Leave empty to locate automatically by IP address")
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
                        text: qsTr("Use IP")
                        type: IconTextButton.Tonal
                        onClicked: root.saveWeatherLocation("")
                    }

                    IconTextButton {
                        icon: "check"
                        text: qsTr("Save")
                        type: IconTextButton.Filled
                        onClicked: root.saveWeatherLocation(weatherLocation.text)
                    }
                }
            }
        }

        // Units
        SectionHeader {
            text: qsTr("Units")
        }

        SelectRow {
            first: true
            label: qsTr("Weather temperature")
            subtext: qsTr("Temperature unit used by weather forecasts")
            menuItems: root.tempItems
            active: root.tempItems[GlobalConfig.services.useFahrenheit ? 1 : 0]
            onSelected: item => GlobalConfig.services.useFahrenheit = root.tempItems.indexOf(item) === 1
        }

        SelectRow {
            last: true
            label: qsTr("System temperature")
            subtext: qsTr("Temperature unit used by the CPU and GPU")
            menuItems: root.tempItems
            active: root.tempItems[GlobalConfig.services.useFahrenheitPerformance ? 1 : 0]
            onSelected: item => GlobalConfig.services.useFahrenheitPerformance = root.tempItems.indexOf(item) === 1
        }

        // Time & date
        SectionHeader {
            text: qsTr("Time and date")
        }

        SelectRow {
            first: true
            last: true
            label: qsTr("Clock format")
            subtext: qsTr("How time is displayed in the Shell")
            menuItems: root.clockItems
            active: root.clockItems[GlobalConfig.services.useTwelveHourClock ? 1 : 0]
            onSelected: item => GlobalConfig.services.useTwelveHourClock = root.clockItems.indexOf(item) === 1
        }
    }
}
