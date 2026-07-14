pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services
import qs.utils

// Centered power menu: horizontal actions (not a side rail).
RowLayout {
    id: root

    required property DrawerVisibilities visibilities

    spacing: Tokens.spacing.large

    SessionButton {
        id: logout

        iconName: Config.session.icons.logout
        command: Config.session.commands.logout
        caption: qsTr("Log out")
        navLeft: null
        navRight: shutdown

        Component.onCompleted: forceActiveFocus()

        Connections {
            function onLauncherChanged(): void {
                if (!root.visibilities.launcher)
                    logout.forceActiveFocus();
            }

            target: root.visibilities
        }
    }

    SessionButton {
        id: shutdown

        iconName: Config.session.icons.shutdown
        command: Config.session.commands.shutdown
        caption: qsTr("Shut down")
        navLeft: logout
        navRight: hibernate
    }

    AnimatedImage {
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: Tokens.sizes.session.button * 0.85
        Layout.preferredHeight: Tokens.sizes.session.button * 0.85
        sourceSize.width: width * ((QsWindow.window as QsWindow)?.devicePixelRatio ?? 1)
        visible: status === AnimatedImage.Ready && source.toString().length > 0
        playing: visible
        asynchronous: true
        speed: Config.general.sessionGifSpeed
        source: Paths.absolutePath(Config.paths.sessionGif)
        fillMode: AnimatedImage.PreserveAspectFit
    }

    SessionButton {
        id: hibernate

        iconName: Config.session.icons.hibernate
        command: Config.session.commands.hibernate
        caption: qsTr("Hibernate")
        navLeft: shutdown
        navRight: reboot
    }

    SessionButton {
        id: reboot

        iconName: Config.session.icons.reboot
        command: Config.session.commands.reboot
        caption: qsTr("Reboot")
        navLeft: hibernate
        navRight: null
    }

    component SessionButton: ColumnLayout {
        id: buttonRoot

        required property list<string> command
        required property string iconName
        property string caption: ""
        property var navLeft: null
        property var navRight: null

        spacing: Tokens.spacing.extraSmall
        Layout.alignment: Qt.AlignVCenter

        function exec(): void {
            root.visibilities.session = false;
            if (!SessionManager.exec(command))
                Quickshell.execDetached(command);
        }

        function forceActiveFocus(): void {
            btn.forceActiveFocus();
        }

        IconButton {
            id: btn

            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Tokens.sizes.session.button
            Layout.preferredHeight: Tokens.sizes.session.button

            icon: buttonRoot.iconName
            inactiveColour: activeFocus ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainerHigh
            inactiveOnColour: activeFocus ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
            radius: pressed ? Tokens.rounding.medium : activeFocus ? Tokens.rounding.extraLarge : Tokens.rounding.largeIncreased
            font: Tokens.font.icon.builders.large.scale(1.25).build()
            onClicked: buttonRoot.exec()

            Keys.onEnterPressed: buttonRoot.exec()
            Keys.onReturnPressed: buttonRoot.exec()
            Keys.onEscapePressed: root.visibilities.session = false
            Keys.onPressed: event => {
                if ((event.key === Qt.Key_Right || event.key === Qt.Key_Tab) && buttonRoot.navRight) {
                    buttonRoot.navRight.forceActiveFocus();
                    event.accepted = true;
                } else if ((event.key === Qt.Key_Left || event.key === Qt.Key_Backtab) && buttonRoot.navLeft) {
                    buttonRoot.navLeft.forceActiveFocus();
                    event.accepted = true;
                } else if (Config.session.vimKeybinds && (event.modifiers & Qt.ControlModifier)) {
                    if ((event.key === Qt.Key_L || event.key === Qt.Key_J || event.key === Qt.Key_N) && buttonRoot.navRight) {
                        buttonRoot.navRight.forceActiveFocus();
                        event.accepted = true;
                    } else if ((event.key === Qt.Key_H || event.key === Qt.Key_K || event.key === Qt.Key_P) && buttonRoot.navLeft) {
                        buttonRoot.navLeft.forceActiveFocus();
                        event.accepted = true;
                    }
                }
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            visible: buttonRoot.caption.length > 0
            text: buttonRoot.caption
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }
    }
}
