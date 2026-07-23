pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

StyledRect {
    id: root

    required property var state

    property bool editingPath: false
    // Depend on archiveNonce/cwd so breadcrumbs re-evaluate when browsing inside zip
    readonly property var breadcrumbModel: {
        const _n = root.state.archiveNonce;
        const _c = root.state.cwd;
        const _i = root.state.archiveInner;
        const _r = root.state.archiveRoot;
        if (root.state.pathSegments)
            return root.state.pathSegments();
        return root.state.cwd;
    }

    implicitHeight: inner.implicitHeight + Tokens.padding.medium * 2
    color: Colours.tPalette.m3surfaceContainer
    clip: true

    function beginEdit(): void {
        if (root.state.isThisPC)
            pathField.text = "";
        else if (root.state.isArchiveBrowse)
            pathField.text = root.state.displayPath() || "";
        else
            pathField.text = root.state.cwdPath() || "";
        editingPath = true;
        Qt.callLater(() => {
            pathField.forceActiveFocus();
            pathField.selectAll();
        });
    }

    function commitEdit(): void {
        const t = (pathField.text || "").trim();
        editingPath = false;
        if (!t.length) {
            root.state.navigateToThisPC();
            return;
        }
        root.state.openAbsolutePath(t);
    }

    function cancelEdit(): void {
        editingPath = false;
    }

    RowLayout {
        id: inner

        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        spacing: Tokens.spacing.small

        Item {
            implicitWidth: implicitHeight
            implicitHeight: upIcon.implicitHeight + Tokens.padding.small
            Layout.minimumWidth: implicitWidth

            StateLayer {
                radius: Tokens.rounding.medium
                disabled: !root.state.canNavigateUp
                onClicked: root.state.popDir()
            }

            MaterialIcon {
                id: upIcon
                anchors.centerIn: parent
                text: "drive_folder_upload"
                color: root.state.canNavigateUp ? Colours.palette.m3onSurface : Colours.palette.m3outline
                grade: 200
            }
        }

        StyledRect {
            id: pathBox
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            radius: Tokens.rounding.medium
            color: Colours.tPalette.m3surfaceContainerHigh
            // fixed height from text metrics — do NOT bind to flickable children
            implicitHeight: pathMetrics.height + Tokens.padding.small + Tokens.padding.extraSmall
            clip: true

            TextMetrics {
                id: pathMetrics
                font: Tokens.font.body.builders.small.weight(Font.Bold).build()
                text: "Ag"
            }

            // Click empty area to edit (under breadcrumbs)
            MouseArea {
                anchors.fill: parent
                enabled: !root.editingPath
                cursorShape: Qt.IBeamCursor
                onClicked: root.beginEdit()
                z: 0
            }

            // Breadcrumb row, clipped; overflow hidden (no height feedback into Layout)
            Item {
                id: crumbClip
                visible: !root.editingPath
                anchors.fill: parent
                anchors.margins: Tokens.padding.extraSmall / 2
                clip: true
                z: 1

                Row {
                    id: pathRow
                    // pin to right when overflowing so current folder stays visible
                    x: Math.min(0, crumbClip.width - width)
                    height: parent.height
                    spacing: 0

                    Repeater {
                        model: root.breadcrumbModel

                        Row {
                            id: folder

                            required property string modelData
                            required property int index

                            height: parent ? parent.height : 0
                            spacing: 0

                            StyledText {
                                visible: folder.index > 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: " / "
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.body.builders.small.weight(Font.Bold).build()
                            }

                            Item {
                                id: seg
                                height: parent.height
                                readonly property real nameCap: 160
                                readonly property real nameW: Math.min(folderName.fullWidth, nameCap)
                                readonly property real iconW: homeIcon.active ? 18 + Tokens.padding.extraSmall : 0
                                width: iconW + nameW + Tokens.padding.medium * 2

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: folder.index < root.breadcrumbModel.length - 1
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.state.slicePathSegment)
                                            root.state.slicePathSegment(folder.index);
                                        else
                                            root.state.sliceCwd(folder.index);
                                    }
                                    z: 2
                                }

                                Loader {
                                    id: homeIcon
                                    asynchronous: false
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: Tokens.padding.medium
                                    active: folder.index === 0 && (folder.modelData === "Home" || folder.modelData === "ThisPC" || folder.modelData === "Phone" || (root.state.isArchiveBrowse && folder.index === 0))
                                    sourceComponent: MaterialIcon {
                                        text: root.state.isArchiveBrowse ? "folder_zip" : (folder.modelData === "ThisPC" ? "computer" : (folder.modelData === "Phone" ? "smartphone" : "home"))
                                        color: (root.breadcrumbModel.length === 1) ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                                        fill: 1
                                    }
                                }

                                StyledText {
                                    id: folderName
                                    // measure full text without feeding Layout loops
                                    readonly property real fullWidth: Math.ceil(metrics.advanceWidth)
                                    TextMetrics {
                                        id: metrics
                                        font: folderName.font
                                        text: folderName.text
                                    }
                                    anchors.left: parent.left
                                    anchors.leftMargin: Tokens.padding.medium + seg.iconW
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.state.isArchiveBrowse ? folder.modelData : root.state.labelForSegment(folder.modelData)
                                    color: folder.index < root.breadcrumbModel.length - 1 ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3onSurface
                                    font: Tokens.font.body.builders.small.weight(Font.Bold).build()
                                    elide: Text.ElideMiddle
                                    width: seg.nameW
                                    maximumLineCount: 1
                                }
                            }
                        }
                    }
                }
            }

            TextInput {
                id: pathField
                visible: root.editingPath
                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.medium
                anchors.rightMargin: Tokens.padding.medium
                z: 2
                verticalAlignment: TextInput.AlignVCenter
                color: Colours.palette.m3onSurface
                font: Tokens.font.body.small
                selectByMouse: true
                clip: true
                wrapMode: TextInput.NoWrap
                Keys.onReturnPressed: root.commitEdit()
                Keys.onEnterPressed: root.commitEdit()
                Keys.onEscapePressed: root.cancelEdit()
                onActiveFocusChanged: {
                    if (!activeFocus && root.editingPath)
                        root.commitEdit();
                }
            }
        }

        Item {
            implicitWidth: implicitHeight
            implicitHeight: editIcon.implicitHeight + Tokens.padding.small
            Layout.minimumWidth: implicitWidth

            StateLayer {
                radius: Tokens.rounding.medium
                onClicked: {
                    if (root.editingPath)
                        root.commitEdit();
                    else
                        root.beginEdit();
                }
            }

            MaterialIcon {
                id: editIcon
                anchors.centerIn: parent
                text: root.editingPath ? "check" : "edit"
                color: Colours.palette.m3onSurface
                grade: 200
            }
        }
    }
}
