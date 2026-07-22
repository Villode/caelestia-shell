//@ pragma Env QS_CRASHREPORT_URL=https://github.com/caelestia-dots/shell/issues/new?template=crash.yml

import "modules"
import "modules/drawers"
import "modules/background"
import "modules/areapicker"
import "modules/filemanager"
import "modules/lock"
import "services"
import QtQuick
import Quickshell

ShellRoot {
    settings.watchFiles: false

    Component.onCompleted: {
        UiLanguage.apply();
        // Apply immediately and again shortly after Hypr socket is ready / session binds load.
        ShortcutBindings.apply();
        Qt.callLater(() => ShortcutBindings.scheduleApply(250));
    }

    GSFLoader {}

    Background {}
    Drawers {}
    AreaPicker {}
    FileManager {}
    PortalPicker {}
    Lock {
        id: lock
    }

    ConfigToasts {}
    Shortcuts {}
    BatteryMonitor {}
    IdleMonitors {
        lock: lock
    }
}
