import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
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

    readonly property list<MenuItem> tempItems: [
        MenuItem {
            text: "°C"
        },
        MenuItem {
            text: "°F"
        }
    ]

    readonly property list<MenuItem> clockItems: [
        MenuItem {
            text: qsTr("24-hour")
        },
        MenuItem {
            text: qsTr("12-hour")
        }
    ]

    // System date/time (timedatectl via villode-datetime)
    property string sysTimezone: ""
    property string sysLocalTime: ""
    property string sysUtcTime: ""
    property bool sysNtp: false
    property bool sysSynced: false
    property bool sysBusy: false
    property string sysError: ""
    property list<string> timezoneMatches: []
    property string timezoneFilter: ""

    readonly property list<string> commonTimezones: [
        "Asia/Shanghai",
        "Asia/Hong_Kong",
        "Asia/Taipei",
        "Asia/Tokyo",
        "Asia/Seoul",
        "Asia/Singapore",
        "Asia/Kolkata",
        "Asia/Dubai",
        "Europe/London",
        "Europe/Paris",
        "Europe/Berlin",
        "Europe/Moscow",
        "America/New_York",
        "America/Chicago",
        "America/Denver",
        "America/Los_Angeles",
        "America/Sao_Paulo",
        "Australia/Sydney",
        "Pacific/Auckland",
        "UTC"
    ]

    title: qsTr("Language and region")

    readonly property Timer weatherDesktopReloadTimer: Timer {
        interval: 500
        onTriggered: Quickshell.execDetached(["villode-desktop", "--reload"])
    }

    readonly property Timer clockTick: Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            // Refresh local display once a second without shelling out every tick
            if (root.sysLocalTime)
                root.sysLocalTime = Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm:ss");
        }
    }

    property Process statusProc: Process {
        id: statusProc
        command: ["villode-datetime", "status-json"]
        stdout: StdioCollector {
            onStreamFinished: root.parseStatus(text)
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    root.sysError = text.trim();
            }
        }
        onExited: code => {
            root.sysBusy = false;
            if (code !== 0 && !root.sysError)
                root.sysError = qsTr("Could not read system time settings.");
        }
    }

    property Process tzListProc: Process {
        id: tzListProc
        command: ["villode-datetime", "list-timezones", root.timezoneFilter]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(l => l.trim());
                root.timezoneMatches = lines.slice(0, 40);
            }
        }
    }

    property Process actionProc: Process {
        id: actionProc
        stdout: StdioCollector {}
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    root.sysError = text.trim().split("\n").filter(l => l.trim()).slice(-1)[0] || text.trim();
            }
        }
        onExited: code => {
            root.sysBusy = false;
            if (code === 0)
                root.sysError = "";
            root.refreshStatus();
        }
    }

    function refreshStatus(): void {
        if (statusProc.running)
            return;
        root.sysBusy = true;
        root.sysError = "";
        statusProc.running = true;
    }

    function parseStatus(text: string): void {
        try {
            const d = JSON.parse(text);
            root.sysTimezone = d.timezone || "";
            root.sysLocalTime = d.localTime || "";
            root.sysUtcTime = d.utcTime || "";
            root.sysNtp = !!d.ntp;
            root.sysSynced = !!d.synchronized;
            root.sysError = d.error || "";
        } catch (e) {
            root.sysError = qsTr("Could not parse time status.");
        }
    }

    function setTimezone(tz: string): void {
        if (!tz)
            return;
        root.sysBusy = true;
        root.sysError = "";
        actionProc.command = ["villode-datetime", "set-timezone", tz];
        actionProc.running = true;
    }

    function setNtp(on: bool): void {
        root.sysBusy = true;
        root.sysError = "";
        actionProc.command = ["villode-datetime", "set-ntp", on ? "on" : "off"];
        actionProc.running = true;
    }

    function setManualTime(value: string): void {
        const t = value.trim();
        if (!t)
            return;
        root.sysBusy = true;
        root.sysError = "";
        actionProc.command = ["villode-datetime", "set-time", t];
        actionProc.running = true;
    }

    function searchTimezones(q: string): void {
        root.timezoneFilter = q.trim();
        if (!root.timezoneFilter) {
            root.timezoneMatches = [];
            return;
        }
        if (tzListProc.running)
            return;
        tzListProc.running = true;
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

    Component.onCompleted: refreshStatus()

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

        // Date & time (system)
        SectionHeader {
            text: qsTr("Date and time")
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: false
            implicitHeight: timeStatusCol.implicitHeight + Tokens.padding.large * 2

            ColumnLayout {
                id: timeStatusCol
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: root.sysSynced ? "schedule" : "schedule"
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.large
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: root.sysLocalTime || qsTr("Reading system time…")
                            font: Tokens.font.body.large
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                const tz = root.sysTimezone || "—";
                                const sync = root.sysNtp
                                    ? (root.sysSynced ? qsTr("Network time on · synced") : qsTr("Network time on · syncing…"))
                                    : qsTr("Network time off · manual");
                                return `${tz} · ${sync}`;
                            }
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    IconTextButton {
                        icon: "refresh"
                        text: qsTr("Refresh")
                        type: IconTextButton.Tonal
                        enabled: !root.sysBusy
                        onClicked: root.refreshStatus()
                    }
                }

                StyledText {
                    visible: root.sysError.length > 0
                    Layout.fillWidth: true
                    text: root.sysError
                    color: Colours.palette.m3error
                    font: Tokens.font.label.small
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("UTC %1").arg(root.sysUtcTime || "—")
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                    elide: Text.ElideRight
                }
            }
        }

        ToggleRow {
            text: qsTr("Set time automatically")
            subtext: qsTr("Use network time (NTP). Recommended.")
            checked: root.sysNtp
            enabled: !root.sysBusy
            onToggled: root.setNtp(checked)
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: false
            last: false
            implicitHeight: tzCol.implicitHeight + Tokens.padding.large * 2

            ColumnLayout {
                id: tzCol
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.small

                StyledText {
                    text: qsTr("Time zone")
                    font: Tokens.font.body.small
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Current: %1").arg(root.sysTimezone || "—")
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                }

                // Quick common zones
                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    Repeater {
                        model: root.commonTimezones

                        IconTextButton {
                            required property string modelData
                            text: modelData.split("/").slice(-1)[0].replace(/_/g, " ")
                            type: modelData === root.sysTimezone ? IconTextButton.Filled : IconTextButton.Tonal
                            enabled: !root.sysBusy
                            onClicked: root.setTimezone(modelData)
                        }
                    }
                }

                M3TextField {
                    id: tzSearch
                    Layout.fillWidth: true
                    label: qsTr("Search time zone")
                    placeholder: qsTr("e.g. Shanghai, Tokyo, New_York")
                    leadingIcon: "search"
                    onTextChanged: root.searchTimezones(text)
                    onAccepted: {
                        if (root.timezoneMatches.length === 1)
                            root.setTimezone(root.timezoneMatches[0]);
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall
                    visible: root.timezoneMatches.length > 0

                    Repeater {
                        model: root.timezoneMatches

                        Item {
                            required property string modelData
                            Layout.fillWidth: true
                            implicitHeight: tzRow.implicitHeight + Tokens.padding.small

                            StateLayer {
                                anchors.fill: parent
                                radius: Tokens.rounding.medium
                                enabled: !root.sysBusy
                                onClicked: root.setTimezone(parent.modelData)
                            }

                            RowLayout {
                                id: tzRow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter

                                StyledText {
                                    Layout.fillWidth: true
                                    text: parent.parent.modelData
                                    font: Tokens.font.label.medium
                                    elide: Text.ElideRight
                                }

                                MaterialIcon {
                                    text: parent.parent.modelData === root.sysTimezone ? "check" : "chevron_right"
                                    color: Colours.palette.m3outline
                                    fontStyle: Tokens.font.icon.small
                                }
                            }
                        }
                    }
                }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: false
            last: true
            implicitHeight: manualCol.implicitHeight + Tokens.padding.large * 2

            ColumnLayout {
                id: manualCol
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.small

                StyledText {
                    text: qsTr("Set date and time manually")
                    font: Tokens.font.body.small
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Turns off network time. Format: YYYY-MM-DD HH:MM:SS")
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                    wrapMode: Text.WordWrap
                }

                M3TextField {
                    id: manualTime
                    Layout.fillWidth: true
                    label: qsTr("Date and time")
                    placeholder: Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm:ss")
                    leadingIcon: "edit_calendar"
                    onAccepted: root.setManualTime(text)
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Item {
                        Layout.fillWidth: true
                    }

                    IconTextButton {
                        icon: "schedule"
                        text: qsTr("Use now")
                        type: IconTextButton.Tonal
                        onClicked: manualTime.text = Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm:ss")
                    }

                    IconTextButton {
                        icon: "check"
                        text: qsTr("Apply")
                        type: IconTextButton.Filled
                        enabled: !root.sysBusy && manualTime.text.trim().length > 0
                        onClicked: root.setManualTime(manualTime.text)
                    }
                }
            }
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

        // Clock display in shell
        SectionHeader {
            text: qsTr("Clock display")
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
