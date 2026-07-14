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
        toggleFloating: "Super+V"
    })

    readonly property list<string> actionIds: [
        "terminal", "fileManager", "launcher", "desktop", "screenshot", "nexus", "multitasking",
        "dashboard", "sidebar", "session", "closeWindow", "fullscreen", "toggleFloating"
    ]

    property var previouslyApplied: ({})

    function shortcut(action: string): string {
        const config = GlobalConfig.general.shortcuts;
        switch (action) {
        case "terminal": return config.terminal;
        case "fileManager": return config.fileManager;
        case "launcher": return config.launcher;
        case "desktop": return config.desktop;
        case "screenshot": return config.screenshot;
        case "nexus": return config.nexus;
        case "multitasking": return config.multitasking;
        case "dashboard": return config.dashboard;
        case "sidebar": return config.sidebar;
        case "session": return config.session;
        case "closeWindow": return config.closeWindow;
        case "fullscreen": return config.fullscreen;
        case "toggleFloating": return config.toggleFloating;
        }
        return "";
    }

    function setShortcut(action: string, shortcut: string): void {
        const config = GlobalConfig.general.shortcuts;
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
        }
    }

    function parsed(shortcut: string): var {
        const parts = shortcut.split("+").map(part => part.trim()).filter(part => part.length > 0);
        if (parts.length === 0)
            return null;
        const key = parts.pop();
        const modifiers = parts.map(part => {
            switch (part.toLowerCase()) {
            case "super": return "SUPER";
            case "ctrl": return "CTRL";
            case "alt": return "ALT";
            case "shift": return "SHIFT";
            default: return part.toUpperCase();
            }
        });
        return { modifiers: modifiers.join(" "), key: key };
    }

    function dispatch(action: string): string {
        const apps = GlobalConfig.general.apps;
        switch (action) {
        case "terminal": return `exec, ${apps.terminal.join(" ")}`;
        case "fileManager": return `exec, ${apps.explorer.join(" ")}`;
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
        }
        return "";
    }

    function apply(): void {
        const commands = [];
        const remove = {};
        for (const action of actionIds) {
            for (const chord of [defaults[action], previouslyApplied[action], shortcut(action)]) {
                const binding = parsed(chord || "");
                if (binding)
                    remove[`${binding.modifiers}, ${binding.key}`] = true;
            }
        }
        for (const binding of Object.keys(remove))
            commands.push(`keyword unbind ${binding}`);
        for (const action of actionIds) {
            const chord = shortcut(action);
            const binding = parsed(chord);
            const actionDispatch = dispatch(action);
            if (binding && actionDispatch)
                commands.push(`keyword bind ${binding.modifiers}, ${binding.key}, ${actionDispatch}`);
            previouslyApplied[action] = chord;
        }
        if (commands.length > 0)
            Hypr.extras.batchMessage(commands);
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

    Connections {
        target: GlobalConfig.general.shortcuts
        function onTerminalChanged(): void { root.apply(); }
        function onFileManagerChanged(): void { root.apply(); }
        function onLauncherChanged(): void { root.apply(); }
        function onDesktopChanged(): void { root.apply(); }
        function onScreenshotChanged(): void { root.apply(); }
        function onNexusChanged(): void { root.apply(); }
        function onMultitaskingChanged(): void { root.apply(); }
        function onDashboardChanged(): void { root.apply(); }
        function onSidebarChanged(): void { root.apply(); }
        function onSessionChanged(): void { root.apply(); }
        function onCloseWindowChanged(): void { root.apply(); }
        function onFullscreenChanged(): void { root.apply(); }
        function onToggleFloatingChanged(): void { root.apply(); }
    }
}
