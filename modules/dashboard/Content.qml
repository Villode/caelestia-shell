pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.filedialog
import qs.services

Item {
    id: root

    required property DrawerVisibilities visibilities
    required property DashboardState dashState
    required property FileDialog facePicker

    readonly property var dashboardTabs: {
        const allTabs = [
            {
                component: dashComponent,
                iconName: "dashboard",
                text: qsTr("Dashboard"),
                enabled: Config.dashboard.showDashboard
            },
            {
                component: mediaComponent,
                iconName: "queue_music",
                text: qsTr("Media"),
                enabled: Config.dashboard.showMedia
            },
            {
                component: performanceComponent,
                iconName: "speed",
                text: qsTr("Performance"),
                enabled: Config.dashboard.showPerformance
            },
            {
                component: weatherComponent,
                iconName: "cloud",
                text: qsTr("Weather"),
                enabled: Config.dashboard.showWeather
            }
        ];
        return allTabs.filter(tab => tab.enabled);
    }

    readonly property real contentPad: Tokens.padding.large
    readonly property real tabsTopMargin: CUtils.clamp(contentPad - Config.border.thickness, 0, contentPad)
    readonly property real activePaneWidth: {
        const it = view.currentItem;
        if (!it)
            return 0;
        return it.item ? it.item.implicitWidth : it.implicitWidth;
    }
    readonly property real activePaneHeight: {
        const it = view.currentItem;
        if (!it)
            return 0;
        return it.item ? it.item.implicitHeight : it.implicitHeight;
    }
    // MUST bind to active pane height directly. Column.implicitHeight was sticky
    // after tab switch (stayed on Dashboard height while Performance content
    // shrank) — that left ~160px of empty glass under the cards outside.
    readonly property real nonAnimWidth: activePaneWidth + contentPad * 2
    readonly property real nonAnimHeight: tabsTopMargin + tabs.implicitHeight + contentPad + activePaneHeight

    implicitWidth: nonAnimWidth
    implicitHeight: nonAnimHeight

    Tabs {
        id: tabs

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: root.tabsTopMargin
        anchors.leftMargin: root.contentPad
        anchors.rightMargin: root.contentPad

        nonAnimWidth: root.nonAnimWidth - root.contentPad * 2
        dashState: root.dashState
        tabs: root.dashboardTabs
    }

    ClippingRectangle {
        id: viewWrapper

        anchors.top: tabs.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: root.contentPad
        anchors.leftMargin: root.contentPad
        anchors.rightMargin: root.contentPad
        height: root.activePaneHeight
        radius: Tokens.rounding.large
        color: "transparent"

        Flickable {
            id: view

            readonly property int currentIndex: root.dashState.currentTab
            readonly property Item currentItem: {
                repeater.count;
                return repeater.itemAt(currentIndex);
            }

            anchors.fill: parent
            flickableDirection: Flickable.HorizontalFlick
            clip: true

            implicitWidth: root.activePaneWidth
            implicitHeight: root.activePaneHeight

            contentX: currentItem ? currentItem.x : 0
            contentWidth: row.width
            contentHeight: root.activePaneHeight

            onContentXChanged: {
                if (!moving || !currentItem)
                    return;
                const x = contentX - currentItem.x;
                if (x > currentItem.width / 2)
                    root.dashState.currentTab = Math.min(root.dashState.currentTab + 1, tabs.count - 1);
                else if (x < -currentItem.width / 2)
                    root.dashState.currentTab = Math.max(root.dashState.currentTab - 1, 0);
            }

            onDragEnded: {
                if (!currentItem)
                    return;
                const x = contentX - currentItem.x;
                if (x > currentItem.width / 10)
                    root.dashState.currentTab = Math.min(root.dashState.currentTab + 1, tabs.count - 1);
                else if (x < -currentItem.width / 10)
                    root.dashState.currentTab = Math.max(root.dashState.currentTab - 1, 0);
                else
                    contentX = Qt.binding(() => currentItem ? currentItem.x : 0);
            }

            Row {
                id: row

                Repeater {
                    id: repeater

                    model: ScriptModel {
                        values: root.dashboardTabs
                    }

                    delegate: Loader {
                        id: paneLoader

                        required property int index
                        required property var modelData

                        width: item ? item.implicitWidth : 0
                        height: item ? item.implicitHeight : 0
                        opacity: index === view.currentIndex ? 1 : 0
                        sourceComponent: modelData.component

                        Component.onCompleted: active = Qt.binding(() => {
                            if (index === view.currentIndex)
                                return true;
                            const vx = Math.floor(view.visibleArea.xPosition * view.contentWidth);
                            const vex = Math.floor(vx + view.visibleArea.widthRatio * view.contentWidth);
                            return (vx >= x && vx <= x + width) || (vex >= x && vex <= x + width);
                        })
                    }
                }
            }

            Component {
                id: dashComponent

                Dash {
                    visibilities: root.visibilities
                    dashState: root.dashState
                    facePicker: root.facePicker
                }
            }

            Component {
                id: mediaComponent

                Media {
                    visibilities: root.visibilities
                }
            }

            Component {
                id: performanceComponent

                Performance {}
            }

            Component {
                id: weatherComponent

                WeatherTab {}
            }

            Behavior on contentX {
                Anim {}
            }
        }
    }

    Behavior on implicitWidth {
        Anim {}
    }

    // Instant height: animating Media/Dashboard→Performance left a tall empty glass slab.
    Behavior on implicitHeight {
        enabled: false
    }
}
