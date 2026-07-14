pragma Singleton

import QtQuick
import Quickshell
import Caelestia
import Caelestia.Config

Singleton {
    id: root

    readonly property string selectedLanguage: GlobalConfig.services.uiLanguage || "system"

    function apply(): void {
        TranslationManager.setLanguage(selectedLanguage, Quickshell.shellPath("i18n"));
    }

    Connections {
        target: GlobalConfig.services
        function onUiLanguageChanged(): void {
            root.apply();
        }
    }
}
