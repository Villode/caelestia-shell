pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

StyledRect {
    id: root

    required property var state
    property var actions: null
    property bool searchExpanded: false
    property bool sortMenuOpen: false

    // Request host (ManagerWindow) to show sort menu above folder view
    signal sortMenuOpenRequested(real x, real y)
    signal sortMenuCloseRequested()

    function closeSortMenu(): void {
        sortMenuCloseRequested();
    }

    function focusSearch(): void {
        if (root.state.searchScope === "global")
            root.state.setSearchScope("local");
        searchExpanded = true;
        Qt.callLater(() => {
            searchField.forceActiveFocus();
            searchField.selectAll();
        });
    }

    function collapseSearch(clear: bool): void {
        searchExpanded = false;
        searchField.focus = false;
        if (clear) {
            searchField.text = "";
            root.state.clearNameFilter();
        }
    }

    implicitHeight: row.implicitHeight + Tokens.padding.small * 2
    color: Colours.tPalette.m3surfaceContainer

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        anchors.topMargin: Tokens.padding.small
        anchors.bottomMargin: Tokens.padding.small
        spacing: Tokens.spacing.small

        ToolBtn {
            icon: "grid_view"
            tip: qsTr("图标视图")
            active: root.state.viewMode === "grid"
            onTriggered: root.state.setViewMode("grid")
        }
        ToolBtn {
            icon: "view_list"
            tip: qsTr("列表视图")
            active: root.state.viewMode === "list"
            onTriggered: root.state.setViewMode("list")
        }

        StyledRect {
            Layout.preferredWidth: 1
            Layout.preferredHeight: 20
            color: Colours.palette.m3outlineVariant
        }

        ToolBtn {
            icon: root.state.showExtensions ? "title" : "format_clear"
            tip: root.state.showExtensions ? qsTr("隐藏扩展名") : qsTr("显示扩展名")
            active: root.state.showExtensions
            onTriggered: root.state.toggleShowExtensions()
        }
        ToolBtn {
            icon: root.state.showHidden ? "visibility" : "visibility_off"
            tip: root.state.showHidden ? qsTr("不显示隐藏文件") : qsTr("显示隐藏文件")
            active: root.state.showHidden
            onTriggered: root.state.toggleShowHidden()
        }

        ToolBtn {
            icon: "refresh"
            tip: qsTr("刷新")
            active: false
            onTriggered: {
                root.state.bumpRefresh();
                root.state.statusText = qsTr("已刷新");
            }
        }

        Item {
            id: sortBtnWrap
            implicitWidth: 34
            implicitHeight: 34

            StyledRect {
                anchors.fill: parent
                radius: Tokens.rounding.medium
                color: root.sortMenuOpen ? Colours.palette.m3secondaryContainer : "transparent"

                StateLayer {
                    color: root.sortMenuOpen ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                    onClicked: {
                        if (root.sortMenuOpen) {
                            root.sortMenuCloseRequested();
                            return;
                        }
                        // Bottom-right of sort button in toolbar coords
                        const p = sortBtnWrap.mapToItem(root, 0, sortBtnWrap.height);
                        root.sortMenuOpenRequested(p.x + sortBtnWrap.width, p.y + 4);
                    }
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "sort"
                    color: root.sortMenuOpen ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                    fontStyle: Tokens.font.icon.medium
                    fill: root.sortMenuOpen ? 1 : 0
                }
            }

        }

        StyledRect {
            Layout.preferredWidth: 1
            Layout.preferredHeight: 20
            color: Colours.palette.m3outlineVariant
        }

        ToolBtn {
            icon: "push_pin"
            tip: qsTr("固定当前文件夹到侧栏")
            active: false
            onTriggered: {
                const p = root.state.cwdPath();
                const parts = p.split("/");
                const n = parts[parts.length - 1] || p;
                root.state.pinPath(p, n);
            }
        }

        ToolBtn {
            visible: root.state.isTrash()
            icon: "delete_sweep"
            tip: qsTr("清空回收站")
            active: false
            onTriggered: {
                if (root.actions && typeof root.actions.requestEmptyTrash === "function")
                    root.actions.requestEmptyTrash();
            }
        }

        Item { Layout.fillWidth: true }

        // Search current folder only (global search lives in sidebar)
        ToolBtn {
            visible: !root.searchExpanded
            icon: "search"
            tip: qsTr("搜索当前文件夹 (Ctrl+F)")
            active: root.state.nameFilter.length > 0 && root.state.searchScope !== "global"
            onTriggered: root.focusSearch()
        }

        StyledRect {
            visible: root.searchExpanded
            Layout.preferredWidth: 240
            Layout.maximumWidth: 360
            Layout.minimumWidth: 160
            implicitHeight: searchField.implicitHeight + Tokens.padding.extraSmall
            radius: Tokens.rounding.medium
            color: Colours.tPalette.m3surfaceContainerHigh

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.small
                anchors.rightMargin: Tokens.padding.extraSmall
                spacing: Tokens.spacing.extraSmall

                MaterialIcon {
                    text: "search"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }

                StyledTextField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: qsTr("搜索当前文件夹…")
                    // One-way sync from state when empty/nav; user edits drive state
                    Component.onCompleted: text = root.state.nameFilter
                    onActiveFocusChanged: {
                        if (activeFocus && text !== root.state.nameFilter)
                            text = root.state.nameFilter;
                    }
                    onTextChanged: {
                        // Avoid re-entrancy; always push to state
                        if (root.state.nameFilter !== text)
                            root.state.setNameFilter(text);
                        // Empty field = show all (even if state already empty, force refresh)
                        if (!text.length && root.state.nameFilter.length)
                            root.state.clearNameFilter();
                    }
                    Keys.onEscapePressed: {
                        root.collapseSearch(true);
                        event.accepted = true;
                    }
                    Keys.onReturnPressed: event.accepted = true
                    Keys.onEnterPressed: event.accepted = true
                }

                Item {
                    implicitWidth: 28
                    implicitHeight: 28

                    StateLayer {
                        radius: Tokens.rounding.full
                        onClicked: root.collapseSearch(true)
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "close"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small
                    }
                }
            }
        }

        // Badge when collapsed but filter still active (should be rare if collapse clears)
        Rectangle {
            visible: !root.searchExpanded && root.state.nameFilter.length > 0
            implicitWidth: Math.max(18, filterBadge.implicitWidth + 8)
            implicitHeight: 18
            radius: height / 2
            color: Colours.palette.m3primary
            Layout.alignment: Qt.AlignVCenter

            StyledText {
                id: filterBadge
                anchors.centerIn: parent
                text: "•"
                color: Colours.palette.m3onPrimary
                font: Tokens.font.body.builders.small.scale(0.8).weight(Font.Bold).build()
            }

            StateLayer {
                radius: parent.radius
                onClicked: root.focusSearch()
            }
        }

        StyledRect {
            visible: root.state.isTrash()
            implicitWidth: emptyLbl.implicitWidth + Tokens.padding.medium * 2
            implicitHeight: emptyLbl.implicitHeight + Tokens.padding.small
            radius: Tokens.rounding.full
            color: Colours.palette.m3errorContainer

            StateLayer {
                radius: parent.radius
                color: Colours.palette.m3onErrorContainer
                onClicked: {
                    if (root.actions && typeof root.actions.requestEmptyTrash === "function")
                        root.actions.requestEmptyTrash();
                }
            }
            StyledText {
                id: emptyLbl
                anchors.centerIn: parent
                text: qsTr("清空回收站")
                color: Colours.palette.m3onErrorContainer
                font: Tokens.font.body.builders.small.weight(Font.Bold).build()
            }
        }
    }

    // When cwd changes / filter cleared externally, collapse search UI if empty
    Connections {
        target: root.state
        function onNameFilterChanged(): void {
            if (searchField.text !== root.state.nameFilter)
                searchField.text = root.state.nameFilter;
            if (!root.state.nameFilter.length && !searchField.activeFocus)
                root.searchExpanded = false;
        }
    }

    component SortRow: Item {
        id: srow
        property string label
        property string sortKey
        property string iconName: ""
        property bool checkable: false
        property bool checked: false

        Layout.fillWidth: true
        implicitHeight: 34
        implicitWidth: Math.max(180, rowInner.implicitWidth + Tokens.padding.medium * 2)

        readonly property bool activeKey: !checkable && sortKey !== "__dir__" && root.state.sortBy === sortKey

        StyledRect {
            anchors.fill: parent
            radius: Tokens.rounding.medium
            color: srow.activeKey ? Colours.palette.m3secondaryContainer : "transparent"

            StateLayer {
                color: srow.activeKey ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                onClicked: {
                    if (srow.sortKey === "__dir__") {
                        root.state.toggleSortReverse();
                    } else if (srow.sortKey === "__folders__") {
                        root.state.toggleFoldersFirst();
                    } else {
                        root.state.setSortBy(srow.sortKey);
                    }
                    // keep menu open for multi-tweak; close on outside later
                }
            }

            RowLayout {
                id: rowInner
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.medium
                anchors.rightMargin: Tokens.padding.small
                spacing: Tokens.spacing.small

                MaterialIcon {
                    visible: srow.iconName.length > 0
                    text: srow.iconName
                    color: srow.activeKey ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                    fontStyle: Tokens.font.icon.small
                }

                StyledText {
                    Layout.fillWidth: true
                    text: srow.label
                    color: srow.activeKey ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                    font: Tokens.font.body.builders.small.weight(srow.activeKey ? Font.Bold : Font.Normal).build()
                }

                MaterialIcon {
                    visible: srow.activeKey || (srow.checkable && srow.checked)
                    text: srow.checkable ? "check" : (root.state.sortReverse ? "arrow_downward" : "arrow_upward")
                    color: srow.activeKey ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.small
                }
            }
        }
    }

    component ToolBtn: Item {
        id: btn
        property string icon
        property string tip
        property bool active: false
        signal triggered

        implicitWidth: 34
        implicitHeight: 34

        StyledRect {
            anchors.fill: parent
            radius: Tokens.rounding.medium
            color: btn.active ? Colours.palette.m3secondaryContainer : "transparent"

            StateLayer {
                color: btn.active ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                onClicked: btn.triggered()
            }

            MaterialIcon {
                anchors.centerIn: parent
                text: btn.icon
                color: btn.active ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                fontStyle: Tokens.font.icon.medium
                fill: btn.active ? 1 : 0
            }
        }
    }
}
