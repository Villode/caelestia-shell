pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.services
import qs.utils

Singleton {
    id: root

    property bool showPreview
    property string scheme
    property string flavour
    readonly property bool light: showPreview ? previewLight : currentLight
    property bool currentLight
    property bool previewLight
    readonly property M3Palette palette: showPreview ? preview : current
    readonly property M3TPalette tPalette: M3TPalette {}
    readonly property M3Palette current: M3Palette {}
    readonly property M3Palette preview: M3Palette {}
    readonly property Transparency transparency: Transparency {}
    readonly property alias wallLuminance: analyser.luminance
    property string preset: "blue"
    property bool autoMode

    property bool cooldownPending
    property real lastBaseTransparency

    function getLuminance(c: color): real {
        if (c.r == 0 && c.g == 0 && c.b == 0)
            return 0;
        return Math.sqrt(0.299 * (c.r ** 2) + 0.587 * (c.g ** 2) + 0.114 * (c.b ** 2));
    }

    function alterColour(c: color, a: real, layer: int): color {
        const luminance = getLuminance(c);

        const offset = (!light || layer == 1 ? 1 : -layer / 2) * (light ? 0.2 : 0.3) * (1 - transparency.base) * (1 + wallLuminance * (light ? (layer == 1 ? 3 : 1) : 2.5));
        const scale = (luminance + offset) / luminance;
        const r = Math.max(0, Math.min(1, c.r * scale));
        const g = Math.max(0, Math.min(1, c.g * scale));
        const b = Math.max(0, Math.min(1, c.b * scale));

        return Qt.rgba(r, g, b, a);
    }

    function layer(c: color, layer: var): color {
        if (!transparency.enabled)
            return c;

        return layer === 0 ? Qt.alpha(c, transparency.base) : alterColour(c, transparency.layers, layer ?? 1);
    }

    function on(c: color): color {
        if (c.hslLightness < 0.5)
            return Qt.hsla(c.hslHue, c.hslSaturation, 0.9, 1);
        return Qt.hsla(c.hslHue, c.hslSaturation, 0.1, 1);
    }

    function load(data: string, isPreview: bool): void {
        const colours = isPreview ? preview : current;
        const scheme = JSON.parse(data);

        if (!isPreview) {
            root.scheme = scheme.name;
            flavour = scheme.flavour;
            currentLight = scheme.mode === "light";
            Quickshell.execDetached(["python3", Quickshell.shellPath("assets/sync_alacritty_theme.py"), scheme.mode]);
        } else {
            previewLight = scheme.mode === "light";
        }

        for (const [name, colour] of Object.entries(scheme.colours)) {
            const propName = name.startsWith("term") ? name : `m3${name}`;
            if (colours.hasOwnProperty(propName))
                colours[propName] = `#${colour}`;
        }

        applyVillodePreset(colours, scheme.mode === "light");
    }

    function applyVillodePreset(colours: M3Palette, lightMode: bool): void {
        const palettes = {
            blue: ["#2563eb", "#dbeafe", "#172554", "#7c3aed", "#ede9fe", "#93c5fd", "#1e3a8a"],
            teal: ["#0f766e", "#ccfbf1", "#134e4a", "#2563eb", "#dbeafe", "#5eead4", "#134e4a"],
            violet: ["#6d28d9", "#ede9fe", "#3b0764", "#be185d", "#fce7f3", "#c4b5fd", "#4c1d95"],
            green: ["#15803d", "#dcfce7", "#14532d", "#0f766e", "#ccfbf1", "#86efac", "#14532d"],
            rose: ["#be123c", "#ffe4e6", "#881337", "#7c3aed", "#ede9fe", "#fda4af", "#881337"]
        };
        const selected = palettes[root.preset] ?? palettes.blue;
        const primary = lightMode ? selected[0] : selected[5];
        const onPrimary = lightMode ? "#ffffff" : selected[6];
        const container = lightMode ? selected[1] : selected[6];
        const onContainer = lightMode ? selected[2] : selected[5];

        const neutralBackground = lightMode ? "#f7f8fa" : "#0f1115";
        const neutralLow = lightMode ? "#f1f3f6" : "#171a20";
        const neutralContainer = lightMode ? "#eceff3" : "#1c2027";
        const neutralHigh = lightMode ? "#e6e9ee" : "#242932";
        const neutralHighest = lightMode ? "#dfe3e9" : "#2c323c";

        colours.m3background = Qt.tint(neutralBackground, Qt.alpha(primary, lightMode ? 0.025 : 0.04));
        colours.m3onBackground = lightMode ? "#20242b" : "#e7e9ee";
        colours.m3surface = Qt.tint(neutralBackground, Qt.alpha(primary, lightMode ? 0.03 : 0.05));
        colours.m3surfaceDim = lightMode ? "#d9dde4" : "#0f1115";
        colours.m3surfaceBright = lightMode ? "#ffffff" : "#343840";
        colours.m3surfaceContainerLowest = lightMode ? "#ffffff" : "#0a0c0f";
        colours.m3surfaceContainerLow = Qt.tint(neutralLow, Qt.alpha(primary, 0.06));
        colours.m3surfaceContainer = Qt.tint(neutralContainer, Qt.alpha(primary, 0.10));
        colours.m3surfaceContainerHigh = Qt.tint(neutralHigh, Qt.alpha(primary, 0.14));
        colours.m3surfaceContainerHighest = Qt.tint(neutralHighest, Qt.alpha(primary, 0.18));
        colours.m3onSurface = lightMode ? "#20242b" : "#e7e9ee";
        colours.m3surfaceVariant = Qt.tint(neutralHighest, Qt.alpha(primary, 0.14));
        colours.m3onSurfaceVariant = lightMode ? "#4b5563" : "#c0c6d0";
        colours.m3outline = lightMode ? "#6b7280" : "#8d96a5";
        colours.m3outlineVariant = lightMode ? "#c3c9d2" : "#444b57";

        colours.m3primary_paletteKeyColor = primary;
        colours.m3surfaceTint = primary;
        colours.m3primary = primary;
        colours.m3onPrimary = onPrimary;
        colours.m3primaryContainer = container;
        colours.m3onPrimaryContainer = onContainer;
        colours.m3inversePrimary = lightMode ? selected[5] : selected[0];
        colours.m3primaryFixed = selected[1];
        colours.m3primaryFixedDim = selected[5];
        colours.m3onPrimaryFixed = selected[2];
        colours.m3onPrimaryFixedVariant = selected[0];
        colours.m3secondary = lightMode ? "#526072" : "#c5cfdd";
        colours.m3onSecondary = lightMode ? "#ffffff" : "#2c3745";
        colours.m3secondaryContainer = Qt.tint(lightMode ? "#e1e7ef" : "#354151", Qt.alpha(primary, 0.16));
        colours.m3onSecondaryContainer = lightMode ? selected[2] : "#e8e5f0";
        colours.m3tertiary = lightMode ? selected[3] : selected[4];
        colours.m3onTertiary = lightMode ? "#ffffff" : selected[2];
        colours.m3tertiaryContainer = lightMode ? selected[4] : selected[2];
        colours.m3onTertiaryContainer = lightMode ? selected[2] : selected[4];
    }

    function setPreset(name: string, mode: string): void {
        root.preset = ["blue", "teal", "violet", "green", "rose"].includes(name) ? name : "blue";
        presetStorage.setText(root.preset);
        applyVillodePreset(current, mode === "light");
        if (showPreview)
            applyVillodePreset(preview, mode === "light");
        Quickshell.execDetached(["caelestia", "scheme", "set", "--notify", "-n", "dynamic", "-m", mode]);
    }

    function setMode(mode: string): void {
        setPreset(root.preset, mode);
    }

    function setAutoMode(enabled: bool): void {
        root.autoMode = enabled;
        autoModeStorage.setText(enabled ? "true" : "false");
        GlobalConfig.services.smartScheme = false;
        if (enabled)
            applyTimeMode(true);
    }

    function applyTimeMode(force: bool): void {
        if (!root.autoMode)
            return;
        const hour = new Date().getHours();
        const mode = hour >= 7 && hour < 19 ? "light" : "dark";
        if (force || (mode === "light") !== root.currentLight)
            setPreset(root.preset, mode);
    }

    function reloadHyprRules(): void {
        let rule, trEnabled;
        if (Hypr.usingLua) {
            rule = `eval hl.layer_rule({ match = { namespace = "caelestia-drawers" }, %1 = %2 })`;
            trEnabled = transparency.enabled;
        } else {
            rule = "keyword layerrule %1 %2, match:namespace caelestia-drawers";
            trEnabled = transparency.enabled ? 1 : 0;
        }
        Hypr.extras.batchMessage([rule.arg("blur").arg(trEnabled), rule.arg("ignore_alpha").arg(Math.max(0, transparency.base - 0.03))]);
    }

    function requestReloadHyprRules(): void {
        if (cooldownTimer.running) {
            root.cooldownPending = true;
        } else {
            root.reloadHyprRules();
            cooldownTimer.restart();
        }
    }

    Component.onCompleted: root.requestReloadHyprRules()

    Connections {
        function onConfigReloaded(): void {
            root.reloadHyprRules();
        }

        target: Hypr
    }

    FileView {
        id: schemeView

        path: `${Paths.state}/scheme.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.load(text(), false)
    }

    FileView {
        id: presetStorage

        path: `${Paths.state}/villode-preset.txt`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const saved = text().trim();
            if (["blue", "teal", "violet", "green", "rose"].includes(saved)) {
                root.preset = saved;
                if (root.autoMode)
                    root.applyTimeMode(true);
                else
                    schemeView.reload();
            }
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => setText(root.preset));
        }
    }

    FileView {
        id: autoModeStorage

        path: `${Paths.state}/villode-auto-mode.txt`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.autoMode = text().trim() === "true";
            GlobalConfig.services.smartScheme = false;
            if (root.autoMode && presetStorage.loaded)
                root.applyTimeMode(true);
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => setText("false"));
        }
    }

    ImageAnalyser {
        id: analyser

        source: Wallpapers.current
    }

    Timer {
        interval: 60000
        running: root.autoMode
        repeat: true
        triggeredOnStart: true
        onTriggered: root.applyTimeMode(false)
    }

    Timer {
        id: cooldownTimer

        interval: 30
        onTriggered: {
            if (root.cooldownPending) {
                root.cooldownPending = false;
                root.reloadHyprRules();
                restart();
            }
        }
    }

    Timer {
        id: cAnimCompleteTimer

        interval: Tokens.anim.durations.expressiveSlowEffects
        onTriggered: root.requestReloadHyprRules()
    }

    component Transparency: QtObject {
        readonly property bool enabled: Tokens.transparency.enabled
        readonly property real base: Math.max(0.25, Math.min(1, Tokens.transparency.base + (root.light ? 0.12 : 0)))
        readonly property real layers: Math.max(0, Math.min(1, Tokens.transparency.layers))

        onEnabledChanged: {
            if (enabled)
                root.requestReloadHyprRules();
            else
                cAnimCompleteTimer.start();
        }
        onBaseChanged: {
            if (root.lastBaseTransparency > base)
                root.requestReloadHyprRules();
            else
                cAnimCompleteTimer.start();
            root.lastBaseTransparency = base;
        }
    }

    component M3TPalette: QtObject {
        readonly property color m3primary_paletteKeyColor: root.layer(root.palette.m3primary_paletteKeyColor)
        readonly property color m3secondary_paletteKeyColor: root.layer(root.palette.m3secondary_paletteKeyColor)
        readonly property color m3tertiary_paletteKeyColor: root.layer(root.palette.m3tertiary_paletteKeyColor)
        readonly property color m3neutral_paletteKeyColor: root.layer(root.palette.m3neutral_paletteKeyColor)
        readonly property color m3neutral_variant_paletteKeyColor: root.layer(root.palette.m3neutral_variant_paletteKeyColor)
        readonly property color m3background: root.layer(root.palette.m3background, 0)
        readonly property color m3onBackground: root.layer(root.palette.m3onBackground)
        readonly property color m3surface: root.layer(root.palette.m3surface, 0)
        readonly property color m3surfaceDim: root.layer(root.palette.m3surfaceDim, 0)
        readonly property color m3surfaceBright: root.layer(root.palette.m3surfaceBright, 0)
        readonly property color m3surfaceContainerLowest: root.layer(root.palette.m3surfaceContainerLowest)
        readonly property color m3surfaceContainerLow: root.layer(root.palette.m3surfaceContainerLow)
        readonly property color m3surfaceContainer: root.layer(root.palette.m3surfaceContainer)
        readonly property color m3surfaceContainerHigh: root.layer(root.palette.m3surfaceContainerHigh)
        readonly property color m3surfaceContainerHighest: root.layer(root.palette.m3surfaceContainerHighest)
        readonly property color m3onSurface: root.layer(root.palette.m3onSurface)
        readonly property color m3surfaceVariant: root.layer(root.palette.m3surfaceVariant, 0)
        readonly property color m3onSurfaceVariant: root.layer(root.palette.m3onSurfaceVariant)
        readonly property color m3inverseSurface: root.layer(root.palette.m3inverseSurface, 0)
        readonly property color m3inverseOnSurface: root.layer(root.palette.m3inverseOnSurface)
        readonly property color m3outline: root.layer(root.palette.m3outline)
        readonly property color m3outlineVariant: root.layer(root.palette.m3outlineVariant)
        readonly property color m3shadow: root.layer(root.palette.m3shadow)
        readonly property color m3scrim: root.layer(root.palette.m3scrim)
        readonly property color m3surfaceTint: root.layer(root.palette.m3surfaceTint)
        readonly property color m3primary: root.layer(root.palette.m3primary)
        readonly property color m3onPrimary: root.layer(root.palette.m3onPrimary)
        readonly property color m3primaryContainer: root.layer(root.palette.m3primaryContainer)
        readonly property color m3onPrimaryContainer: root.layer(root.palette.m3onPrimaryContainer)
        readonly property color m3inversePrimary: root.layer(root.palette.m3inversePrimary)
        readonly property color m3secondary: root.layer(root.palette.m3secondary)
        readonly property color m3onSecondary: root.layer(root.palette.m3onSecondary)
        readonly property color m3secondaryContainer: root.layer(root.palette.m3secondaryContainer)
        readonly property color m3onSecondaryContainer: root.layer(root.palette.m3onSecondaryContainer)
        readonly property color m3tertiary: root.layer(root.palette.m3tertiary)
        readonly property color m3onTertiary: root.layer(root.palette.m3onTertiary)
        readonly property color m3tertiaryContainer: root.layer(root.palette.m3tertiaryContainer)
        readonly property color m3onTertiaryContainer: root.layer(root.palette.m3onTertiaryContainer)
        readonly property color m3error: root.layer(root.palette.m3error)
        readonly property color m3onError: root.layer(root.palette.m3onError)
        readonly property color m3errorContainer: root.layer(root.palette.m3errorContainer)
        readonly property color m3onErrorContainer: root.layer(root.palette.m3onErrorContainer)
        readonly property color m3success: root.layer(root.palette.m3success)
        readonly property color m3onSuccess: root.layer(root.palette.m3onSuccess)
        readonly property color m3successContainer: root.layer(root.palette.m3successContainer)
        readonly property color m3onSuccessContainer: root.layer(root.palette.m3onSuccessContainer)
        readonly property color m3primaryFixed: root.layer(root.palette.m3primaryFixed)
        readonly property color m3primaryFixedDim: root.layer(root.palette.m3primaryFixedDim)
        readonly property color m3onPrimaryFixed: root.layer(root.palette.m3onPrimaryFixed)
        readonly property color m3onPrimaryFixedVariant: root.layer(root.palette.m3onPrimaryFixedVariant)
        readonly property color m3secondaryFixed: root.layer(root.palette.m3secondaryFixed)
        readonly property color m3secondaryFixedDim: root.layer(root.palette.m3secondaryFixedDim)
        readonly property color m3onSecondaryFixed: root.layer(root.palette.m3onSecondaryFixed)
        readonly property color m3onSecondaryFixedVariant: root.layer(root.palette.m3onSecondaryFixedVariant)
        readonly property color m3tertiaryFixed: root.layer(root.palette.m3tertiaryFixed)
        readonly property color m3tertiaryFixedDim: root.layer(root.palette.m3tertiaryFixedDim)
        readonly property color m3onTertiaryFixed: root.layer(root.palette.m3onTertiaryFixed)
        readonly property color m3onTertiaryFixedVariant: root.layer(root.palette.m3onTertiaryFixedVariant)
    }

    component M3Palette: QtObject {
        property color m3primary_paletteKeyColor: "#a8627b"
        property color m3secondary_paletteKeyColor: "#8e6f78"
        property color m3tertiary_paletteKeyColor: "#986e4c"
        property color m3neutral_paletteKeyColor: "#807477"
        property color m3neutral_variant_paletteKeyColor: "#837377"
        property color m3background: "#191114"
        property color m3onBackground: "#efdfe2"
        property color m3surface: "#191114"
        property color m3surfaceDim: "#191114"
        property color m3surfaceBright: "#403739"
        property color m3surfaceContainerLowest: "#130c0e"
        property color m3surfaceContainerLow: "#22191c"
        property color m3surfaceContainer: "#261d20"
        property color m3surfaceContainerHigh: "#31282a"
        property color m3surfaceContainerHighest: "#3c3235"
        property color m3onSurface: "#efdfe2"
        property color m3surfaceVariant: "#514347"
        property color m3onSurfaceVariant: "#d5c2c6"
        property color m3inverseSurface: "#efdfe2"
        property color m3inverseOnSurface: "#372e30"
        property color m3outline: "#9e8c91"
        property color m3outlineVariant: "#514347"
        property color m3shadow: "#000000"
        property color m3scrim: "#000000"
        property color m3surfaceTint: "#ffb0ca"
        property color m3primary: "#ffb0ca"
        property color m3onPrimary: "#541d34"
        property color m3primaryContainer: "#6f334a"
        property color m3onPrimaryContainer: "#ffd9e3"
        property color m3inversePrimary: "#8b4a62"
        property color m3secondary: "#e2bdc7"
        property color m3onSecondary: "#422932"
        property color m3secondaryContainer: "#5a3f48"
        property color m3onSecondaryContainer: "#ffd9e3"
        property color m3tertiary: "#f0bc95"
        property color m3onTertiary: "#48290c"
        property color m3tertiaryContainer: "#b58763"
        property color m3onTertiaryContainer: "#000000"
        property color m3error: "#ffb4ab"
        property color m3onError: "#690005"
        property color m3errorContainer: "#93000a"
        property color m3onErrorContainer: "#ffdad6"
        property color m3success: "#B5CCBA"
        property color m3onSuccess: "#213528"
        property color m3successContainer: "#374B3E"
        property color m3onSuccessContainer: "#D1E9D6"
        property color m3primaryFixed: "#ffd9e3"
        property color m3primaryFixedDim: "#ffb0ca"
        property color m3onPrimaryFixed: "#39071f"
        property color m3onPrimaryFixedVariant: "#6f334a"
        property color m3secondaryFixed: "#ffd9e3"
        property color m3secondaryFixedDim: "#e2bdc7"
        property color m3onSecondaryFixed: "#2b151d"
        property color m3onSecondaryFixedVariant: "#5a3f48"
        property color m3tertiaryFixed: "#ffdcc3"
        property color m3tertiaryFixedDim: "#f0bc95"
        property color m3onTertiaryFixed: "#2f1500"
        property color m3onTertiaryFixedVariant: "#623f21"
        property color term0: "#353434"
        property color term1: "#ff4c8a"
        property color term2: "#ffbbb7"
        property color term3: "#ffdedf"
        property color term4: "#b3a2d5"
        property color term5: "#e98fb0"
        property color term6: "#ffba93"
        property color term7: "#eed1d2"
        property color term8: "#b39e9e"
        property color term9: "#ff80a3"
        property color term10: "#ffd3d0"
        property color term11: "#fff1f0"
        property color term12: "#dcbc93"
        property color term13: "#f9a8c2"
        property color term14: "#ffd1c0"
        property color term15: "#ffffff"
    }
}
