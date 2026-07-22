pragma Singleton

import QtQuick
import Quickshell
import Caelestia.Config

Singleton {
    id: root

    readonly property var defaults: ({
        terminal: "Super+Return",
        fileManager: "Super+E",
        launcher: "Super+D",
        desktop: "Super+Shift+D",
        screenshot: "Print",
        nexus: "Super+Comma",
        multitasking: "Super+Tab",
        dashboard: "Super+A",
        sidebar: "Super+S",
        session: "Super+Escape",
        closeWindow: "Super+Q",
        fullscreen: "Super+F",
        toggleFloating: "Super+V",
        clipboard: "Super+Shift+V"
    })

    readonly property list<string> actionIds: [
        "terminal", "fileManager", "launcher", "desktop", "screenshot", "nexus", "multitasking",
        "dashboard", "sidebar", "session", "closeWindow", "fullscreen", "toggleFloating", "clipboard"
    ]

    property var previouslyApplied: ({})
    property int applyGeneration: 0

    function shortcut(action: string): string {
        const config = GlobalConfig.general.shortcuts;
        if (!config)
            return defaults[action] || "";
        switch (action) {
        case "terminal": return config.terminal || defaults.terminal;
        case "fileManager": return config.fileManager || defaults.fileManager;
        case "launcher": return config.launcher || defaults.launcher;
        case "desktop": return config.desktop || defaults.desktop;
        case "screenshot": return config.screenshot || defaults.screenshot;
        case "nexus": return config.nexus || defaults.nexus;
        case "multitasking": return config.multitasking || defaults.multitasking;
        case "dashboard": return config.dashboard || defaults.dashboard;
        case "sidebar": return config.sidebar || defaults.sidebar;
        case "session": return config.session || defaults.session;
        case "closeWindow": return config.closeWindow || defaults.closeWindow;
        case "fullscreen": return config.fullscreen || defaults.fullscreen;
        case "toggleFloating": return config.toggleFloating || defaults.toggleFloating;
        case "clipboard": {
            // Property may be missing on old plugins — fall back safely.
            try {
                const v = config.clipboard;
                if (v !== undefined && v !== null && String(v).length)
                    return String(v);
            } catch (e) {}
            return defaults.clipboard;
        }
        }
        return "";
    }

    function setShortcut(action: string, shortcut: string): void {
        const config = GlobalConfig.general.shortcuts;
        if (!config)
            return;
        switch (action) {
        case "terminal": config.terminal = shortcut; break;
        case "fileManager": config.fileManager = shortcut; break;
        case "launcher": config.launcher = shortcut; break;
        case "desktop": config.desktop = shortcut; break;
        case "screenshot": config.screenshot = shortcut; break;
        case "nexus": config.nexus = shortcut; break;
        case "multitasking": config.multitasking = shortcut; break;
        case "dashboard": config.dashboard = shortcut; break;
        case "sidebar": config.sidebar = shortcut; break;
        case "session": config.session = shortcut; break;
        case "closeWindow": config.closeWindow = shortcut; break;
        case "fullscreen": config.fullscreen = shortcut; break;
        case "toggleFloating": config.toggleFloating = shortcut; break;
        case "clipboard":
            try {
                config.clipboard = shortcut;
            } catch (e) {
                console.warn("ShortcutBindings: clipboard config property missing — rebuild caelestia-config plugin");
            }
            break;
        }
        // Apply immediately; property change also triggers, but do not rely solely on it.
        Qt.callLater(root.apply);
    }

    function parsed(shortcut: string): var {
        const parts = shortcut.split("+").map(part => part.trim()).filter(part => part.length > 0);
        if (parts.length === 0)
            return null;
        let key = parts.pop();
        const keyAliases = {
            print: "Print",
            printscreen: "Print",
            prtsc: "Print",
            prtscn: "Print",
            sysrq: "Print",
            return: "Return",
            enter: "Return",
            escape: "Escape",
            esc: "Escape",
            space: "Space",
            tab: "Tab",
            comma: "comma",
            period: "period",
            slash: "slash",
            minus: "minus",
            equal: "equal"
        };
        const alias = keyAliases[key.toLowerCase()];
        if (alias)
            key = alias;
        else if (key.length === 1)
            key = key.toUpperCase();
        const modifiers = parts.map(part => {
            switch (part.toLowerCase()) {
            case "super":
            case "meta":
            case "win":
                return "SUPER";
            case "ctrl":
            case "control":
                return "CTRL";
            case "alt":
                return "ALT";
            case "shift":
                return "SHIFT";
            default:
                return part.toUpperCase();
            }
        }).filter(part => part.length > 0);
        return {
            modifiers: modifiers.join(" "),
            key: key
        };
    }

    function bindSpec(binding: var): string {
        if (!binding)
            return "";
        if (!binding.modifiers || binding.modifiers.length === 0)
            return `,${binding.key}`;
        return `${binding.modifiers}, ${binding.key}`;
    }

    function dispatch(action: string): string {
        const apps = GlobalConfig.general.apps;
        switch (action) {
        case "terminal": return `exec, ${(apps?.terminal ?? ["foot"]).join(" ")}`;
        case "fileManager": return `exec, ${(apps?.explorer ?? ["thunar"]).join(" ")}`;
        case "launcher": return "exec, villode-launcher";
        case "desktop": return "exec, villode-desktop --toggle";
        case "screenshot": return "global, caelestia:screenshot";
        case "nexus": return "global, caelestia:nexus";
        case "multitasking": return "global, caelestia:multitasking";
        case "dashboard": return "global, caelestia:dashboard";
        case "sidebar": return "global, caelestia:sidebar";
        case "session": return "global, caelestia:session";
        case "closeWindow": return "killactive";
        case "fullscreen": return "fullscreen";
        case "toggleFloating": return "togglefloating";
        case "clipboard": return "global, caelestia:clipboard";
        }
        return "";
    }

    function apply(): void {
        const gen = ++applyGeneration;
        const commands = [];
        const remove = {};

        // Collect every chord we may have ever bound so reloads / rebinds stay clean.
        for (const action of actionIds) {
            for (const chord of [defaults[action], previouslyApplied[action], shortcut(action)]) {
                const binding = parsed(chord || "");
                if (!binding)
                    continue;
                remove[bindSpec(binding)] = true;
                if (!binding.modifiers || binding.modifiers.length === 0)
                    remove[`, ${binding.key}`] = true;
            }
        }

        for (const binding of Object.keys(remove))
            commands.push(`keyword unbind ${binding}`);
        // Locked screenshot binds (bindl) need a separate clear.
        for (const chord of [defaults.screenshot, previouslyApplied.screenshot, shortcut("screenshot")]) {
            const binding = parsed(chord || "");
            if (binding)
                commands.push(`keyword unbindl ${bindSpec(binding)}`);
        }

        for (const action of actionIds) {
            const chord = shortcut(action);
            const binding = parsed(chord);
            const actionDispatch = dispatch(action);
            if (binding && actionDispatch) {
                const spec = bindSpec(binding);
                // Hypr expects "dispatcher, arg" — actionDispatch already includes comma when needed.
                commands.push(`keyword bind ${spec}, ${actionDispatch}`);
                if (action === "screenshot")
                    commands.push(`keyword bindl ${spec}, ${actionDispatch}`);
            }
            previouslyApplied[action] = chord;
        }

        if (commands.length === 0)
            return;

        // Guard against overlapping applies from rapid setting changes.
        if (gen !== applyGeneration)
            return;

        if (Hypr?.extras)
            Hypr.extras.batchMessage(commands);
        else
            console.warn("ShortcutBindings: Hypr.extras unavailable, binds not applied");
    }

    function scheduleApply(delayMs = 0): void {
        applyTimer.interval = Math.max(0, delayMs);
        applyTimer.restart();
    }

    function duplicateAction(action: string, chord: string): string {
        if (!chord)
            return "";
        const normalized = chord.toLowerCase();
        for (const candidate of actionIds) {
            if (candidate !== action && shortcut(candidate).toLowerCase() === normalized)
                return candidate;
        }
        return "";
    }

    Timer {
        id: applyTimer
        interval: 0
        repeat: false
        onTriggered: root.apply()
    }

    // Re-apply after Hyprland reloads its config (session conf would otherwise restore Super+V etc.).
    Connections {
        target: Hypr
        function onConfigReloaded(): void {
            root.scheduleApply(80);
        }
    }

    Connections {
        target: GlobalConfig.general.shortcuts
        function onTerminalChanged(): void { root.scheduleApply(); }
        function onFileManagerChanged(): void { root.scheduleApply(); }
        function onLauncherChanged(): void { root.scheduleApply(); }
        function onDesktopChanged(): void { root.scheduleApply(); }
        function onScreenshotChanged(): void { root.scheduleApply(); }
        function onNexusChanged(): void { root.scheduleApply(); }
        function onMultitaskingChanged(): void { root.scheduleApply(); }
        function onDashboardChanged(): void { root.scheduleApply(); }
        function onSidebarChanged(): void { root.scheduleApply(); }
        function onSessionChanged(): void { root.scheduleApply(); }
        function onCloseWindowChanged(): void { root.scheduleApply(); }
        function onFullscreenChanged(): void { root.scheduleApply(); }
        function onToggleFloatingChanged(): void { root.scheduleApply(); }
        function onClipboardChanged(): void { root.scheduleApply(); }
    }

    Component.onCompleted: scheduleApply(120)
}
