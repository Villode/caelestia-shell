import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    property string selectedAction: "terminal"
    property string selectedShortcut
    property var highlightedKeys: ({})
    readonly property var keyboardRows: [
        ["Esc", "__gap", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12", "__gap", "Print", "Scroll", "Pause", "__gap", "__blank", "__blank", "__blank", "__blank"],
        ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "Backspace", "__gap", "Insert", "Home", "PgUp", "__gap", "Num", "/", "*", "-"],
        ["Tab", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]", "\\", "__gap", "Delete", "End", "PgDn", "__gap", "7", "8", "9", "+"],
        ["Caps", "A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'", "Return", "__gap", "__blank", "__blank", "__blank", "__gap", "4", "5", "6", "+"],
        ["Shift", "Z", "X", "C", "V", "B", "N", "M", ",", ".", "/", "Shift", "__gap", "__blank", "↑", "__blank", "__gap", "1", "2", "3", "Enter"],
        ["Ctrl", "Super", "Alt", "Space", "Alt", "Super", "Ctrl", "__gap", "←", "↓", "→", "__gap", "0", "__blank", ".", "Enter"]
    ]
    function refreshPreview(): void {
        selectedShortcut = ShortcutBindings.shortcut(selectedAction);
        const keys = {};
        for (const part of selectedShortcut.split("+")) {
            const key = normalizedKey(part.trim());
            if (key)
                keys[key] = true;
        }
        highlightedKeys = keys;
    }

    function selectAction(action: string): void {
        selectedAction = action;
        refreshPreview();
    }

    title: qsTr("Keyboard shortcuts")

    function normalizedKey(key: string): string {
        const aliases = {
            "esc": "escape", "enter": "return", "caps": "capslock", "`": "grave",
            "-": "minus", "=": "equal", "[": "bracketleft", "]": "bracketright", "\\": "backslash",
            ";": "semicolon", "'": "apostrophe", ",": "comma", ".": "period", "/": "slash",
            "←": "left", "→": "right", "↑": "up", "↓": "down", "pgup": "pageup", "pgdn": "pagedown",
            "control": "ctrl", "meta": "super"
        };
        const lower = String(key).toLowerCase().split("_").join("");
        return aliases[lower] ?? lower;
    }

    function keyUnits(key: string): real {
        switch (key) {
        case "__gap": return 0.5;
        case "__blank": return 1;
        case "Backspace": return 2;
        case "Tab": return 1.5;
        case "\\": return 1.5;
        case "Caps": return 1.75;
        case "Return": return 2.25;
        case "Shift": return 2.4;
        case "Ctrl":
        case "Super":
        case "Alt": return 1.45;
        case "Space": return 5.5;
        }
        return 1;
    }

    function keyLabel(key: string): string {
        switch (key) {
        case "__gap":
        case "__blank": return "";
        case "Backspace": return "⌫";
        case "Return": return "↵";
        case "Enter": return "↵";
        case "Shift": return "⇧";
        case "Print": return "Prt";
        case "Scroll": return "Scr";
        case "Pause": return "Pse";
        case "Insert": return "Ins";
        case "Delete": return "Del";
        case "PgUp": return "Pg↑";
        case "PgDn": return "Pg↓";
        }
        return key;
    }

    function actionLabel(action: string): string {
        switch (action) {
        case "terminal": return qsTr("Open terminal");
        case "fileManager": return qsTr("Open file manager");
        case "launcher": return qsTr("Open app launcher");
        case "desktop": return qsTr("Show or hide desktop");
        case "screenshot": return qsTr("Take a screenshot");
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

    function actionIcon(action: string): string {
        switch (action) {
        case "terminal": return "terminal";
        case "fileManager": return "folder";
        case "launcher": return "apps";
        case "desktop": return "desktop_windows";
        case "screenshot": return "screenshot";
        case "nexus": return "settings";
        case "multitasking": return "view_carousel";
        case "dashboard": return "dashboard";
        case "sidebar": return "dock_to_right";
        case "session": return "power_settings_new";
        case "closeWindow": return "close";
        case "fullscreen": return "fullscreen";
        case "toggleFloating": return "select_window";
        }
        return "keyboard";
    }

    function resetAll(): void {
        for (const action of ShortcutBindings.actionIds)
            ShortcutBindings.setShortcut(action, ShortcutBindings.defaults[action]);
        refreshPreview();
    }

    Component.onCompleted: refreshPreview()

    property Connections shortcutConnections: Connections {
        target: GlobalConfig.general.shortcuts

        function onTerminalChanged(): void { root.refreshPreview(); }
        function onFileManagerChanged(): void { root.refreshPreview(); }
        function onLauncherChanged(): void { root.refreshPreview(); }
        function onDesktopChanged(): void { root.refreshPreview(); }
        function onScreenshotChanged(): void { root.refreshPreview(); }
        function onNexusChanged(): void { root.refreshPreview(); }
        function onMultitaskingChanged(): void { root.refreshPreview(); }
        function onDashboardChanged(): void { root.refreshPreview(); }
        function onSidebarChanged(): void { root.refreshPreview(); }
        function onSessionChanged(): void { root.refreshPreview(); }
        function onCloseWindowChanged(): void { root.refreshPreview(); }
        function onFullscreenChanged(): void { root.refreshPreview(); }
        function onToggleFloatingChanged(): void { root.refreshPreview(); }
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
        Layout.topMargin: editor.first ? 0 : Tokens.spacing.small
        implicitHeight: content.implicitHeight + Tokens.padding.small * 2
        topLeftRadius: Tokens.rounding.extraLarge
        topRightRadius: Tokens.rounding.extraLarge
        bottomLeftRadius: Tokens.rounding.extraLarge
        bottomRightRadius: Tokens.rounding.extraLarge
        border.width: root.selectedAction === action ? 1 : 0
        border.color: Colours.palette.m3primary
        focus: recording

        TapHandler {
            onTapped: root.selectAction(editor.action)
        }

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
                root.refreshPreview();
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
                root.refreshPreview();
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

            StyledRect {
                implicitWidth: 42
                implicitHeight: 42
                radius: Tokens.rounding.full
                color: editor.recording ? Colours.palette.m3primaryContainer : Colours.tPalette.m3surfaceContainerHigh

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.actionIcon(editor.action)
                    color: editor.recording ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium
                    fill: editor.recording ? 1 : 0
                }
            }

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

            ButtonBase {
                id: shortcutButton

                implicitWidth: Math.max(132, shortcutContent.implicitWidth + Tokens.padding.medium * 2)
                implicitHeight: 42
                checked: editor.recording
                type: ButtonBase.Tonal
                inactiveColour: Colours.palette.m3secondaryContainer
                inactiveOnColour: Colours.palette.m3onSecondaryContainer
                activeColour: Colours.palette.m3primary
                activeOnColour: Colours.palette.m3onPrimary
                onClicked: {
                    root.selectAction(editor.action);
                    editor.message = qsTr("Press the new key combination; Backspace clears it");
                    editor.hasError = false;
                    editor.recording = true;
                    editor.forceActiveFocus();
                }

                RowLayout {
                    id: shortcutContent

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        visible: editor.recording
                        text: "keyboard"
                        color: shortcutButton.onColour
                        fontStyle: Tokens.font.icon.small
                    }

                    StyledText {
                        visible: editor.recording || !editor.shortcut
                        text: editor.recording ? qsTr("Waiting for keys…") : qsTr("Not assigned")
                        color: shortcutButton.onColour
                        font: Tokens.font.label.medium
                    }

                    Repeater {
                        model: editor.recording ? [] : editor.shortcut.split("+").filter(key => key.length > 0)

                        RowLayout {
                            required property string modelData
                            required property int index
                            spacing: Tokens.spacing.extraSmall

                            StyledRect {
                                implicitWidth: keyLabel.implicitWidth + Tokens.padding.small * 2
                                implicitHeight: 26
                                radius: Tokens.rounding.small
                                color: Qt.alpha(shortcutButton.onColour, 0.1)
                                border.width: 1
                                border.color: Qt.alpha(shortcutButton.onColour, 0.24)

                                StyledText {
                                    id: keyLabel
                                    anchors.centerIn: parent
                                    text: parent.parent.modelData
                                    color: shortcutButton.onColour
                                    font: Tokens.font.label.medium
                                }
                            }

                            StyledText {
                                visible: index < editor.shortcut.split("+").length - 1
                                text: "+"
                                color: shortcutButton.onColour
                                font: Tokens.font.label.small
                            }
                        }
                    }
                }
            }

            IconButton {
                icon: "backspace"
                type: IconButton.Text
                enabled: editor.shortcut.length > 0
                onClicked: {
                    root.selectAction(editor.action);
                    ShortcutBindings.setShortcut(editor.action, "");
                    root.refreshPreview();
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
            text: qsTr("Keyboard shortcuts")
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.small
            Layout.rightMargin: Tokens.padding.small
            spacing: Tokens.spacing.medium

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "keyboard_alt"
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.large
                    fill: 1
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Previewing %1").arg(root.actionLabel(root.selectedAction))
                        font: Tokens.font.body.medium
                        wrapMode: Text.Wrap
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.selectedShortcut ? qsTr("Highlighted keys: %1").arg(root.selectedShortcut.split("+").join(" + ")) : qsTr("No shortcut assigned")
                        color: Colours.palette.m3outline
                        font: Tokens.font.body.small
                        wrapMode: Text.Wrap
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall

                Repeater {
                    model: root.keyboardRows

                    RowLayout {
                        id: keyboardRow

                        required property var modelData
                        readonly property var keys: modelData

                        Layout.fillWidth: true
                        spacing: Tokens.spacing.extraSmall

                        Repeater {
                            model: keyboardRow.keys

                            StyledRect {
                                id: keyboardKey

                                required property string modelData
                                readonly property bool spacer: modelData === "__gap" || modelData === "__blank"
                                readonly property bool active: !spacer && root.highlightedKeys[root.normalizedKey(modelData)] === true

                                Layout.fillWidth: true
                                Layout.preferredWidth: root.keyUnits(modelData) * 32
                                implicitHeight: 32
                                radius: Tokens.rounding.small
                                color: spacer ? "transparent" : active ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainerHigh
                                border.width: spacer || active ? 0 : 1
                                border.color: Colours.palette.m3outlineVariant

                                StyledText {
                                    anchors.centerIn: parent
                                    text: root.keyLabel(keyboardKey.modelData)
                                    color: keyboardKey.active ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                                    font: Tokens.font.label.small
                                }
                            }
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Select a shortcut below to preview or change it. Changes apply immediately.")
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
                wrapMode: Text.Wrap
            }
        }

        SectionHeader { text: qsTr("Applications") }

        ShortcutEditor { action: "terminal"; label: root.actionLabel(action); first: true }
        ShortcutEditor { action: "fileManager"; label: root.actionLabel(action) }
        ShortcutEditor { action: "launcher"; label: root.actionLabel(action) }
        ShortcutEditor { action: "desktop"; label: root.actionLabel(action) }
        ShortcutEditor { action: "screenshot"; label: root.actionLabel(action); last: true }

        SectionHeader { text: qsTr("Shell controls") }

        ShortcutEditor { action: "nexus"; label: root.actionLabel(action); first: true }
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
