pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

StyledRect {
    id: root

    readonly property string barPosition: {
        const value = String(Config.bar.position || "left").toLowerCase();
        if (value === "right" || value === "top")
            return value;
        return "left";
    }
    readonly property bool isVertical: barPosition !== "top"

    readonly property color colour: Colours.palette.m3tertiary
    readonly property int padding: Config.bar.clock.background ? Tokens.padding.medium : Tokens.padding.extraSmall
    readonly property var font: Tokens.font.body.builders.small.scale(1.1)

    implicitWidth: root.isVertical ? Tokens.sizes.bar.innerWidth : (layout.implicitWidth + root.padding * 2)
    implicitHeight: root.isVertical ? (layout.implicitHeight + root.padding * 2) : Tokens.sizes.bar.innerWidth

    color: Qt.alpha(Colours.tPalette.m3surfaceContainer, Config.bar.clock.background ? Colours.tPalette.m3surfaceContainer.a : 0)
    radius: Tokens.rounding.full

    GridLayout {
        id: layout

        anchors.centerIn: parent
        columns: root.isVertical ? 1 : 100
        rows: root.isVertical ? 100 : 1
        flow: root.isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        columnSpacing: Tokens.spacing.extraSmall
        rowSpacing: Tokens.spacing.extraSmall

        Loader {
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            asynchronous: true
            active: Config.bar.clock.showIcon
            visible: active

            sourceComponent: MaterialIcon {
                text: "calendar_month"
                color: root.colour
            }
        }

        Loader {
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            asynchronous: true
            active: Config.bar.clock.showDate
            visible: active

            sourceComponent: GridLayout {
                columns: root.isVertical ? 1 : 100
                rows: root.isVertical ? 100 : 1
                flow: root.isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                columnSpacing: Math.max(0, (root.isVertical ? layout.rowSpacing : layout.columnSpacing) - 4)
                rowSpacing: Math.max(0, (root.isVertical ? layout.rowSpacing : layout.columnSpacing) - 4)

                StyledText {
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                    text: Time.format("ddd")
                    font: Tokens.font.body.builders.small.scale(0.9).build()
                    color: root.colour
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                    text: Time.format("d")
                    font: root.font.scale(1.1).build()
                    color: root.colour
                }

                // Vertical: thin horizontal rule. Horizontal: thin vertical rule.
                StyledRect {
                    Layout.fillWidth: root.isVertical
                    Layout.fillHeight: !root.isVertical
                    Layout.preferredWidth: root.isVertical ? -1 : 1
                    Layout.preferredHeight: root.isVertical ? 1 : -1
                    Layout.leftMargin: root.isVertical ? -Tokens.padding.extraSmall : Tokens.padding.extraSmall / 2
                    Layout.rightMargin: root.isVertical ? -Tokens.padding.extraSmall : Tokens.padding.extraSmall / 2
                    Layout.topMargin: root.isVertical ? 4 : Tokens.padding.extraSmall / 2
                    Layout.bottomMargin: root.isVertical ? Tokens.padding.extraSmall / 2 : Tokens.padding.extraSmall / 2
                    implicitWidth: root.isVertical ? 0 : 1
                    implicitHeight: root.isVertical ? 1 : 0
                    color: Colours.palette.m3outlineVariant
                }
            }
        }

        // Horizontal bar: single "03:54" so digits are not jammed into "0354".
        // Vertical bar: stacked hour / minute (original look).
        Loader {
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            active: !root.isVertical
            visible: active

            sourceComponent: StyledText {
                text: GlobalConfig.services.useTwelveHourClock ? Time.format("h:mm") : Time.format("HH:mm")
                font: root.font.build()
                color: root.colour
            }
        }

        Loader {
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            active: root.isVertical
            visible: active

            sourceComponent: ColumnLayout {
                spacing: 0

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Time.hourStr
                    font: {
                        const scale = text === "11" ? 1.15 : Math.min(1.05, Math.max(hourMetrics.width, minMetrics.width) / Math.max(1, hourMetrics.width));
                        return root.font.width(scale * 100).letterSpacing(scale).build();
                    }
                    color: root.colour

                    TextMetrics {
                        id: hourMetrics
                        font: root.font.build()
                        text: Time.hourStr
                    }
                }

                StyledText {
                    Layout.topMargin: -4
                    Layout.alignment: Qt.AlignHCenter
                    text: Time.minuteStr
                    font: {
                        const scale = text === "11" ? 1.15 : Math.min(1.05, Math.max(hourMetrics.width, minMetrics.width) / Math.max(1, minMetrics.width));
                        return root.font.width(scale * 100).letterSpacing(scale).build();
                    }
                    color: root.colour

                    TextMetrics {
                        id: minMetrics
                        font: root.font.build()
                        text: Time.minuteStr
                    }
                }
            }
        }

        Loader {
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            asynchronous: true
            active: GlobalConfig.services.useTwelveHourClock
            visible: active

            sourceComponent: StyledText {
                text: Time.amPmStr.toLowerCase()
                font: Tokens.font.body.builders.small.scale(0.9).build()
                color: root.colour
            }
        }
    }
}
