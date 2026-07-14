pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
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

    readonly property alias layout: layout
    readonly property alias items: items
    readonly property alias expandIcon: expandIcon

    readonly property int padding: Config.bar.tray.background ? Tokens.padding.medium : Tokens.padding.extraSmall
    readonly property int spacing: Config.bar.tray.background ? Tokens.spacing.small : 0

    property bool expanded

    readonly property real nonAnimExtent: {
        if (!Config.bar.tray.compact)
            return (root.isVertical ? layout.implicitHeight : layout.implicitWidth) + padding * 2;
        const expandSize = root.isVertical ? expandIcon.implicitHeight : expandIcon.implicitWidth;
        const layoutSize = root.isVertical ? layout.implicitHeight : layout.implicitWidth;
        return (expanded ? expandSize + layoutSize + spacing : expandSize) + padding * 2;
    }
    readonly property real nonAnimHeight: nonAnimExtent

    clip: true
    visible: (root.isVertical ? height : width) > 0

    implicitWidth: root.isVertical ? Tokens.sizes.bar.innerWidth : nonAnimExtent
    implicitHeight: root.isVertical ? nonAnimExtent : Tokens.sizes.bar.innerWidth

    color: Qt.alpha(Colours.tPalette.m3surfaceContainer, (Config.bar.tray.background && items.count > 0) ? Colours.tPalette.m3surfaceContainer.a : 0)
    radius: Tokens.rounding.full

    Grid {
        id: layout

        anchors.horizontalCenter: root.isVertical ? parent.horizontalCenter : undefined
        anchors.verticalCenter: root.isVertical ? undefined : parent.verticalCenter
        anchors.top: root.isVertical ? parent.top : undefined
        anchors.left: root.isVertical ? undefined : parent.left
        anchors.topMargin: root.isVertical ? root.padding : 0
        anchors.leftMargin: root.isVertical ? 0 : root.padding
        columns: root.isVertical ? 1 : 100
        rows: root.isVertical ? 100 : 1
        flow: root.isVertical ? Grid.TopToBottom : Grid.LeftToRight
        spacing: Tokens.spacing.small

        opacity: root.expanded || !Config.bar.tray.compact ? 1 : 0

        add: Transition {
            Anim {
                properties: "scale"
                from: 0
                to: 1
                easing: Tokens.anim.standardDecel
            }
        }

        move: Transition {
            Anim {
                properties: "scale"
                to: 1
                easing: Tokens.anim.standardDecel
            }
            Anim {
                properties: "x,y"
            }
        }

        Repeater {
            id: items

            model: ScriptModel {
                values: SystemTray.items.values.filter(i => !GlobalConfig.bar.tray.hiddenIcons.includes(i.id))
            }

            TrayItem {}
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    Loader {
        id: expandIcon

        asynchronous: true

        anchors.horizontalCenter: root.isVertical ? parent.horizontalCenter : undefined
        anchors.verticalCenter: root.isVertical ? undefined : parent.verticalCenter
        anchors.bottom: root.isVertical ? parent.bottom : undefined
        anchors.right: root.isVertical ? undefined : parent.right

        active: Config.bar.tray.compact && items.count > 0

        sourceComponent: Item {
            implicitWidth: expandIconInner.implicitWidth - (root.isVertical ? 0 : Tokens.padding.small)
            implicitHeight: expandIconInner.implicitHeight - (root.isVertical ? Tokens.padding.small : 0)

            MaterialIcon {
                id: expandIconInner

                anchors.horizontalCenter: root.isVertical ? parent.horizontalCenter : undefined
                anchors.verticalCenter: root.isVertical ? undefined : parent.verticalCenter
                anchors.bottom: root.isVertical ? parent.bottom : undefined
                anchors.right: root.isVertical ? undefined : parent.right
                anchors.bottomMargin: root.isVertical ? (Config.bar.tray.background ? Tokens.padding.extraSmall : -Tokens.padding.extraSmall) : 0
                anchors.rightMargin: root.isVertical ? 0 : (Config.bar.tray.background ? Tokens.padding.extraSmall : -Tokens.padding.extraSmall)
                text: root.isVertical ? "expand_less" : "chevron_left"
                fontStyle: Tokens.font.icon.large
                rotation: root.expanded ? 180 : 0

                Behavior on rotation {
                    Anim {}
                }

                Behavior on anchors.bottomMargin {
                    Anim {}
                }
            }
        }
    }

    Behavior on implicitWidth {
        Anim {}
    }

    Behavior on implicitHeight {
        Anim {}
    }
}
