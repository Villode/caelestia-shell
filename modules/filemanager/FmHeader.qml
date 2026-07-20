pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

StyledRect {
    id: root

    required property var state

    implicitHeight: inner.implicitHeight + Tokens.padding.medium * 2
    color: Colours.tPalette.m3surfaceContainer

    RowLayout {
        id: inner

        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        spacing: Tokens.spacing.small

        Item {
            implicitWidth: implicitHeight
            implicitHeight: upIcon.implicitHeight + Tokens.padding.small

            StateLayer {
                radius: Tokens.rounding.medium
                disabled: root.state.isThisPC
                onClicked: root.state.popDir()
            }

            MaterialIcon {
                id: upIcon
                anchors.centerIn: parent
                text: "drive_folder_upload"
                color: root.state.isThisPC ? Colours.palette.m3outline : Colours.palette.m3onSurface
                grade: 200
            }
        }

        StyledRect {
            Layout.fillWidth: true
            radius: Tokens.rounding.medium
            color: Colours.tPalette.m3surfaceContainerHigh
            implicitHeight: pathComponents.implicitHeight + pathComponents.anchors.margins * 2

            RowLayout {
                id: pathComponents

                anchors.fill: parent
                anchors.margins: Tokens.padding.extraSmall / 2
                anchors.leftMargin: 0
                spacing: Tokens.spacing.small

                Repeater {
                    model: root.state.cwd

                    RowLayout {
                        id: folder

                        required property string modelData
                        required property int index

                        spacing: 0

                        Loader {
                            asynchronous: true
                            Layout.rightMargin: Tokens.spacing.small
                            active: folder.index > 0
                            sourceComponent: StyledText {
                                text: "/"
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.body.builders.small.weight(Font.Bold).build()
                            }
                        }

                        Item {
                            implicitWidth: homeIcon.implicitWidth + (homeIcon.active ? Tokens.padding.extraSmall : 0) + folderName.implicitWidth + Tokens.padding.medium * 2
                            implicitHeight: folderName.implicitHeight + Tokens.padding.small

                            Loader {
                                asynchronous: true
                                anchors.fill: parent
                                active: folder.index < root.state.cwd.length - 1
                                sourceComponent: StateLayer {
                                    onClicked: root.state.sliceCwd(folder.index)
                                    radius: Tokens.rounding.medium
                                }
                            }

                            Loader {
                                id: homeIcon
                                asynchronous: true
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: Tokens.padding.medium
                                active: folder.index === 0 && (folder.modelData === "Home" || folder.modelData === "ThisPC")
                                sourceComponent: MaterialIcon {
                                    text: folder.modelData === "ThisPC" ? "computer" : "home"
                                    color: root.state.cwd.length === 1 ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                                    fill: 1
                                }
                            }

                            StyledText {
                                id: folderName
                                anchors.left: homeIcon.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: homeIcon.active ? Tokens.padding.extraSmall : 0
                                // Chinese labels for XDG places
                                text: root.state.labelForSegment(folder.modelData)
                                color: folder.index < root.state.cwd.length - 1 ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3onSurface
                                font: Tokens.font.body.builders.small.weight(Font.Bold).build()
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }
            }
        }
    }
}
