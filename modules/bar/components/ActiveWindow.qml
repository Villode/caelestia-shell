pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

Item {
    id: root

    required property var bar
    required property Brightness.Monitor monitor
    property color colour: Colours.palette.m3primary
    readonly property bool isVertical: bar.isVertical !== false

    readonly property string windowTitle: {
        const title = Hypr.activeToplevel?.title;
        if (!title)
            return qsTr("Desktop");
        if (Config.bar.activeWindow.compact) {
            // " - " (standard hyphen), " — " (em dash), " – " (en dash)
            const parts = title.split(/\s+[\-\u2013\u2014]\s+/);
            if (parts.length > 1)
                return parts[parts.length - 1].trim();
        }
        return title;
    }

    readonly property int maxExtent: {
        const otherModules = bar.children.filter(c => c.entryId && c.item !== this && c.entryId !== "spacer");
        const otherSize = otherModules.reduce((acc, curr) => acc + (curr.item.nonAnimHeight ?? (root.isVertical ? curr.height : curr.width)), 0);
        // Length - 2 cause repeater counts as a child
        const available = root.isVertical ? bar.height : bar.width;
        return available - otherSize - bar.spacing * Math.max(0, otherModules.length) - bar.vPadding * 2;
    }
    readonly property int maxHeight: maxExtent
    property Title current: text1

    clip: true
    implicitWidth: root.isVertical ? Math.max(icon.implicitWidth, current.implicitHeight) : icon.implicitWidth + current.implicitWidth + current.anchors.leftMargin
    implicitHeight: root.isVertical ? icon.implicitHeight + current.implicitWidth + current.anchors.topMargin : Math.max(icon.implicitHeight, current.implicitHeight)

    Loader {
        asynchronous: true
        anchors.fill: parent
        active: !Config.bar.activeWindow.showOnHover

        sourceComponent: MouseArea {
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onPositionChanged: {
                const popouts = root.bar.popouts;
                if (popouts.hasCurrent && popouts.currentName !== "activewindow")
                    popouts.hasCurrent = false;
            }
            onClicked: {
                const popouts = root.bar.popouts;
                if (popouts.hasCurrent) {
                    popouts.hasCurrent = false;
                } else {
                    popouts.currentName = "activewindow";
                    const p = root.mapToItem(root.bar, root.implicitWidth / 2, root.implicitHeight / 2);
                    popouts.currentCenter = root.isVertical ? p.y : p.x;
                    popouts.hasCurrent = true;
                }
            }
        }
    }

    MaterialIcon {
        id: icon

        anchors.horizontalCenter: root.isVertical ? parent.horizontalCenter : undefined
        anchors.verticalCenter: root.isVertical ? undefined : parent.verticalCenter
        anchors.left: root.isVertical ? undefined : parent.left

        animate: true
        text: Icons.getAppCategoryIcon(Hypr.activeToplevel?.lastIpcObject.class, "desktop_windows")
        color: root.colour
    }

    Title {
        id: text1
    }

    Title {
        id: text2
    }

    TextMetrics {
        id: metrics

        text: root.windowTitle
        font: root.Tokens.font.body.builders.small.letterSpacing(1.4).build()
        elide: Qt.ElideRight
        elideWidth: Math.max(0, root.maxExtent - (root.isVertical ? icon.height : icon.width))

        onTextChanged: {
            const next = root.current === text1 ? text2 : text1;
            next.text = elidedText;
            root.current = next;
        }
        onElideWidthChanged: root.current.text = elidedText
    }

    Behavior on implicitHeight {
        Anim {}
    }

    Behavior on implicitWidth {
        Anim {}
    }

    component Title: StyledText {
        id: text

        anchors.horizontalCenter: root.isVertical ? icon.horizontalCenter : undefined
        anchors.verticalCenter: root.isVertical ? undefined : icon.verticalCenter
        anchors.top: root.isVertical ? icon.bottom : undefined
        anchors.left: root.isVertical ? undefined : icon.right
        anchors.topMargin: root.isVertical ? Tokens.spacing.small : 0
        anchors.leftMargin: root.isVertical ? 0 : Tokens.spacing.small

        font: metrics.font
        color: root.colour
        opacity: root.current === this ? 1 : 0

        transform: [
            Translate {
                id: rotateShift
                x: 0
            },
            Rotation {
                id: rotateTitle
                angle: 0
                origin.x: text.implicitHeight / 2
                origin.y: text.implicitHeight / 2
            }
        ]

        states: [
            State {
                name: "vertical"
                when: root.isVertical
                PropertyChanges {
                    rotateTitle.angle: root.Config.bar.activeWindow.inverted ? 270 : 90
                    rotateShift.x: root.Config.bar.activeWindow.inverted ? -text.implicitWidth + text.implicitHeight : 0
                    text.width: text.implicitHeight
                    text.height: text.implicitWidth
                }
            },
            State {
                name: "horizontal"
                when: !root.isVertical
                PropertyChanges {
                    rotateTitle.angle: 0
                    rotateShift.x: 0
                    text.width: text.implicitWidth
                    text.height: text.implicitHeight
                }
            }
        ]

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }
}
