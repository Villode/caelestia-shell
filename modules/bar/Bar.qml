pragma ComponentBehavior: Bound

import "popouts" as BarPopouts
import "components"
import "components/workspaces"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

GridLayout {
    id: root

    required property ShellScreen screen
    required property DrawerVisibilities visibilities
    required property BarPopouts.Wrapper popouts
    required property bool fullscreen
    property string position: "left"
    property bool isVertical: true
    readonly property int vPadding: Tokens.padding.large

    columns: isVertical ? 1 : 100
    rows: isVertical ? 100 : 1
    flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
    columnSpacing: Tokens.spacing.medium
    rowSpacing: Tokens.spacing.medium

    // Keep a single spacing property for ActiveWindow calculations.
    readonly property real spacing: isVertical ? rowSpacing : columnSpacing

    function closeTray(): void {
        if (!Config.bar.tray.compact)
            return;

        for (let i = 0; i < repeater.count; i++) {
            const loader = repeater.itemAt(i) as WrappedLoader;
            if (loader?.enabled && loader.entryId === "tray") {
                (loader.item as Tray).expanded = false;
            }
        }
    }

    function checkPopout(pos: real): void {
        const ch = isVertical ? childAt(width / 2, pos) as WrappedLoader : childAt(pos, height / 2) as WrappedLoader;

        if (ch?.entryId !== "tray")
            closeTray();

        if (!ch) {
            popouts.hasCurrent = false;
            return;
        }

        const id = ch.entryId;
        const top = isVertical ? ch.y : ch.x;

        if (id === "statusIcons" && Config.bar.popouts.statusIcons) {
            const items = (ch.item as StatusIcons).items;
            const mapped = mapToItem(items, isVertical ? 0 : pos, isVertical ? pos : 0);
            const icon = items.childAt(isVertical ? items.width / 2 : mapped.x, isVertical ? mapped.y : items.height / 2);
            if (icon) {
                popouts.currentName = icon.name;
                popouts.currentCenter = Qt.binding(() => {
                    const p = icon.mapToItem(root, icon.implicitWidth / 2, icon.implicitHeight / 2);
                    return root.isVertical ? p.y : p.x;
                });
                popouts.hasCurrent = true;
            }
        } else if (id === "tray" && Config.bar.popouts.tray) {
            const tray = ch.item as Tray;
            if (!Config.bar.tray.compact || (tray.expanded && !tray.expandIcon.contains(mapToItem(tray.expandIcon, isVertical ? tray.implicitWidth / 2 : pos - top, isVertical ? pos - top : tray.implicitHeight / 2)))) {
                const layoutSize = isVertical ? tray.layout.implicitHeight : tray.layout.implicitWidth;
                const index = Math.floor(((pos - top - tray.padding * 2 + tray.spacing) / Math.max(1, layoutSize)) * tray.items.count);
                const trayItem = tray.items.itemAt(index);
                if (trayItem) {
                    popouts.currentName = `traymenu${index}`;
                    popouts.currentCenter = Qt.binding(() => {
                        const p = trayItem.mapToItem(root, trayItem.implicitWidth / 2, trayItem.implicitHeight / 2);
                        return root.isVertical ? p.y : p.x;
                    });
                    popouts.hasCurrent = true;
                } else {
                    popouts.hasCurrent = false;
                }
            } else {
                popouts.hasCurrent = false;
                tray.expanded = true;
            }
        } else if (id === "clock") {
            popouts.currentName = "calendar";
            popouts.currentCenter = Qt.binding(() => {
                const p = ch.mapToItem(root, ch.implicitWidth / 2, ch.implicitHeight / 2);
                return root.isVertical ? p.y : p.x;
            });
            popouts.hasCurrent = true;
        } else if (id === "activeWindow" && Config.bar.popouts.activeWindow && Config.bar.activeWindow.showOnHover && root.isVertical) {
            // Horizontal (top) bar: active-window fills the center and collides with the
            // dashboard hover zone — only open this popout via click there.
            popouts.currentName = id.toLowerCase();
            const item = ch.item as Item;
            const p = item.mapToItem(root, item.implicitWidth / 2, item.implicitHeight / 2);
            popouts.currentCenter = root.isVertical ? p.y : p.x;
            popouts.hasCurrent = true;
        } else if (id === "activeWindow" && !root.isVertical) {
            popouts.hasCurrent = false;
        }
    }

    function handleWheel(pos: real, angleDelta: point): void {
        const ch = isVertical ? childAt(width / 2, pos) as WrappedLoader : childAt(pos, height / 2) as WrappedLoader;
        if (ch?.entryId === "workspaces" && Config.bar.scrollActions.workspaces) {
            // Workspace scroll
            const mon = (GlobalConfig.bar.workspaces.perMonitorWorkspaces ? Hypr.monitorFor(screen) : Hypr.focusedMonitor);
            const specialWs = mon?.lastIpcObject.specialWorkspace.name;
            const delta = root.isVertical ? angleDelta.y : (angleDelta.y || angleDelta.x);
            if (specialWs?.length > 0)
                Hypr.dispatch(Hypr.usingLua ? `hl.dsp.workspace.toggle_special("${specialWs.slice(8)}")` : `togglespecialworkspace ${specialWs.slice(8)}`);
            else if (delta < 0 || (GlobalConfig.bar.workspaces.perMonitorWorkspaces ? mon.activeWorkspace?.id : Hypr.activeWsId) > 1)
                Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ workspace = "r${delta > 0 ? "-" : "+"}1" })` : `workspace r${delta > 0 ? "-" : "+"}1`);
        }
    }

    Repeater {
        id: repeater

        model: Config.bar.entries

        DelegateChooser {
            role: "id"

            DelegateChoice {
                roleValue: "spacer"
                delegate: WrappedLoader {
                    Layout.fillWidth: !root.isVertical && enabled
                    Layout.fillHeight: root.isVertical && enabled
                }
            }
            DelegateChoice {
                roleValue: "logo"
                delegate: WrappedLoader {
                    sourceComponent: OsIcon {}
                }
            }
            DelegateChoice {
                roleValue: "workspaces"
                delegate: WrappedLoader {
                    sourceComponent: Workspaces {
                        screen: root.screen
                        fullscreen: root.fullscreen
                    }
                }
            }
            DelegateChoice {
                roleValue: "activeWindow"
                delegate: WrappedLoader {
                    Layout.fillWidth: !root.isVertical
                    Layout.fillHeight: root.isVertical
                    visible: !root.fullscreen
                    sourceComponent: ActiveWindow {
                        bar: root
                        monitor: Brightness.getMonitorForScreen(root.screen)
                    }
                }
            }
            DelegateChoice {
                roleValue: "tray"
                delegate: WrappedLoader {
                    visible: !root.fullscreen
                    sourceComponent: Tray {}
                }
            }
            DelegateChoice {
                roleValue: "clock"
                delegate: WrappedLoader {
                    visible: !root.fullscreen
                    sourceComponent: Clock {}
                }
            }
            DelegateChoice {
                roleValue: "statusIcons"
                delegate: WrappedLoader {
                    visible: !root.fullscreen
                    sourceComponent: StatusIcons {}
                }
            }
            DelegateChoice {
                roleValue: "power"
                delegate: WrappedLoader {
                    sourceComponent: Power {
                        visibilities: root.visibilities
                    }
                }
            }
        }
    }

    component WrappedLoader: Loader {
        required enabled
        required property var modelData
        readonly property string entryId: modelData.id
        required property int index

        function findFirstEnabled(): Item {
            const count = repeater.count;
            for (let i = 0; i < count; i++) {
                const item = repeater.itemAt(i);
                if (item?.enabled)
                    return item;
            }
            return null;
        }

        function findLastEnabled(): Item {
            for (let i = repeater.count - 1; i >= 0; i--) {
                const item = repeater.itemAt(i);
                if (item?.enabled)
                    return item;
            }
            return null;
        }

        // Logo + workspaces must paint on the first frame after Shell restart;
        // async load can leave an empty gap next to the logo until a later layout pass.
        asynchronous: entryId !== "logo" && entryId !== "workspaces"
        Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
        Layout.minimumWidth: entryId === "workspaces" ? Tokens.sizes.bar.innerWidth : 0
        Layout.minimumHeight: entryId === "workspaces" ? Tokens.sizes.bar.innerWidth : 0

        // Cursed ahh thing to add padding to first and last enabled components
        Layout.topMargin: root.isVertical && findFirstEnabled() === this ? root.vPadding : 0
        Layout.bottomMargin: root.isVertical && findLastEnabled() === this ? root.vPadding : 0
        Layout.leftMargin: !root.isVertical && findFirstEnabled() === this ? root.vPadding : 0
        Layout.rightMargin: !root.isVertical && findLastEnabled() === this ? root.vPadding : 0

        visible: enabled
        active: enabled
    }
}
