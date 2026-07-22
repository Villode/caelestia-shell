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

    readonly property real nonAnimHeight: header.implicitHeight + searchBox.implicitHeight + listHost.implicitHeight + layout.spacing * 2

    implicitHeight: layout.implicitHeight

    function activate(entryId: string): void {
        Clipboard.copyEntry(entryId);
        root.visibilities.clipboard = false;
    }

    ColumnLayout {
        id: layout

        anchors.fill: parent
        spacing: Tokens.spacing.medium

        // Main card
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: cardCol.implicitHeight + Tokens.padding.large * 2
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer

            ColumnLayout {
                id: cardCol

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                RowLayout {
                    id: header

                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        implicitWidth: implicitHeight
                        implicitHeight: pasteIcon.implicitHeight + Tokens.padding.large
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3tertiaryContainer

                        MaterialIcon {
                            id: pasteIcon

                            anchors.centerIn: parent
                            text: "content_paste"
                            color: Colours.palette.m3onTertiaryContainer
                            fontStyle: Tokens.font.icon.large
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: qsTr("剪切板")
                            font: Tokens.font.body.medium
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                if (Clipboard.statusText.length)
                                    return Clipboard.statusText;
                                const n = Clipboard.filteredEntries.length;
                                const pins = Clipboard.pinnedIds.length;
                                if (pins > 0)
                                    return qsTr("%1 条 · %2 置顶").arg(n).arg(pins);
                                return qsTr("%1 条记录").arg(n);
                            }
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
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
                            placeholderText: qsTr("搜索…")
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

                            Component.onCompleted: {
                                if (root.visibilities.clipboard)
                                    forceActiveFocus();
                            }
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
                    // Compact list height — bottom chrome, not a tall modal.
                    implicitHeight: Math.min(Tokens.sizes.clipboard.maxHeight, Math.max(list.contentHeight, emptyHint.implicitHeight + Tokens.padding.large * 2))

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
                            color: isCurrent ? Colours.palette.m3secondaryContainer : Colours.layer(Colours.palette.m3surfaceContainer, 1)

                            StateLayer {
                                radius: parent.radius
                                onClicked: root.activate(del.entryId)
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Tokens.padding.medium
                                spacing: Tokens.spacing.medium

                                MaterialIcon {
                                    text: modelData.pinned ? "push_pin" : (modelData.isImage ? "image" : "notes")
                                    color: modelData.pinned
                                        ? Colours.palette.m3primary
                                        : (isCurrent ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant)
                                    fontStyle: Tokens.font.icon.medium
                                    fill: modelData.pinned ? 1 : 0
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
                                    icon: modelData.pinned ? "keep" : "keep_outline"
                                    type: IconButton.Text
                                    // Pin / unpin — stays at top of history
                                    checked: !!modelData.pinned
                                    onClicked: Clipboard.togglePin(del.entryId)
                                }

                                IconButton {
                                    icon: "delete"
                                    type: IconButton.Text
                                    onClicked: Clipboard.deleteEntry(del.entryId)
                                }
                            }
                        }

                        StyledText {
                            id: emptyHint

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
        }
    }

    Keys.onEscapePressed: root.visibilities.clipboard = false
}
