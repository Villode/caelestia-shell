pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

StyledRect {
    id: root

    required property var state

    readonly property int sidebarWidth: 230

    function focusGlobalSearch(): void {
        if (typeof globalSearchBox !== "undefined" && globalSearchBox)
            globalSearchBox.focusGlobal();
    }
    implicitWidth: sidebarWidth
    color: Colours.tPalette.m3surfaceContainer

    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list", "text/plain"]
        onEntered: drag => {
            dropHint.visible = true;
            drag.accepted = true;
        }
        onExited: dropHint.visible = false
        onDropped: drop => {
            dropHint.visible = false;
            let path = "";
            if (drop.hasUrls && drop.urls.length) {
                const u = drop.urls[0].toString();
                path = u.startsWith("file://") ? decodeURIComponent(u.slice(7)) : u;
            } else if (drop.hasText) {
                path = drop.text.trim().split("\n")[0];
                if (path.startsWith("file://"))
                    path = decodeURIComponent(path.slice(7));
            }
            if (!path)
                return;
            while (path.length > 1 && path.endsWith("/"))
                path = path.slice(0, -1);
            const name = path.split("/").pop() || path;
            root.state.pinPath(path, name);
            drop.acceptProposedAction();
        }
    }

    StyledRect {
        id: dropHint
        anchors.fill: parent
        anchors.margins: 6
        radius: Tokens.rounding.large
        visible: false
        z: 20
        color: Qt.alpha(Colours.palette.m3primary, 0.12)
        border.width: 2
        border.color: Colours.palette.m3primary

        StyledText {
            anchors.centerIn: parent
            text: qsTr("拖放到此以固定快捷")
            color: Colours.palette.m3primary
            font: Tokens.font.body.builders.small.weight(Font.Bold).build()
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: col.implicitHeight + Tokens.padding.medium * 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            width: flick.width
            anchors.top: parent.top
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.extraSmall

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Tokens.padding.extraSmall / 2
                Layout.bottomMargin: Tokens.spacing.small
                text: qsTr("文件")
                color: Colours.palette.m3onSurface
                font: Tokens.font.body.builders.large.weight(Font.Bold).build()
            }

            // Global search — always visible on every page
            StyledRect {
                id: globalSearchBox
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.padding.small
                Layout.rightMargin: Tokens.padding.small
                Layout.bottomMargin: Tokens.spacing.medium
                implicitHeight: globalField.implicitHeight + Tokens.padding.small
                radius: Tokens.rounding.full
                color: root.state.searchScope === "global"
                    ? Qt.alpha(Colours.palette.m3primaryContainer, 0.85)
                    : Colours.tPalette.m3surfaceContainerHigh
                border.width: root.state.searchScope === "global" ? 1 : 0
                border.color: Colours.palette.m3primary

                function focusGlobal(): void {
                    if (root.state.searchScope !== "global")
                        root.state.setSearchScope("global");
                    Qt.callLater(() => {
                        globalField.forceActiveFocus();
                        globalField.selectAll();
                    });
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.medium
                    anchors.rightMargin: Tokens.padding.extraSmall
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        text: "travel_explore"
                        color: root.state.searchScope === "global"
                            ? Colours.palette.m3onPrimaryContainer
                            : Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small
                    }

                    StyledTextField {
                        id: globalField
                        Layout.fillWidth: true
                        placeholderText: qsTr("全局搜索…")
                        color: root.state.searchScope === "global"
                            ? Colours.palette.m3onPrimaryContainer
                            : Colours.palette.m3onSurface
                        Component.onCompleted: {
                            if (root.state.searchScope === "global")
                                text = root.state.nameFilter;
                        }
                        onActiveFocusChanged: {
                            if (activeFocus) {
                                if (root.state.searchScope !== "global")
                                    root.state.setSearchScope("global");
                                if (text !== root.state.nameFilter)
                                    text = root.state.nameFilter;
                            }
                        }
                        onTextChanged: {
                            if (root.state.searchScope !== "global")
                                return;
                            if (root.state.nameFilter !== text)
                                root.state.setNameFilter(text);
                        }
                        Keys.onEscapePressed: {
                            text = "";
                            root.state.clearNameFilter();
                            root.state.setSearchScope("local");
                            event.accepted = true;
                        }
                        Keys.onReturnPressed: event.accepted = true
                        Keys.onEnterPressed: event.accepted = true
                    }

                    Item {
                        implicitWidth: 26
                        implicitHeight: 26
                        visible: root.state.searchScope === "global" || globalField.text.length > 0

                        StateLayer {
                            radius: Tokens.rounding.full
                            onClicked: {
                                globalField.text = "";
                                root.state.clearNameFilter();
                                root.state.setSearchScope("local");
                            }
                        }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "close"
                            color: Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.small
                        }
                    }
                }

                Connections {
                    target: root.state
                    function onNameFilterChanged(): void {
                        if (root.state.searchScope !== "global")
                            return;
                        if (globalField.text !== root.state.nameFilter)
                            globalField.text = root.state.nameFilter;
                    }
                    function onSearchScopeChanged(): void {
                        if (root.state.searchScope !== "global") {
                            if (!globalField.activeFocus)
                                globalField.text = "";
                        } else if (globalField.text !== root.state.nameFilter) {
                            globalField.text = root.state.nameFilter;
                        }
                    }
                }
            }

            // Windows-style entry point
            PlaceRow {
                placeId: "ThisPC"
                label: qsTr("此电脑")
                iconName: "computer"
                selected: root.state.placeSelected("ThisPC")
                onActivated: root.state.navigateToThisPC()
            }

            PlaceRow {
                placeId: "Home"
                label: qsTr("主目录")
                iconName: "home"
                selected: root.state.placeSelected("Home")
                onActivated: root.state.navigateToPlace("Home")
            }

            PlaceRow {
                placeId: "Trash"
                label: qsTr("回收站")
                iconName: "delete"
                selected: root.state.placeSelected("Trash")
                onActivated: root.state.navigateToTrash()
            }

            Divider {}
            SectionTitle { text: qsTr("常用") }

            Repeater {
                model: ["Downloads", "Desktop", "Documents", "Music", "Pictures", "Videos"]

                PlaceRow {
                    required property string modelData
                    placeId: modelData
                    label: root.state.labelForSegment(modelData)
                    selected: root.state.placeSelected(modelData)
                    iconName: {
                        const p = modelData;
                        if (p === "Downloads") return "file_download";
                        if (p === "Desktop") return "desktop_windows";
                        if (p === "Documents") return "description";
                        if (p === "Music") return "music_note";
                        if (p === "Pictures") return "image";
                        if (p === "Videos") return "video_library";
                        return "folder";
                    }
                    onActivated: root.state.navigateToPlace(placeId)
                }
            }

            Divider {}
            SectionTitle { text: qsTr("快捷访问") }

            StyledText {
                visible: !root.state.favorites || root.state.favorites.length === 0
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.padding.large
                Layout.rightMargin: Tokens.padding.large
                text: qsTr("拖入文件夹，或右键「固定到侧栏」")
                color: Colours.palette.m3outline
                font: Tokens.font.body.builders.small.scale(0.9).build()
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: root.state.favorites

                PlaceRow {
                    required property var modelData
                    placeId: ""
                    label: modelData.name || modelData.path
                    selected: root.state.cwdPath() === modelData.path
                    iconName: "folder_special"
                    onActivated: root.state.openAbsolutePath(modelData.path)
                    onRemove: root.state.unpinPath(modelData.path)
                    removable: true
                }
            }

            Item {
                Layout.preferredHeight: 12
            }
        }
    }

    component SectionTitle: StyledText {
        Layout.leftMargin: Tokens.padding.large
        Layout.topMargin: Tokens.spacing.small
        Layout.bottomMargin: Tokens.spacing.extraSmall
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.builders.small.weight(Font.Bold).build()
    }

    component Divider: Item {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.small
        implicitHeight: 1
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 1
            color: Colours.palette.m3outlineVariant
        }
    }

    component PlaceRow: StyledRect {
        id: place

        property string placeId
        property string label
        property string sublabel: ""
        property string iconName: "folder"
        property bool selected: false
        property bool removable: false
        property bool dimmed: false
        signal activated
        signal remove

        Layout.fillWidth: true
        implicitHeight: placeInner.implicitHeight + Tokens.padding.medium * 2
        radius: Tokens.rounding.full
        color: Qt.alpha(Colours.palette.m3secondaryContainer, selected ? 1 : 0)
        opacity: dimmed ? 0.75 : 1

        StateLayer {
            color: place.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton && place.removable) {
                    place.remove();
                    return;
                }
                place.activated();
            }
        }

        RowLayout {
            id: placeInner
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            anchors.leftMargin: Tokens.padding.large
            anchors.rightMargin: Tokens.padding.large
            spacing: Tokens.spacing.medium

            MaterialIcon {
                text: place.iconName
                color: place.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                fontStyle: Tokens.font.icon.medium
                fill: place.selected ? 1 : 0
                Behavior on fill {
                    Anim { type: Anim.DefaultEffects }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: place.label
                    color: place.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }
                StyledText {
                    visible: place.sublabel.length > 0
                    Layout.fillWidth: true
                    text: place.sublabel
                    color: place.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3outline
                    font: Tokens.font.body.builders.small.scale(0.85).build()
                    elide: Text.ElideMiddle
                }
            }

            MaterialIcon {
                visible: place.removable
                text: "close"
                color: place.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3outline
                fontStyle: Tokens.font.icon.builders.small.build()
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    onClicked: place.remove()
                }
            }
        }
    }
}
