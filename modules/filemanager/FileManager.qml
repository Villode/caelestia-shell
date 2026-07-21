pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    // Multi-window: keep weak refs; prune destroyed entries on each open
    property var windows: []

    Component {
        id: managerComp
        ManagerWindow {}
    }

    function prune(): void {
        const next = [];
        for (let i = 0; i < windows.length; i++) {
            const w = windows[i];
            if (w)
                next.push(w);
        }
        windows = next;
    }

    function attachWindow(w: var): void {
        if (!w)
            return;
        w.requestClose.connect(() => {
            // Remove this window from the list
            const next = [];
            for (let i = 0; i < windows.length; i++) {
                if (windows[i] !== w && windows[i])
                    next.push(windows[i]);
            }
            windows = next;
            try {
                w.destroy();
            } catch (e) {}
        });
        const next = windows.slice();
        next.push(w);
        windows = next;
    }

    function createWindow(): var {
        prune();
        const w = managerComp.createObject(root);
        if (!w)
            return null;
        attachWindow(w);
        return w;
    }

    function lastWindow(): var {
        prune();
        if (!windows.length)
            return null;
        return windows[windows.length - 1];
    }

    function raiseWindow(w: var): void {
        if (!w)
            return;
        w.visible = true;
        // Nudge focus: re-set visible / title pulse for Hyprland
        try {
            if (typeof w.requestActivate === "function")
                w.requestActivate();
        } catch (e) {}
    }

    // Reuse last window, or create first
    function openHome(): void {
        let w = lastWindow();
        if (!w)
            w = createWindow();
        if (!w)
            return;
        w.openPath("");
        raiseWindow(w);
    }

    function openPath(path: string): void {
        let w = lastWindow();
        if (!w)
            w = createWindow();
        if (!w)
            return;
        w.openPath(path || "");
        raiseWindow(w);
    }

    // Always new FloatingWindow
    function openNew(path: string): void {
        const w = createWindow();
        if (!w)
            return;
        w.openPath(path || "");
        raiseWindow(w);
    }

    function closeAll(): void {
        prune();
        const copy = windows.slice();
        windows = [];
        for (let i = 0; i < copy.length; i++) {
            const w = copy[i];
            if (!w)
                continue;
            try {
                w.visible = false;
                w.destroy();
            } catch (e) {}
        }
    }

    function count(): int {
        prune();
        return windows.length;
    }

    IpcHandler {
        target: "filemanager"

        function open(): void {
            root.openHome();
        }

        function openPath(path: string): void {
            root.openPath(path);
        }

        // New window (optional path)
        function openNew(path: string): void {
            root.openNew(path || "");
        }

        function openNewHome(): void {
            root.openNew("");
        }

        function closeAll(): void {
            root.closeAll();
        }

        function count(): string {
            return String(root.count());
        }
    }
}
