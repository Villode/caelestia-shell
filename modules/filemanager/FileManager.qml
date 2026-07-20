pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property var win: null

    function ensureWindow(): var {
        if (win)
            return win;
        win = managerComp.createObject(root);
        if (win) {
            win.requestClose.connect(() => {
                if (win) {
                    win.destroy();
                    win = null;
                }
            });
        }
        return win;
    }

    function openHome(): void {
        const w = ensureWindow();
        if (!w)
            return;
        w.openPath("");
        w.visible = true;
    }

    function openPath(path: string): void {
        const w = ensureWindow();
        if (!w)
            return;
        w.openPath(path);
        w.visible = true;
    }

    Component {
        id: managerComp
        ManagerWindow {}
    }

    IpcHandler {
        target: "filemanager"

        function open(): void {
            root.openHome();
        }

        function openPath(path: string): void {
            root.openPath(path);
        }
    }
}
