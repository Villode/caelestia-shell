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

    function focusSearch(): void {
        searchField.forceActiveFocus();
        searchField.selectAll();
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

        // Current-folder name filter
        StyledRect {
            Layout.preferredWidth: 220
            Layout.maximumWidth: 320
            Layout.fillWidth: true
            Layout.minimumWidth: 120
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
                    placeholderText: qsTr("筛选当前文件夹…")
                    text: root.state.nameFilter
                    selectByMouse: true
                    onTextChanged: {
                        if (root.state.nameFilter !== text)
                            root.state.setNameFilter(text);
                    }
                    Keys.onEscapePressed: {
                        if (text.length) {
                            text = "";
                            root.state.clearNameFilter();
                            event.accepted = true;
                        }
                    }
                }

                Item {
                    visible: searchField.text.length > 0
                    implicitWidth: 28
                    implicitHeight: 28

                    StateLayer {
                        radius: Tokens.rounding.full
                        onClicked: {
                            searchField.text = "";
                            root.state.clearNameFilter();
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

        StyledText {
            visible: !root.state.isTrash()
            text: root.state.viewMode === "list" ? qsTr("列表") : qsTr("图标")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.builders.small.build()
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
