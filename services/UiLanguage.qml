pragma Singleton

import QtQuick
import Quickshell
import Caelestia
import Caelestia.Config

Singleton {
    id: root

    readonly property string selectedLanguage: GlobalConfig.services.uiLanguage || "system"

    function apply(): void {
        const lang = selectedLanguage;
        const dir = Quickshell.shellPath("i18n");
        // C++ singleton from Villode Caelestia plugin. Guard so older system
        // packages without TranslationManager do not hard-fail the shell.
        try {
            if (typeof TranslationManager === "undefined") {
                console.warn("UiLanguage: TranslationManager not defined (wrong QML import path?)");
                return;
            }
            TranslationManager.setLanguage(lang, dir);
        } catch (e) {
            console.warn("UiLanguage: setLanguage failed:", e);
        }
    }

    Component.onCompleted: Qt.callLater(root.apply)

    Connections {
        target: GlobalConfig.services
        function onUiLanguageChanged(): void {
            root.apply();
        }
    }

    // Fallback if notify signal is missing on some plugin builds
    onSelectedLanguageChanged: root.apply()
}
