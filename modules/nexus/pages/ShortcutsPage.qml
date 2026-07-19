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
    // Single source of truth for which editor is recording; empty means none.
    property string recordingAction: ""

    // ROG-style full laptop layout: integrated numpad, dual Fn, sys keys on
    // the function row, and arrows between the main cluster and numpad.
    // Every row totals the same unit budget so left-aligned columns stay straight.
    // NumAdd/NumEnter span 2 rows; NumAdd2/NumEnter2 are invisible placeholders.
    readonly property var keyboardRows: [
        ["Esc", "__fgap", "F1", "F2", "F3", "F4", "__fgap", "F5", "F6", "F7", "F8", "__fgap", "F9", "F10", "F11", "F12", "__fgap", "Delete", "Pause", "Print", "Home"],
        ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "Backspace", "__nav", "NumLk", "NumDiv", "NumMul", "NumSub"],
        ["Tab", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]", "\\", "__nav", "Num7", "Num8", "Num9", "NumAdd"],
        ["Caps", "A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'", "Return", "__nav", "Num4", "Num5", "Num6", "NumAdd2"],
        ["Shift", "Z", "X", "C", "V", "B", "N", "M", ",", ".", "/", "ShiftR", "__blank", "↑", "__blank", "Num1", "Num2", "Num3", "NumEnter"],
        ["Ctrl", "Fn", "Super", "Alt", "Space", "AltR", "FnR", "CtrlR", "←", "↓", "→", "Num0", "NumDel", "NumEnter2"]
    ]

    readonly property real keyboardMaxUnits: {
        let maxUnits = 0;
        for (const row of keyboardRows) {
            let units = 0;
            for (const key of row)
                units += keyUnits(key);
            maxUnits = Math.max(maxUnits, units);
        }
        return maxUnits;
    }

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
        // Switching to another row (or re-selecting) ends an in-progress capture.
        if (recordingAction && recordingAction !== action)
            cancelActiveRecording();
        selectedAction = action;
        refreshPreview();
    }

    function cancelActiveRecording(): void {
        if (!recordingAction)
            return;
        recordingAction = "";
        refreshPreview();
    }

    function beginRecording(action: string): void {
        if (recordingAction && recordingAction !== action)
            cancelActiveRecording();
        selectedAction = action;
        refreshPreview();
        recordingAction = action;
    }

    title: qsTr("Keyboard shortcuts")

    // Blank page clicks cancel an open capture without clearing the binding.
    Item {
        anchors.fill: parent
        z: -1

        TapHandler {
            acceptedButtons: Qt.LeftButton
            gesturePolicy: TapHandler.DragThreshold
            onTapped: root.cancelActiveRecording()
        }
    }

    function normalizedKey(key: string): string {
        const aliases = {
            "esc": "escape",
            "enter": "return",
            "caps": "capslock",
            "capslock": "capslock",
            "`": "grave",
            "-": "minus",
            "=": "equal",
            "[": "bracketleft",
            "]": "bracketright",
            "\\": "backslash",
            ";": "semicolon",
            "'": "apostrophe",
            ",": "comma",
            ".": "period",
            "/": "slash",
            "←": "left",
            "→": "right",
            "↑": "up",
            "↓": "down",
            "pgup": "pageup",
            "pgdn": "pagedown",
            "control": "ctrl",
            "meta": "super",
            "shiftr": "shift",
            "printscreen": "print",
            "prtsc": "print",
            "altr": "alt",
            "ctrlr": "ctrl",
            "fnr": "fn",
            "numlk": "numlock",
            "numlock": "numlock",
            "numdiv": "slash",
            "nummul": "asterisk",
            "numsub": "minus",
            "numadd": "plus",
            "numadd2": "plus",
            "numenter": "return",
            "numenter2": "return",
            "num0": "0",
            "num1": "1",
            "num2": "2",
            "num3": "3",
            "num4": "4",
            "num5": "5",
            "num6": "6",
            "num7": "7",
            "num8": "8",
            "num9": "9",
            "numdel": "delete"
        };
        const lower = String(key).toLowerCase().split("_").join("");
        return aliases[lower] ?? lower;
    }

    function keyUnits(key: string): real {
        switch (key) {
        case "__gap":
            return 0.4;
        case "__fgap":
            // Four F-row gaps: 1 + 4*fgap + 12 + 4 = 22 → fgap = 1.25
            return 1.25;
        case "__nav":
            // Same width as the arrow island (blank + ↑ + blank / ← ↓ →)
            return 3;
        case "__blank":
            return 1;
        case "Backspace":
            return 2;
        case "Tab":
            return 1.5;
        case "\\":
            return 1.5;
        case "Caps":
            return 1.75;
        case "Return":
            return 2.25;
        case "Shift":
            return 2.25;
        case "ShiftR":
            return 2.75;
        case "Ctrl":
        case "CtrlR":
        case "Super":
        case "Alt":
        case "AltR":
        case "Fn":
        case "FnR":
            return 1.15;
        case "Space":
            // 7 × 1.15 = 8.05; 15 − 8.05 = 6.95 keeps the main cluster at 15u
            return 6.95;
        case "Num0":
            return 2;
        case "NumAdd":
        case "NumAdd2":
        case "NumEnter":
        case "NumEnter2":
            return 1;
        case "F1":
        case "F2":
        case "F3":
        case "F4":
        case "F5":
        case "F6":
        case "F7":
        case "F8":
        case "F9":
        case "F10":
        case "F11":
        case "F12":
        case "Print":
        case "Scroll":
        case "Pause":
        case "Esc":
        case "Delete":
        case "Home":
            return 1;
        }
        return 1;
    }

    function keyLabel(key: string): string {
        switch (key) {
        case "__gap":
        case "__fgap":
        case "__nav":
        case "__blank":
        case "NumAdd2":
        case "NumEnter2":
            return "";
        case "Backspace":
            return "⌫";
        case "Return":
        case "Enter":
            return "↵";
        case "Shift":
        case "ShiftR":
            return "⇧";
        case "Print":
            return "PrtSc";
        case "Scroll":
            return "Scr";
        case "Pause":
            return "Pse";
        case "Insert":
            return "Ins";
        case "Delete":
            return "Del";
        case "Home":
            return "Home";
        case "PgUp":
            return "Pg↑";
        case "PgDn":
            return "Pg↓";
        case "Caps":
            return "Caps";
        case "Super":
            return "";  // rendered as Win icon in KeyCap / chips
        case "Ctrl":
        case "CtrlR":
            return "Ctrl";
        case "Alt":
        case "AltR":
            return "Alt";
        case "Fn":
        case "FnR":
            return "Fn";
        case "Space":
            return "";
        case "NumLk":
            return "Num";
        case "NumDiv":
            return "/";
        case "NumMul":
            return "*";
        case "NumSub":
            return "−";
        case "NumAdd":
            return "+";
        case "NumEnter":
            return "↵";
        case "Num0":
            return "0";
        case "Num1":
            return "1";
        case "Num2":
            return "2";
        case "Num3":
            return "3";
        case "Num4":
            return "4";
        case "Num5":
            return "5";
        case "Num6":
            return "6";
        case "Num7":
            return "7";
        case "Num8":
            return "8";
        case "Num9":
            return "9";
        case "NumDel":
            return "Del";
        }
        return key;
    }

    function keyIsModifier(key: string): bool {
        switch (key) {
        case "Ctrl":
        case "CtrlR":
        case "Super":
        case "Alt":
        case "AltR":
        case "Fn":
        case "FnR":
        case "Shift":
        case "ShiftR":
        case "Caps":
        case "Tab":
        case "Esc":
            return true;
        }
        return false;
    }

    function chordParts(shortcut: string): var {
        if (!shortcut)
            return [];
        return shortcut.split("+").map(part => part.trim()).filter(part => part.length > 0);
    }

    function prettyChordPart(part: string): string {
        switch (String(part).toLowerCase()) {
        case "super":
            return "";  // Win icon in chord chip
        case "ctrl":
        case "control":
            return "Ctrl";
        case "alt":
            return "Alt";
        case "shift":
            return "Shift";
        case "return":
        case "enter":
            return "↵";
        case "escape":
            return "Esc";
        case "comma":
            return ",";
        case "period":
            return ".";
        case "slash":
            return "/";
        case "print":
            return "PrtSc";
        case "space":
            return "Space";
        case "page_up":
        case "pageup":
            return "PgUp";
        case "page_down":
        case "pagedown":
            return "PgDn";
        }
        if (part.length === 1)
            return part.toUpperCase();
        return part;
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


    // Four-pane Windows-style logo (Material Icons has no true Win glyph).
    component WinLogo: Item {
        id: winLogo

        property color colour: Colours.palette.m3onSurface
        property real size: 14

        implicitWidth: size
        implicitHeight: size

        readonly property real gap: Math.max(1.1, size * 0.14)
        readonly property real pane: Math.max(2.2, (size - gap) / 2)

        Repeater {
            model: 4

            StyledRect {
                required property int index
                width: winLogo.pane
                height: winLogo.pane
                radius: Math.max(0.5, winLogo.size * 0.08)
                color: winLogo.colour
                x: (index % 2) * (winLogo.pane + winLogo.gap)
                y: Math.floor(index / 2) * (winLogo.pane + winLogo.gap)
            }
        }
    }

    component ShortcutEditor: ConnectedRect {
        id: editor

        required property string action
        required property string label
        property string message
        property bool hasError
        readonly property bool recording: root.recordingAction === action
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

        // Keep row taps exclusive so the page blank TapHandler does not also fire.
        TapHandler {
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: {
                if (editor.recording)
                    editor.cancelRecording();
                else if (root.recordingAction && root.recordingAction !== editor.action)
                    root.cancelActiveRecording();
                root.selectAction(editor.action);
            }
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
            // Print/SysReq produce no event.text on Wayland, so they must be
            // mapped explicitly or shortcut capture silently ignores them.
            case Qt.Key_Print: return "Print";
            case Qt.Key_SysReq: return "Print";
            case Qt.Key_ScrollLock: return "Scroll_Lock";
            case Qt.Key_Pause: return "Pause";
            case Qt.Key_Insert: return "Insert";
            case Qt.Key_Delete: return "Delete";
            case Qt.Key_Menu: return "Menu";
            case Qt.Key_F1: return "F1";
            case Qt.Key_F2: return "F2";
            case Qt.Key_F3: return "F3";
            case Qt.Key_F4: return "F4";
            case Qt.Key_F5: return "F5";
            case Qt.Key_F6: return "F6";
            case Qt.Key_F7: return "F7";
            case Qt.Key_F8: return "F8";
            case Qt.Key_F9: return "F9";
            case Qt.Key_F10: return "F10";
            case Qt.Key_F11: return "F11";
            case Qt.Key_F12: return "F12";
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
            // Prefer nativeVirtualKey / key when text is empty (media/sys keys).
            if (event.text && event.text.length > 0)
                return event.text.toUpperCase();
            return "";
        }

        function cancelRecording(): void {
            if (!recording)
                return;
            root.cancelActiveRecording();
            hasError = false;
            message = qsTr("Cancelled; original shortcut kept");
        }

        // Another row or blank area cleared root.recordingAction — surface cancel text.
        onRecordingChanged: {
            if (!recording && message === qsTr("Press the new key combination; Esc cancels, Backspace clears")) {
                hasError = false;
                message = qsTr("Cancelled; original shortcut kept");
            }
        }

        Keys.onPressed: event => {
            if (!recording)
                return;
            event.accepted = true;
            // Esc alone cancels recording and keeps the previous binding.
            if (event.key === Qt.Key_Escape && event.modifiers === Qt.NoModifier) {
                cancelRecording();
                return;
            }
            // Explicit clear only — not cancel.
            if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
                ShortcutBindings.setShortcut(action, "");
                root.cancelActiveRecording();
                root.refreshPreview();
                message = qsTr("Shortcut cleared");
                hasError = false;
                return;
            }
            if ([Qt.Key_Meta, Qt.Key_Control, Qt.Key_Alt, Qt.Key_Shift, Qt.Key_Super_L, Qt.Key_Super_R].includes(event.key))
                return;
            const key = keyName(event);
            if (!key)
                return;
            const parts = [];
            if (event.modifiers & Qt.MetaModifier)
                parts.push("Super");
            if (event.modifiers & Qt.ControlModifier)
                parts.push("Ctrl");
            if (event.modifiers & Qt.AltModifier)
                parts.push("Alt");
            if (event.modifiers & Qt.ShiftModifier)
                parts.push("Shift");
            parts.push(key);
            const chord = parts.join("+");
            const duplicate = ShortcutBindings.duplicateAction(action, chord);
            if (duplicate) {
                // Keep original binding; just surface the conflict.
                message = qsTr("Already used by %1").arg(root.actionLabel(duplicate));
                hasError = true;
                root.cancelActiveRecording();
            } else {
                ShortcutBindings.setShortcut(action, chord);
                root.cancelActiveRecording();
                root.refreshPreview();
                message = qsTr("Applied immediately");
                hasError = false;
            }
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
                    if (editor.recording) {
                        // Click again to cancel without clearing the binding.
                        editor.cancelRecording();
                        root.selectAction(editor.action);
                        return;
                    }
                    // Starting capture here also cancels any other open capture.
                    editor.message = qsTr("Press the new key combination; Esc cancels, Backspace clears");
                    editor.hasError = false;
                    root.beginRecording(editor.action);
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
                            id: partRow
                            required property string modelData
                            required property int index
                            spacing: Tokens.spacing.extraSmall

                            StyledRect {
                                readonly property bool isSuper: String(partRow.modelData).toLowerCase() === "super"
                                implicitWidth: isSuper
                                    ? 28
                                    : keyLabel.implicitWidth + Tokens.padding.small * 2
                                implicitHeight: 26
                                radius: Tokens.rounding.small
                                color: Qt.alpha(shortcutButton.onColour, 0.1)
                                border.width: 1
                                border.color: Qt.alpha(shortcutButton.onColour, 0.24)

                                WinLogo {
                                    anchors.centerIn: parent
                                    visible: parent.isSuper
                                    size: 11
                                    colour: shortcutButton.onColour
                                }

                                StyledText {
                                    id: keyLabel
                                    anchors.centerIn: parent
                                    visible: !parent.isSuper
                                    text: root.prettyChordPart(partRow.modelData) || partRow.modelData
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
                    root.cancelActiveRecording();
                    root.selectAction(editor.action);
                    ShortcutBindings.setShortcut(editor.action, "");
                    root.refreshPreview();
                    editor.message = qsTr("Shortcut cleared");
                    editor.hasError = false;
                }
            }
        }
    }


    function keyRowSpan(key: string): int {
        switch (key) {
        case "NumAdd":
        case "NumEnter":
            return 2;
        }
        return 1;
    }

    function keyIsPlaceholder(key: string): bool {
        return key === "NumAdd2" || key === "NumEnter2";
    }

    function keyIsSpacer(key: string): bool {
        return key === "__gap" || key === "__fgap" || key === "__nav" || key === "__blank" || keyIsPlaceholder(key);
    }

    component KeyCap: Item {
        id: keyCap

        required property string keyId
        required property real unit
        required property real unitWidth
        required property real keyHeight
        required property real rowSpacing

        readonly property bool spacer: root.keyIsSpacer(keyId)
        readonly property bool tall: root.keyRowSpan(keyId) > 1
        readonly property bool active: !spacer && root.highlightedKeys[root.normalizedKey(keyId)] === true
        readonly property bool modifierLike: root.keyIsModifier(keyId)
        readonly property string label: root.keyLabel(keyId)
        readonly property real capHeight: keyHeight * root.keyRowSpan(keyId) + (root.keyRowSpan(keyId) - 1) * rowSpacing

        width: unit * unitWidth
        height: keyHeight
        z: tall ? 2 : 1
        clip: false

        // Drawn body; tall keys overflow into the next row over their placeholders.
        StyledRect {
            id: capBody

            x: keyCap.spacer ? 0 : 1.5
            y: keyCap.spacer ? 0 : 1.5
            width: Math.max(0, keyCap.width - (keyCap.spacer ? 0 : 3))
            height: Math.max(0, keyCap.capHeight - (keyCap.spacer ? 0 : 3))
            visible: !keyCap.spacer
            radius: Tokens.rounding.small
            color: {
                if (keyCap.spacer)
                    return "transparent";
                if (keyCap.active)
                    return Colours.palette.m3primary;
                if (keyCap.modifierLike)
                    return Colours.palette.m3surfaceContainerHighest;
                return Colours.tPalette.m3surfaceContainerHigh;
            }
            border.width: keyCap.spacer ? 0 : keyCap.active ? 0 : 1
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, keyCap.modifierLike ? 0.55 : 0.35)

            // Soft top sheen for a physical keycap feel.
            StyledRect {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 1
                height: Math.max(6, parent.height * 0.28)
                radius: Math.max(2, parent.radius - 1)
                visible: !keyCap.spacer && !keyCap.active
                color: Qt.alpha(Colours.palette.m3onSurface, Colours.light ? 0.06 : 0.08)
            }

            // Bottom lip / depth.
            StyledRect {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 2
                radius: parent.radius
                visible: !keyCap.spacer && !keyCap.active
                color: Qt.alpha(Colours.palette.m3onSurface, Colours.light ? 0.08 : 0.22)
            }

            // Active glow ring.
            StyledRect {
                anchors.fill: parent
                anchors.margins: -2
                z: -1
                radius: parent.radius + 2
                visible: keyCap.active
                color: Qt.alpha(Colours.palette.m3primary, 0.28)
            }

            // Super key: Windows-style four-pane logo.
            WinLogo {
                anchors.centerIn: parent
                visible: !keyCap.spacer && keyCap.keyId === "Super"
                size: Math.max(11, Math.min(15, keyCap.keyHeight * 0.42))
                colour: keyCap.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                opacity: keyCap.active ? 1 : 0.92
            }

            StyledText {
                anchors.centerIn: parent
                text: keyCap.label
                visible: !keyCap.spacer && keyCap.keyId !== "Super" && keyCap.label.length > 0
                color: keyCap.active ? Colours.palette.m3onPrimary : (keyCap.modifierLike ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3onSurface)
                font: Tokens.font.label.small
                opacity: keyCap.active ? 1 : 0.92
            }

            // Space bar centre mark.
            StyledRect {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(parent.width * 0.28, 36)
                height: 3
                radius: Tokens.rounding.full
                visible: keyCap.keyId === "Space" && !keyCap.active
                color: Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.35)
            }

            Behavior on color {
                CAnim {}
            }
        }

        scale: keyCap.active ? 1.04 : 1

        Behavior on scale {
            Anim {
                type: Anim.FastSpatial
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

        // Floating keyboard preview deck
        ConnectedRect {
            id: previewDeck

            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.small
            Layout.rightMargin: Tokens.padding.small
            implicitHeight: deckColumn.implicitHeight + Tokens.padding.large * 2
            topLeftRadius: Tokens.rounding.extraLarge
            topRightRadius: Tokens.rounding.extraLarge
            bottomLeftRadius: Tokens.rounding.extraLarge
            bottomRightRadius: Tokens.rounding.extraLarge
            color: Colours.tPalette.m3surfaceContainer
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.35)

            ColumnLayout {
                id: deckColumn

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                // Header: action + live chord chips
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        implicitWidth: 48
                        implicitHeight: 48
                        radius: Tokens.rounding.large
                        color: Colours.palette.m3primaryContainer

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: root.actionIcon(root.selectedAction)
                            color: Colours.palette.m3onPrimaryContainer
                            fontStyle: Tokens.font.icon.large
                            fill: 1
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.extraSmall

                        StyledText {
                            Layout.fillWidth: true
                            text: root.actionLabel(root.selectedAction)
                            font: Tokens.font.title.small
                            elide: Text.ElideRight
                        }

                        // Chord chips
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.extraSmall

                            StyledText {
                                visible: root.chordParts(root.selectedShortcut).length === 0
                                text: qsTr("No shortcut assigned")
                                color: Colours.palette.m3outline
                                font: Tokens.font.body.small
                            }

                            Repeater {
                                model: root.chordParts(root.selectedShortcut)

                                RowLayout {
                                    required property string modelData
                                    required property int index
                                    spacing: Tokens.spacing.extraSmall

                                    StyledRect {
                                        implicitWidth: String(modelData).toLowerCase() === "super"
                                            ? 34
                                            : Math.max(34, chordLabel.implicitWidth + Tokens.padding.medium)
                                        implicitHeight: 28
                                        radius: Tokens.rounding.small
                                        color: Colours.palette.m3secondaryContainer
                                        border.width: 1
                                        border.color: Qt.alpha(Colours.palette.m3onSecondaryContainer, 0.18)

                                        // mini key lip
                                        StyledRect {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            height: 2
                                            radius: parent.radius
                                            color: Qt.alpha(Colours.palette.m3onSecondaryContainer, 0.12)
                                        }

                                        WinLogo {
                                            anchors.centerIn: parent
                                            visible: String(modelData).toLowerCase() === "super"
                                            size: 12
                                            colour: Colours.palette.m3onSecondaryContainer
                                        }

                                        StyledText {
                                            id: chordLabel
                                            anchors.centerIn: parent
                                            visible: String(modelData).toLowerCase() !== "super"
                                            text: root.prettyChordPart(modelData)
                                            color: Colours.palette.m3onSecondaryContainer
                                            font: Tokens.font.label.medium
                                        }
                                    }

                                    StyledText {
                                        visible: index < root.chordParts(root.selectedShortcut).length - 1
                                        text: "+"
                                        color: Colours.palette.m3outline
                                        font: Tokens.font.label.medium
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }
                    }
                }

                // Keyboard well / chassis
                StyledRect {
                    id: keyboardWell

                    Layout.fillWidth: true
                    implicitHeight: keyboardColumn.implicitHeight + Tokens.padding.medium * 2
                    radius: Tokens.rounding.largeIncreased
                    color: Colours.tPalette.m3surfaceContainerLowest
                    border.width: 1
                    border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.4)
                    // Tall numpad keys overflow into the next row; do not clip them.
                    clip: false

                    // Inner rim to sell the "deck" depth
                    StyledRect {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: parent.radius - 1
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.alpha(Colours.palette.m3onSurface, Colours.light ? 0.04 : 0.06)
                    }

                    ColumnLayout {
                        id: keyboardColumn

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.padding.medium
                        spacing: 3
                        clip: false

                        readonly property real unitWidth: {
                            const pad = 0;
                            const available = Math.max(1, width - pad);
                            return available / root.keyboardMaxUnits;
                        }
                        // Slightly shorter caps so the denser full layout stays readable.
                        readonly property real keyHeight: Math.max(24, Math.min(32, unitWidth * 0.88))
                        readonly property real rowSpacing: spacing

                        Repeater {
                            model: root.keyboardRows

                            Item {
                                id: keyboardRow

                                required property var modelData
                                required property int index
                                readonly property var keys: modelData

                                Layout.fillWidth: true
                                Layout.preferredHeight: keyboardColumn.keyHeight
                                implicitHeight: keyboardColumn.keyHeight
                                clip: false
                                z: 1

                                Row {
                                    id: keyRow
                                    // Left-align so main cluster / arrows / numpad share vertical columns.
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    spacing: 0
                                    height: keyboardColumn.keyHeight
                                    clip: false

                                    Repeater {
                                        model: keyboardRow.keys

                                        KeyCap {
                                            required property string modelData
                                            keyId: modelData
                                            unit: root.keyUnits(modelData)
                                            unitWidth: keyboardColumn.unitWidth
                                            keyHeight: keyboardColumn.keyHeight
                                            rowSpacing: keyboardColumn.rowSpacing
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Select a shortcut below to preview it on the keyboard. Changes apply immediately.")
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                    wrapMode: Text.Wrap
                }
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
