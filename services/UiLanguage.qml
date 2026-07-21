pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config

Singleton {
    id: root

    // Villode defaults to Simplified Chinese; "system" still honours the locale.
    readonly property string selectedLanguage: GlobalConfig.services.uiLanguage || "zh_CN"
    readonly property string catalogPath: {
        const dir = Quickshell.shellPath("i18n");
        const lang = resolvedLanguage();
        return `${dir}/qml_${lang}.qm`;
    }

    property bool managerAvailable: false
    property bool catalogPresent: false
    property bool translationLoaded: false
    property string appliedLanguage: ""
    property string lastError: ""
    property string statusLine: qsTr("Checking translation…")

    function resolvedLanguage(): string {
        const lang = selectedLanguage || "zh_CN";
        if (!lang || lang === "system") {
            const sys = Qt.locale().name || "zh_CN";
            if (sys === "C" || sys.indexOf("C.") === 0 || sys === "POSIX")
                return "zh_CN";
            return sys.replace(/-/g, "_");
        }
        return lang.replace(/-/g, "_");
    }

    function refreshStatus(): void {
        const lang = appliedLanguage || resolvedLanguage();
        if (!managerAvailable) {
            statusLine = qsTr("Translation plugin missing — reinstall Shell with native modules");
            return;
        }
        if (!catalogPresent) {
            statusLine = qsTr("Catalog missing for %1 — run caelestia-zh-apply").arg(lang);
            return;
        }
        if (translationLoaded)
            statusLine = qsTr("Loaded · %1").arg(lang);
        else
            statusLine = qsTr("Plugin OK, catalog not loaded · %1").arg(lang);
    }

    function apply(): void {
        lastError = "";
        const lang = selectedLanguage || "zh_CN";
        const dir = Quickshell.shellPath("i18n");
        const resolved = resolvedLanguage();
        catalogPresent = false;

        try {
            if (typeof TranslationManager === "undefined") {
                managerAvailable = false;
                translationLoaded = false;
                appliedLanguage = "";
                lastError = "TranslationManager undefined";
                console.warn("UiLanguage: TranslationManager not defined (wrong QML import path?)");
                refreshStatus();
                return;
            }
            managerAvailable = true;
            const ok = TranslationManager.setLanguage(lang, dir);
            appliedLanguage = TranslationManager.language || resolved;
            translationLoaded = !!TranslationManager.translationLoaded;
            catalogPresent = translationLoaded || ok;
            if (!ok && !translationLoaded)
                lastError = "catalog load failed";
        } catch (e) {
            managerAvailable = false;
            translationLoaded = false;
            lastError = String(e);
            console.warn("UiLanguage: setLanguage failed:", e);
        }
        refreshStatus();
    }

    function statusJson(): string {
        return JSON.stringify({
            selected: selectedLanguage,
            resolved: resolvedLanguage(),
            applied: appliedLanguage,
            managerAvailable: managerAvailable,
            catalogPresent: catalogPresent,
            translationLoaded: translationLoaded,
            catalogPath: catalogPath,
            status: statusLine,
            error: lastError
        });
    }

    Component.onCompleted: Qt.callLater(root.apply)

    Connections {
        target: GlobalConfig.services
        function onUiLanguageChanged(): void {
            root.apply();
        }
    }

    onSelectedLanguageChanged: root.apply()

    IpcHandler {
        target: "uilanguage"

        function apply(): void {
            root.apply();
        }

        function status(): string {
            return root.statusJson();
        }

        function language(): string {
            return root.appliedLanguage || root.resolvedLanguage();
        }

        function loaded(): bool {
            return root.translationLoaded;
        }
    }
}
