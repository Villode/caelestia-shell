pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components.controls
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Taskbar")
    isSubPage: true

    readonly property list<string> positionValues: ["left", "right", "top"]
    readonly property list<MenuItem> positionItems: [
        MenuItem {
            text: qsTr("Left")
        },
        MenuItem {
            text: qsTr("Right")
        },
        MenuItem {
            text: qsTr("Top")
        }
    ]

    function positionIndex(value: string): int {
        const idx = positionValues.indexOf(String(value || "left").toLowerCase());
        return idx >= 0 ? idx : 0;
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Behaviour
        SectionHeader {
            first: true
            text: qsTr("Behaviour")
        }

        SelectRow {
            first: true
            label: qsTr("Position")
            subtext: qsTr("Experimental: place the taskbar on the left, right, or top edge")
            menuItems: root.positionItems
            active: root.positionItems[root.positionIndex(Config.bar.position)]
            onSelected: item => GlobalConfig.bar.position = root.positionValues[root.positionItems.indexOf(item)]
        }

        ToggleRow {
            text: qsTr("Persistent")
            subtext: qsTr("Keep the bar visible at all times")
            checked: Config.bar.persistent
            onToggled: GlobalConfig.bar.persistent = checked
        }

        ToggleRow {
            text: qsTr("Show on hover")
            subtext: qsTr("Reveal the bar when the cursor reaches the screen edge")
            checked: Config.bar.showOnHover
            onToggled: GlobalConfig.bar.showOnHover = checked
        }

        StepperRow {
            last: true
            label: qsTr("Drag threshold")
            subtext: qsTr("Pixels dragged before the bar reveals")
            value: Config.bar.dragThreshold
            from: 0
            to: 200
            stepSize: 5
            onMoved: v => GlobalConfig.bar.dragThreshold = v
        }

        // Components
        SectionHeader {
            text: qsTr("Components")
        }

        NavRow {
            first: true
            icon: "workspaces"
            label: qsTr("Workspaces")
            status: qsTr("Indicators, window icons")
            onClicked: root.nState.openSubPage(5)
        }

        NavRow {
            icon: "web_asset"
            label: qsTr("Active window")
            status: qsTr("Title display, popout")
            onClicked: root.nState.openSubPage(6)
        }

        NavRow {
            icon: "widgets"
            label: qsTr("Tray")
            status: qsTr("System tray icons")
            onClicked: root.nState.openSubPage(7)
        }

        NavRow {
            icon: "signal_cellular_alt"
            label: qsTr("Status icons")
            status: qsTr("Visible indicators")
            onClicked: root.nState.openSubPage(8)
        }

        NavRow {
            last: true
            icon: "schedule"
            label: qsTr("Clock")
            status: qsTr("Date, icon, background")
            onClicked: root.nState.openSubPage(9)
        }

        // Scroll actions
        SectionHeader {
            text: qsTr("Scroll actions")
        }

        ToggleRow {
            first: true
            last: true
            text: qsTr("Workspaces")
            subtext: qsTr("Scroll over the workspace indicator to switch workspaces")
            checked: Config.bar.scrollActions.workspaces
            onToggled: GlobalConfig.bar.scrollActions.workspaces = checked
        }

    }
}
