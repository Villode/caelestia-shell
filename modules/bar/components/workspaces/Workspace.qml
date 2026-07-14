pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

Item {
    id: root

    required property int index
    required property int activeWsId
    required property var occupied
    required property int groupOffset

    readonly property string barPosition: {
        const value = String(Config.bar.position || "left").toLowerCase();
        if (value === "right" || value === "top")
            return value;
        return "left";
    }
    readonly property bool isVertical: barPosition !== "top"

    readonly property bool isWorkspace: true // Flag for finding workspace children
    // Fixed cell along the bar thickness — never depends on laid-out size (avoids 0-size
    // collapse on Shell restart before content/Hypr data is ready).
    readonly property int cellSize: Tokens.sizes.bar.innerWidth - Tokens.padding.small
    // Extent along the bar axis for ActiveIndicator / OccupiedBg.
    readonly property int size: {
        const along = isVertical ? Math.max(cellSize, content.implicitHeight) : Math.max(cellSize, content.implicitWidth);
        return along + (hasWindows ? Tokens.padding.extraSmall : 0);
    }

    readonly property int ws: groupOffset + index + 1
    readonly property bool isOccupied: occupied[ws] ?? false
    readonly property bool hasWindows: isOccupied && Config.bar.workspaces.showWindows

    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
    Layout.preferredWidth: isVertical ? cellSize : size
    Layout.preferredHeight: isVertical ? size : cellSize
    Layout.minimumWidth: isVertical ? cellSize : cellSize
    Layout.minimumHeight: isVertical ? cellSize : cellSize
    implicitWidth: isVertical ? cellSize : Math.max(cellSize, content.implicitWidth)
    implicitHeight: isVertical ? Math.max(cellSize, content.implicitHeight) : cellSize

    GridLayout {
        id: content

        anchors.centerIn: parent
        columns: root.isVertical ? 1 : 100
        rows: root.isVertical ? 100 : 1
        flow: root.isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        columnSpacing: 0
        rowSpacing: 0

        StyledText {
            id: indicator

            Layout.alignment: root.isVertical ? (Qt.AlignHCenter | Qt.AlignTop) : (Qt.AlignVCenter | Qt.AlignLeft)
            Layout.preferredWidth: Tokens.sizes.bar.innerWidth - Tokens.padding.small
            Layout.preferredHeight: Tokens.sizes.bar.innerWidth - Tokens.padding.small

            animate: true
            text: {
                const ws = Hypr.workspaces.values.find(w => w.id === root.ws);
                const wsName = !ws || ws.name == root.ws ? root.ws : ws.name[0];
                let displayName = wsName.toString();
                if (Config.bar.workspaces.capitalisation.toLowerCase() === "upper") {
                    displayName = displayName.toUpperCase();
                } else if (Config.bar.workspaces.capitalisation.toLowerCase() === "lower") {
                    displayName = displayName.toLowerCase();
                }
                const label = Config.bar.workspaces.label || displayName;
                const occupiedLabel = Config.bar.workspaces.occupiedLabel || label;
                const activeLabel = Config.bar.workspaces.activeLabel || (root.isOccupied ? occupiedLabel : label);
                return root.activeWsId === root.ws ? activeLabel : root.isOccupied ? occupiedLabel : label;
            }
            color: Config.bar.workspaces.occupiedBg || root.isOccupied || root.activeWsId === root.ws ? Colours.palette.m3onSurface : Colours.layer(Colours.palette.m3outlineVariant, 2)
            verticalAlignment: Qt.AlignVCenter
            horizontalAlignment: Qt.AlignHCenter
            font.family: Tokens.font.workspaces
        }

        Loader {
            id: windows

            asynchronous: true

            Layout.alignment: root.isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
            Layout.fillWidth: !root.isVertical
            Layout.fillHeight: root.isVertical
            Layout.topMargin: root.isVertical ? -Tokens.sizes.bar.innerWidth / 10 : 0
            Layout.leftMargin: root.isVertical ? 0 : -Tokens.sizes.bar.innerWidth / 10

            visible: active
            active: root.hasWindows

            sourceComponent: Grid {
                spacing: 0
                columns: root.isVertical ? 1 : 100
                rows: root.isVertical ? 100 : 1
                flow: root.isVertical ? Grid.TopToBottom : Grid.LeftToRight

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
                    model: ScriptModel {
                        values: {
                            const ws = root.ws;
                            const windows = Hypr.toplevels.values.filter(c => c.workspace?.id === ws);
                            const maxIcons = root.Config.bar.workspaces.maxWindowIcons;
                            return maxIcons > 0 ? windows.slice(0, maxIcons) : windows;
                        }
                    }

                    // Monochrome Material glyphs only. ActiveIndicator Colouriser recolors
                    // this whole mask; full-color IconImages become solid black blocks.
                    MaterialIcon {
                        required property var modelData

                        grade: 0
                        text: Icons.getAppCategoryIcon(modelData.lastIpcObject.class, "terminal")
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }
        }
    }

    Behavior on Layout.preferredHeight {
        Anim {}
    }

    Behavior on Layout.preferredWidth {
        Anim {}
    }
}
