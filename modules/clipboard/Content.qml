pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    required property DrawerVisibilities visibilities

    readonly property int panelW: Tokens.sizes.clipboard.width
    readonly property int maxH: Tokens.sizes.clipboard.maxHeight

    implicitWidth: panelW
    implicitHeight: Math.min(maxH, header.implicitHeight + searchBox.implicitHeight + listHost.implicitHeight + Tokens.padding.large * 2 + Tokens.spacing.medium * 2)

    function activate(entryId: string): void {
        Clipboard.copyEntry(entryId);
        root.visibilities.clipboard = false;
    }

    ColumnLayout {
        id: col

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        RowLayout {
            id: header

            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            MaterialIcon {
                text: "content_paste"
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.large
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: qsTr("剪切板")
                    font: Tokens.font.title.medium
                }

                StyledText {
                    text: Clipboard.statusText.length ? Clipboard.statusText : qsTr("%1 条记录").arg(Clipboard.filteredEntries.length)
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }
            }

            IconButton {
                icon: "delete_sweep"
                type: IconButton.Text
                onClicked: Clipboard.wipe()
            }

            IconButton {
                icon: "close"
                type: IconButton.Text
                onClicked: root.visibilities.clipboard = false
            }
        }

        StyledRect {
            id: searchBox

            Layout.fillWidth: true
            implicitHeight: searchRow.implicitHeight
            radius: Tokens.rounding.full
            color: Colours.layer(Colours.palette.m3surfaceContainer, 2)

            RowLayout {
                id: searchRow

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.medium
                anchors.rightMargin: Tokens.padding.small
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: "search"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }

                StyledTextField {
                    id: searchField

                    Layout.fillWidth: true
                    placeholderText: qsTr("搜索剪切板…")
                    text: Clipboard.filter
                    onTextChanged: Clipboard.filter = text
                    topPadding: Tokens.padding.small
                    bottomPadding: Tokens.padding.small

                    Keys.onEscapePressed: root.visibilities.clipboard = false
                    Keys.onDownPressed: list.incrementCurrentIndex()
                    Keys.onUpPressed: list.decrementCurrentIndex()
                    Keys.onReturnPressed: {
                        const item = list.currentItem;
                        if (item?.entryId)
                            root.activate(item.entryId);
                    }

                    Component.onCompleted: forceActiveFocus()
                }

                IconButton {
                    visible: searchField.text.length > 0
                    icon: "close"
                    type: IconButton.Text
                    onClicked: {
                        searchField.text = "";
                        Clipboard.clearFilter();
                    }
                }
            }
        }

        Item {
            id: listHost

            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitHeight: Math.min((Tokens.sizes.clipboard.maxHeight) - 140, Math.max(list.contentHeight, 80))

            ListView {
                id: list

                anchors.fill: parent
                clip: true
                spacing: Tokens.spacing.small
                model: Clipboard.filteredEntries
                currentIndex: count > 0 ? 0 : -1
                keyNavigationWraps: true
                boundsBehavior: Flickable.StopAtBounds

                delegate: StyledRect {
                    id: del

                    required property var modelData
                    required property int index
                    readonly property string entryId: modelData.id
                    readonly property bool isCurrent: ListView.isCurrentItem

                    width: list.width
                    implicitHeight: Tokens.sizes.clipboard.itemHeight
                    radius: Tokens.rounding.large
                    color: isCurrent ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainerHigh

                    StateLayer {
                        radius: parent.radius
                        onClicked: root.activate(del.entryId)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Tokens.padding.medium
                        spacing: Tokens.spacing.medium

                        MaterialIcon {
                            text: modelData.isImage ? "image" : "notes"
                            color: isCurrent ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.medium
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.preview || qsTr("（空）")
                            font: Tokens.font.body.medium
                            color: isCurrent ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            maximumLineCount: 2
                        }

                        IconButton {
                            icon: "delete"
                            type: IconButton.Text
                            label.color: Colours.palette.m3error
                            stateLayer.color: Colours.palette.m3error
                            onClicked: Clipboard.deleteEntry(del.entryId)
                        }
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: list.count === 0 && !Clipboard.loading
                    text: Clipboard.filter.length ? qsTr("无匹配项") : qsTr("暂无历史\n复制内容后会显示在这里")
                    horizontalAlignment: Text.AlignHCenter
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.medium
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: Clipboard.loading && list.count === 0
                    text: qsTr("加载中…")
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }
    }

    Keys.onEscapePressed: root.visibilities.clipboard = false
}
