import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Keyboard shortcuts")

    function actionLabel(action: string): string {
        switch (action) {
        case "terminal": return qsTr("Open terminal");
        case "fileManager": return qsTr("Open file manager");
        case "launcher": return qsTr("Open app launcher");
        case "desktop": return qsTr("Show or hide desktop");
        case "nexus": return qsTr("Open settings");
        case "multitasking": return qsTr("Open multitasking overview");
        case "dashboard": return qsTr("Toggle dashboard");
        case "sidebar": return qsTr("Toggle sidebar");
        case "session": return qsTr("Open power menu");
        case "closeWindow": return qsTr("Close active window");
        case "fullscreen": return qsTr("Toggle fullscreen");
        case "toggleFloating": return qsTr("Toggle floating window");
        }
        return action;
    }

    function resetAll(): void {
        for (const action of ShortcutBindings.actionIds)
            ShortcutBindings.setShortcut(action, ShortcutBindings.defaults[action]);
    }

    component ShortcutEditor: ConnectedRect {
        id: editor

        required property string action
        required property string label
        property string message
        property bool recording
        property bool hasError
        readonly property string shortcut: ShortcutBindings.shortcut(action)

        Layout.fillWidth: true
        implicitHeight: content.implicitHeight + Tokens.padding.medium * 2
        focus: recording

        function keyName(event): string {
            switch (event.key) {
            case Qt.Key_Space: return "Space";
            case Qt.Key_Return:
            case Qt.Key_Enter: return "Return";
            case Qt.Key_Escape: return "Escape";
            case Qt.Key_Tab: return "Tab";
            case Qt.Key_Backtab: return "Tab";
            case Qt.Key_Left: return "Left";
            case Qt.Key_Right: return "Right";
            case Qt.Key_Up: return "Up";
            case Qt.Key_Down: return "Down";
            case Qt.Key_Home: return "Home";
            case Qt.Key_End: return "End";
            case Qt.Key_PageUp: return "Page_Up";
            case Qt.Key_PageDown: return "Page_Down";
            case Qt.Key_Comma: return "Comma";
            case Qt.Key_Less: return "Comma";
            case Qt.Key_Period: return "Period";
            case Qt.Key_Greater: return "Period";
            case Qt.Key_Slash: return "Slash";
            case Qt.Key_Question: return "Slash";
            case Qt.Key_Semicolon: return "Semicolon";
            case Qt.Key_Colon: return "Semicolon";
            case Qt.Key_Apostrophe: return "Apostrophe";
            case Qt.Key_QuoteDbl: return "Apostrophe";
            case Qt.Key_Minus: return "Minus";
            case Qt.Key_Underscore: return "Minus";
            case Qt.Key_Equal: return "Equal";
            case Qt.Key_Plus: return "Equal";
            }
            return event.text ? event.text.toUpperCase() : "";
        }

        Keys.onPressed: event => {
            if (!recording)
                return;
            event.accepted = true;
            if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
                ShortcutBindings.setShortcut(action, "");
                message = qsTr("Shortcut cleared");
                hasError = false;
                recording = false;
                return;
            }
            if ([Qt.Key_Meta, Qt.Key_Control, Qt.Key_Alt, Qt.Key_Shift, Qt.Key_Super_L, Qt.Key_Super_R].includes(event.key))
                return;
            const key = keyName(event);
            if (!key)
                return;
            const parts = [];
            if (event.modifiers & Qt.MetaModifier) parts.push("Super");
            if (event.modifiers & Qt.ControlModifier) parts.push("Ctrl");
            if (event.modifiers & Qt.AltModifier) parts.push("Alt");
            if (event.modifiers & Qt.ShiftModifier) parts.push("Shift");
            parts.push(key);
            const chord = parts.join("+");
            const duplicate = ShortcutBindings.duplicateAction(action, chord);
            if (duplicate) {
                message = qsTr("Already used by %1").arg(root.actionLabel(duplicate));
                hasError = true;
            } else {
                ShortcutBindings.setShortcut(action, chord);
                message = qsTr("Applied immediately");
                hasError = false;
            }
            recording = false;
        }

        RowLayout {
            id: content

            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.largeIncreased
            anchors.rightMargin: Tokens.padding.medium
            anchors.topMargin: Tokens.padding.medium
            anchors.bottomMargin: Tokens.padding.medium
            spacing: Tokens.spacing.medium

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: editor.label
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: editor.message
                    color: editor.hasError ? Colours.palette.m3error : Colours.palette.m3outline
                    font: Tokens.font.label.small
                    elide: Text.ElideRight
                }
            }

            IconTextButton {
                icon: editor.recording ? "keyboard" : "edit"
                text: editor.recording ? qsTr("Press shortcut") : (editor.shortcut || qsTr("Disabled"))
                type: IconTextButton.Tonal
                onClicked: {
                    editor.message = qsTr("Press the new key combination; Backspace clears it");
                    editor.hasError = false;
                    editor.recording = true;
                    editor.forceActiveFocus();
                }
            }

            IconButton {
                icon: "backspace"
                type: IconButton.Text
                enabled: editor.shortcut.length > 0
                onClicked: {
                    ShortcutBindings.setShortcut(editor.action, "");
                    editor.message = qsTr("Shortcut cleared");
                    editor.hasError = false;
                }
            }
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: 0

        SectionHeader {
            first: true
            text: qsTr("Apps and Shell")
        }

        ShortcutEditor { action: "terminal"; label: root.actionLabel(action); first: true }
        ShortcutEditor { action: "fileManager"; label: root.actionLabel(action) }
        ShortcutEditor { action: "launcher"; label: root.actionLabel(action) }
        ShortcutEditor { action: "desktop"; label: root.actionLabel(action) }
        ShortcutEditor { action: "nexus"; label: root.actionLabel(action) }
        ShortcutEditor { action: "multitasking"; label: root.actionLabel(action) }
        ShortcutEditor { action: "dashboard"; label: root.actionLabel(action) }
        ShortcutEditor { action: "sidebar"; label: root.actionLabel(action) }
        ShortcutEditor { action: "session"; label: root.actionLabel(action); last: true }

        SectionHeader { text: qsTr("Window management") }

        ShortcutEditor { action: "closeWindow"; label: root.actionLabel(action); first: true }
        ShortcutEditor { action: "fullscreen"; label: root.actionLabel(action) }
        ShortcutEditor { action: "toggleFloating"; label: root.actionLabel(action); last: true }

        IconTextButton {
            Layout.alignment: Qt.AlignRight
            Layout.topMargin: Tokens.spacing.large
            icon: "restart_alt"
            text: qsTr("Restore defaults")
            type: IconTextButton.Tonal
            onClicked: root.resetAll()
        }
    }
}
