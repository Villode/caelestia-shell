import QtQuick
import QtQuick.Layouts
import Caelestia
import Caelestia.Config
import qs.components
import qs.services

// Compact Mac-style glass capsule. Hyprland blurs drawers; use translucent
// surface so frost glass shows through (same as other shell panels).
StyledRect {
    id: root

    required property Toast modelData

    readonly property bool hasMessage: root.modelData.message && root.modelData.message.length > 0
    readonly property color accent: {
        if (root.modelData.type === Toast.Success)
            return Colours.palette.m3primary;
        if (root.modelData.type === Toast.Warning)
            return Colours.palette.m3secondary;
        if (root.modelData.type === Toast.Error)
            return Colours.palette.m3error;
        return Colours.palette.m3onSurfaceVariant;
    }

    // Hug content — not a wide fixed card
    implicitWidth: Math.min(280, layout.implicitWidth + Tokens.padding.large * 2)
    implicitHeight: layout.implicitHeight + Tokens.padding.small * 2 + 4

    // Capsule
    radius: height / 2
    color: Colours.tPalette.m3surfaceContainer
    border.width: 1
    border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.35)

    RowLayout {
        id: layout

        anchors.centerIn: parent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Tokens.padding.medium + 2
        anchors.rightMargin: Tokens.padding.large
        spacing: Tokens.spacing.small

        // Compact round glyph
        StyledRect {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 22
            Layout.preferredHeight: 22
            radius: Tokens.rounding.full
            color: Qt.alpha(root.accent, root.modelData.type === Toast.Info ? 0.18 : 0.9)

            MaterialIcon {
                anchors.centerIn: parent
                text: root.modelData.icon || "info"
                fill: 1
                color: {
                    if (root.modelData.type === Toast.Success)
                        return Colours.palette.m3onPrimary;
                    if (root.modelData.type === Toast.Warning)
                        return Colours.palette.m3onSecondary;
                    if (root.modelData.type === Toast.Error)
                        return Colours.palette.m3onError;
                    return root.accent;
                }
                fontStyle: Tokens.font.icon.builders.small.scale(1.05).build()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            Layout.maximumWidth: 220
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.modelData.title
                color: Colours.palette.m3onSurface
                font: Tokens.font.label.medium
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.hasMessage
                text: root.modelData.message
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
                elide: Text.ElideRight
                maximumLineCount: 1
                opacity: 0.9
            }
        }
    }
}
