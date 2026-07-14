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
            Layout.alignment: Qt.AlignHCenter
            asynchronous: true
            active: Config.bar.clock.showIcon
            visible: active

            sourceComponent: MaterialIcon {
                text: "calendar_month"
                color: root.colour
            }
        }

        Loader {
            Layout.alignment: Qt.AlignHCenter
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
                    Layout.alignment: Qt.AlignHCenter
                    text: Time.format("ddd")
                    font: Tokens.font.body.builders.small.scale(0.9).build()
                    color: root.colour
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Time.format("d")
                    font: root.font.scale(1.1).build()
                    color: root.colour
                }

                StyledRect {
                    Layout.fillWidth: root.isVertical
                    Layout.fillHeight: !root.isVertical
                    Layout.leftMargin: root.isVertical ? -Tokens.padding.extraSmall : Tokens.padding.extraSmall / 2
                    Layout.rightMargin: root.isVertical ? -Tokens.padding.extraSmall : Tokens.padding.extraSmall / 2
                    Layout.topMargin: root.isVertical ? 4 : -Tokens.padding.extraSmall
                    Layout.bottomMargin: root.isVertical ? Tokens.padding.extraSmall / 2 : -Tokens.padding.extraSmall
                    implicitWidth: root.isVertical ? 0 : 1
                    implicitHeight: root.isVertical ? 1 : 0
                    color: Colours.palette.m3outlineVariant
                }
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Time.hourStr
            font: {
                const scale = text === "11" ? 1.15 : Math.min(1.05, Math.max(hourMetrics.width, minMetrics.width) / hourMetrics.width);
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
            Layout.topMargin: root.isVertical ? -parent.rowSpacing - 4 : 0
            Layout.leftMargin: root.isVertical ? 0 : -parent.columnSpacing - 4
            Layout.alignment: Qt.AlignHCenter
            text: Time.minuteStr
            font: {
                const scale = text === "11" ? 1.15 : Math.min(1.05, Math.max(hourMetrics.width, minMetrics.width) / minMetrics.width);
                return root.font.width(scale * 100).letterSpacing(scale).build();
            }
            color: root.colour

            TextMetrics {
                id: minMetrics

                font: root.font.build()
                text: Time.minuteStr
            }
        }

        Loader {
            Layout.topMargin: root.isVertical ? -parent.rowSpacing - 4 : 0
            Layout.leftMargin: root.isVertical ? 0 : -parent.columnSpacing - 4
            Layout.alignment: Qt.AlignHCenter
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
