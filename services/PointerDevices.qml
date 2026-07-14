pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root

    // —— Touchpad ——
    property list<var> touchpads: []
    property list<var> mice: []
    property bool touchpadEnabled: true
    property bool busy: false
    property string statusMessage: ""
    property string pendingEnabled: ""

    // —— Mouse ——
    // scrollFactor: Hyprland input:scroll_factor (typical 0.25–3)
    property real scrollFactor: 1.0
    // sensitivity: Hyprland input:sensitivity (−1 … 1)
    property real sensitivity: 0.0
    property bool naturalScroll: false
    // Hold middle button + move pointer to scroll (input:scroll_button = 274)
    property bool middleScroll: true
    // Click middle to toggle scroll mode instead of hold
    property bool middleScrollLock: false
    // accel_profile flat vs adaptive
    property bool flatAccel: false

    readonly property int btnMiddle: 274

    // Flexible mappings: [{ key: "mouse:275"|"XF86Back"|..., action: "browser_back" }]
    property list<var> buttonMaps: []

    // Capture flow: user presses a physical button while capturing === true
    property bool capturing: false
    property string lastCapturedKey: ""
    property string captureStatus: ""
    property string pendingCaptureAction: "browser_back"
    // Bumps every start so late/async events from a previous listen process cannot finish the new session.
    property int captureSession: 0
    property int activeCaptureSession: 0
    // Ignore stale capture.key / dying process stdout for a short window after start.
    property double captureReadyAt: 0

    readonly property string captureFilePath: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/villode-mouse-capture.key`
    readonly property string capturePausePath: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/villode-side-capture.pause`
    readonly property string captureHitScript: `${Quickshell.env("HOME")}/.local/bin/villode-mouse-capture-hit`

    readonly property var sideActions: [
        {
            id: "default",
            label: qsTr("System default (pass through to applications)")
        },
        {
            id: "browser_back",
            label: qsTr("Browser back")
        },
        {
            id: "browser_forward",
            label: qsTr("Browser forward")
        },
        {
            id: "workspace_prev",
            label: qsTr("Previous workspace")
        },
        {
            id: "workspace_next",
            label: qsTr("Next workspace")
        },
        {
            id: "movefocus_l",
            label: qsTr("Focus left")
        },
        {
            id: "movefocus_r",
            label: qsTr("Focus right")
        },
        {
            id: "volume_up",
            label: qsTr("Volume +")
        },
        {
            id: "volume_down",
            label: qsTr("Volume −")
        },
        {
            id: "media_play",
            label: qsTr("Play / pause")
        },
        {
            id: "killactive",
            label: qsTr("Close current window")
        },
        {
            id: "fullscreen",
            label: qsTr("Full screen")
        },
        {
            id: "togglefloating",
            label: qsTr("Floating window")
        },
        {
            id: "notify_test",
            label: qsTr("Test notification")
        }
    ]

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || `${Quickshell.env("HOME")}/.config`
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`
    readonly property string hyprTouchpadPath: `${configHome}/hypr/conf.d/villode-touchpad.conf`
    readonly property string villodeTouchpadPath: `${configHome}/villode-hyprland/touchpad.conf`
    readonly property string hyprMousePath: `${configHome}/hypr/conf.d/villode-mouse.conf`
    readonly property string villodeMousePath: `${configHome}/villode-hyprland/mouse.conf`
    readonly property string touchpadStatePath: `${stateHome}/caelestia/touchpad-enabled`
    readonly property string mouseStatePath: `${stateHome}/caelestia/mouse-settings.json`

    property string pendingWriteContent: ""
    property string pendingWriteEnabled: "1"
    property string pendingMouseConf: ""
    property string pendingMouseJson: ""
    property bool writingMouse: false

    function refresh(): void {
        if (!listProc.running)
            listProc.running = true;
        if (!optsProc.running)
            optsProc.running = true;
    }

    function isTouchpadName(name: string): bool {
        const n = String(name || "").toLowerCase();
        return n.includes("touchpad") || n.includes("trackpad") || n.includes("synaptics") || (n.includes("elan") && n.includes("touchpad"));
    }

    function setTouchpadEnabled(enabled: bool): void {
        if (busy)
            return;
        if (!touchpads.length) {
            statusMessage = qsTr("No touchpad detected.");
            return;
        }

        busy = true;
        statusMessage = "";
        pendingEnabled = enabled ? "1" : "0";
        touchpadEnabled = enabled;

        const cmds = [];
        for (const pad of touchpads) {
            cmds.push(`hyprctl keyword "device[${pad.name}]:enabled" ${enabled ? 1 : 0}`);
        }
        applyProc.command = ["bash", "-lc", cmds.join(" && ")];
        applyProc.running = true;
    }

    function toggleTouchpad(): void {
        setTouchpadEnabled(!touchpadEnabled);
    }

    function clampScrollFactor(v: real): real {
        return Math.min(3.0, Math.max(0.25, Math.round(v * 100) / 100));
    }

    function clampSensitivity(v: real): real {
        return Math.min(1.0, Math.max(-1.0, Math.round(v * 100) / 100));
    }

    function setScrollFactor(v: real): void {
        scrollFactor = clampScrollFactor(v);
        applyMouseLive();
        scheduleMousePersist();
    }

    function setSensitivity(v: real): void {
        sensitivity = clampSensitivity(v);
        applyMouseLive();
        scheduleMousePersist();
    }

    function setNaturalScroll(enabled: bool): void {
        naturalScroll = enabled;
        applyMouseLive();
        scheduleMousePersist();
    }

    function setMiddleScroll(enabled: bool): void {
        middleScroll = enabled;
        applyMouseLive();
        scheduleMousePersist();
    }

    function setMiddleScrollLock(enabled: bool): void {
        middleScrollLock = enabled;
        applyMouseLive();
        scheduleMousePersist();
    }

    function setFlatAccel(enabled: bool): void {
        flatAccel = enabled;
        applyMouseLive();
        scheduleMousePersist();
    }

    function actionLabel(actionId: string): string {
        for (const a of sideActions) {
            if (a.id === actionId)
                return a.label;
        }
        return actionId || qsTr("System default");
    }

    function normalizeBindKey(key: string): string {
        if (!key)
            return "";
        return key;
    }

    function keyDisplayName(key: string): string {
        const k = normalizeBindKey(key);
        if (!k)
            return "—";
        if (k.startsWith("mouse:")) {
            const n = parseInt(k.slice(6), 10);
            const names = {
                275: qsTr("Side button"),
                276: qsTr("Forward side button"),
                277: qsTr("Extra button 3"),
                278: qsTr("Extra button 4"),
                279: qsTr("Extra button 5")
            };
            return names[n] ? `${names[n]} · ${k}` : qsTr("Mouse button · %1").arg(k);
        }
        if (k.startsWith("XF86"))
            return qsTr("Media/function key · %1").arg(k);
        return k;
    }

    // Hyprland dispatcher/args after "bind = , KEY, "
    // Standard mice only (mouse:275+ / XF86*). Xiaomi dongle side keys not supported.
    function actionDispatch(actionId: string): string {
        switch (actionId) {
        case "browser_back":
            return "sendshortcut, ALT, Left, activewindow";
        case "browser_forward":
            return "sendshortcut, ALT, Right, activewindow";
        case "workspace_prev":
            return "workspace, e-1";
        case "workspace_next":
            return "workspace, e+1";
        case "movefocus_l":
            return "movefocus, l";
        case "movefocus_r":
            return "movefocus, r";
        case "volume_up":
            return "exec, wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+";
        case "volume_down":
            return "exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
        case "media_play":
            return "exec, playerctl play-pause";
        case "killactive":
            return "killactive,";
        case "fullscreen":
            return "fullscreen,";
        case "togglefloating":
            return "togglefloating,";
        case "notify_test":
            return `exec, hyprctl notify 1 2000 0 "${qsTr("Side button test succeeded")}"`;
        default:
            return "";
        }
    }

    function managedBindKeys(): list<string> {
        const keys = [];
        const seen = {};
        for (const m of buttonMaps) {
            if (m && m.key && !seen[m.key]) {
                seen[m.key] = true;
                keys.push(m.key);
            }
        }
        // Always clear common candidates so stale binds don't linger.
        for (const k of captureCandidateKeys()) {
            if (!seen[k]) {
                seen[k] = true;
                keys.push(k);
            }
        }
        return keys;
    }

    function captureCandidateKeys(): list<string> {
        // Standard side / extra mouse buttons + common media browser keys.
        // Middle (274) excluded: used for hold-to-scroll.
        const keys = [];
        for (let i = 275; i <= 287; i++)
            keys.push(`mouse:${i}`);
        for (const k of ["XF86Back", "XF86Forward", "XF86Home", "XF86WWW", "XF86Mail", "XF86Calculator", "XF86Config"])
            keys.push(k);
        return keys;
    }

    function ensureCaptureScript(): void {
        const script = `#!/bin/sh
# Written by Caelestia mouse settings — do not edit by hand
key="$1"
file="\${XDG_RUNTIME_DIR:-/tmp}/villode-mouse-capture.key"
printf '%s\\n' "$key" > "$file"
hyprctl notify 1 2000 0 "${qsTr("Recorded button")}: $key" >/dev/null 2>&1 || true
`;
        captureScriptFile.path = captureHitScript;
        captureScriptFile.setText(script);
        // chmod +x
        chmodCaptureProc.running = true;
    }

    property bool captureInstallPending: false
    readonly property string listenScript: `${Quickshell.env("HOME")}/.local/bin/villode-mouse-listen`
    readonly property string userName: Quickshell.env("USER") || "villode"

    function captureAcceptsResults(): bool {
        // Only accept keys after arm window — avoids finishing from:
        // 1) leftover capture.key from last success
        // 2) async onExited/stdout of a process we just stopped
        // 3) FileView cache of previous content
        return capturing && activeCaptureSession === captureSession && Date.now() >= captureReadyAt;
    }

    function isCaptureKeyLine(line: string): bool {
        if (!line)
            return false;
        const l = line.trim();
        // Standard mice only — no Xiaomi code:96 / KP_Enter path.
        return l.startsWith("mouse:") || l.startsWith("XF86");
    }

    function startButtonCapture(defaultAction: string): void {
        if (capturing)
            return;
        // New session id first so any dying process callbacks are ignored.
        captureSession += 1;
        activeCaptureSession = captureSession;
        captureReadyAt = Date.now() + 550;

        // Stop any leftover listen process from a previous attempt.
        if (inputListenProc.running)
            inputListenProc.running = false;

        pendingCaptureAction = defaultAction || "notify_test";
        lastCapturedKey = "";
        captureStatus = qsTr("Press a mouse side button...");
        capturing = true;
        // Userspace listen is primary; skip installing Hypr temp binds that also
        // write capture.key (they raced with the poll and "finished" instantly).
        captureInstallPending = false;
        // Suspend existing maps so recording is not interrupted by workspace
        // switch / browser back / etc.
        suspendMapsForCapture();
        // Wipe stale key file before any poll can see it.
        clearCaptureFileProc.command = ["bash", "-lc", `rm -f '${captureFilePath}' '${captureFilePath}.tmp' 2>/dev/null; :`];
        clearCaptureFileProc.running = true;
        // Defer listener start so previous Process fully tears down (one click).
        listenStartTimer.restart();
        // Do not poll during the arm window — only after capture is ready.
        capturePollTimer.stop();
        pollArmTimer.restart();
        captureTimeoutTimer.restart();
        statusMessage = qsTr("Recording: existing mappings are paused. Press a side button.");
    }

    function suspendMapsForCapture(): void {
        // Pause userspace side-key daemon via flag file.
        pauseFlagProc.command = ["bash", "-lc", `mkdir -p \"$(dirname '${capturePausePath}')\" && : > '${capturePausePath}'`];
        pauseFlagProc.running = true;
        // Unbind Hyprland maps without re-applying (capturing=true blocks apply).
        const cmds = [];
        for (const k of managedBindKeys())
            cmds.push(`hyprctl keyword unbind ", ${k}" >/dev/null 2>&1 || true`);
        for (const c of [14, 22, 28, 96, 158, 159, 171, 172])
            cmds.push(`hyprctl keyword unbind ", code:${c}" >/dev/null 2>&1 || true`);
        if (cmds.length) {
            sideBindProc.command = ["bash", "-lc", cmds.join(" ; ")];
            sideBindProc.running = true;
        }
    }

    function resumeMapsAfterCapture(): void {
        // Clear pause flag (legacy); maps re-applied via applySideBindsLive.
        resumeFlagProc.command = ["bash", "-lc", `rm -f '${capturePausePath}'`];
        resumeFlagProc.running = true;
    }

    function startInputListener(): void {
        // User-session only — never pkexec.
        // After usermod -aG input, current GUI session may lack the group until
        // re-login; `sg input` applies it immediately for the listener process.
        // Stream key line to Process stdout (tee) AND log file so UI can finish
        // even if FileView poll misses the capture file.
        inputListenProc.command = ["bash", "-lc", `
set +e
OUT="${captureFilePath}"
LISTEN="${listenScript}"
LOG=/tmp/villode-mouse-listen.log
: > "$LOG"
rm -f "$OUT"
chmod +x "$LISTEN" 2>/dev/null
# Keep Process stdout so StdioCollector can finish capture; also log for debug.
if command -v sg >/dev/null 2>&1 && getent group input | grep -q "\$(id -un)"; then
  sg input -c "\"$LISTEN\" --out \"$OUT\" --timeout 14 --debug" 2>>"$LOG" | tee -a "$LOG"
else
  "$LISTEN" --out "$OUT" --timeout 14 --debug 2>>"$LOG" | tee -a "$LOG"
fi
exit \${PIPESTATUS[0]}
`];
        inputListenProc.running = true;
    }

    function tryFinishFromCaptureFile(): void {
        if (!captureAcceptsResults() || captureReadProc.running)
            return;
        captureReadProc.command = ["bash", "-lc", `test -s '${captureFilePath}' && tr -d '\\r' < '${captureFilePath}' | head -1 | tr -d '\\n'`];
        captureReadProc.running = true;
    }

    function clearAllButtonMaps(): void {
        if (capturing)
            cancelButtonCapture();
        buttonMaps = [];
        lastCapturedKey = "";
        captureStatus = "";
        // Hard wipe: unbind every key we may have ever installed (including
        // broken empty-key / keycode-only binds from earlier bugs).
        purgeAllSideBinds();
        scheduleMousePersist();
        statusMessage = qsTr("Cleared all side-button and accidental keyboard mappings.");
    }

    function purgeAllSideBinds(): void {
        const cmds = [];
        // Named keys
        for (const k of managedBindKeys())
            cmds.push(`hyprctl keyword unbind ", ${k}" >/dev/null 2>&1 || true`);
        // Extra strays from older builds
        for (const k of ["test-manual", "test-F9", "F9", "Back", "Forward"])
            cmds.push(`hyprctl keyword unbind ", ${k}" >/dev/null 2>&1 || true`);
        // Keycode-only binds (empty key name) that hijacked the keyboard
        for (let c = 1; c <= 255; c++)
            cmds.push(`hyprctl keyword unbind ", code:${c}" >/dev/null 2>&1 || true`);
        for (let c = 256; c <= 300; c++)
            cmds.push(`hyprctl keyword unbind ", code:${c}" >/dev/null 2>&1 || true`);
        cmds.push(`hyprctl keyword unbind ", " >/dev/null 2>&1 || true`);
        sideBindProc.command = ["bash", "-lc", cmds.join(" ; ")];
        sideBindProc.running = true;
    }

    function isValidBindKey(key: string): bool {
        if (!key || key.indexOf(" ") >= 0)
            return false;
        // Standard side buttons / media keys only (no keyboard keycodes — avoids
        // hijacking real keys; Xiaomi-style code:96 dongles are not supported).
        if (key.startsWith("mouse:")) {
            const n = parseInt(key.slice(6), 10);
            return !isNaN(n) && n >= 275 && n <= 300; // never left/right/middle
        }
        if (key.startsWith("XF86"))
            return true;
        return false;
    }

    function installCaptureBinds(): void {
        const cmds = [];
        for (const k of captureCandidateKeys()) {
            cmds.push(`hyprctl keyword unbind ", ${k}"`);
            cmds.push(`hyprctl keyword bind ", ${k}, exec, ${captureHitScript} ${k}"`);
        }
        sideBindProc.command = ["bash", "-lc", cmds.join(" ; ")];
        sideBindProc.running = true;
        captureInstallPending = false;
    }

    function cancelButtonCapture(): void {
        if (!capturing)
            return;
        capturing = false;
        activeCaptureSession = 0;
        captureStatus = qsTr("Recording cancelled");
        capturePollTimer.stop();
        captureTimeoutTimer.stop();
        pollArmTimer.stop();
        listenStartTimer.stop();
        // Stop listen process if still running
        if (inputListenProc.running)
            inputListenProc.running = false;
        // Drop any file written during a cancelled session.
        clearCaptureFileProc.command = ["bash", "-lc", `rm -f '${captureFilePath}' 2>/dev/null; :`];
        clearCaptureFileProc.running = true;
        resumeMapsAfterCapture();
        applySideBindsLive();
        statusMessage = qsTr("Button recording cancelled; mappings restored.");
    }

    function finishButtonCapture(key: string): void {
        if (!captureAcceptsResults())
            return;
        capturing = false;
        activeCaptureSession = 0;
        capturePollTimer.stop();
        captureTimeoutTimer.stop();
        pollArmTimer.stop();
        listenStartTimer.stop();
        if (inputListenProc.running)
            inputListenProc.running = false;
        lastCapturedKey = key;
        captureStatus = qsTr("Recorded: %1").arg(keyDisplayName(key));
        // Remove key file so the next "录制" cannot instantly re-finish on stale content.
        clearCaptureFileProc.command = ["bash", "-lc", `rm -f '${captureFilePath}' 2>/dev/null; :`];
        clearCaptureFileProc.running = true;
        resumeMapsAfterCapture();
        // Restore maps then upsert this key with pending action.
        upsertButtonMap(key, pendingCaptureAction);
        statusMessage = qsTr("Bound %1 → %2").arg(keyDisplayName(key)).arg(actionLabel(pendingCaptureAction));
    }

    function upsertButtonMap(key: string, actionId: string): void {
        const action = actionId || "default";
        key = normalizeBindKey(key);
        if (!isValidBindKey(key)) {
            statusMessage = qsTr("Could not bind button: %1").arg(key);
            captureStatus = statusMessage;
            applySideBindsLive();
            return;
        }
        const next = [];
        let found = false;
        for (const m of buttonMaps) {
            if (!m || !m.key)
                continue;
            const mk = normalizeBindKey(m.key);
            if (!isValidBindKey(mk))
                continue;
            if (mk === key) {
                if (action !== "default")
                    next.push({
                        key: key,
                        action: action
                    });
                found = true;
            } else if (!next.some(x => x.key === mk)) {
                next.push({
                    key: mk,
                    action: m.action
                });
            }
        }
        if (!found && action !== "default") {
            next.push({
                key: key,
                action: action
            });
        }
        buttonMaps = next;
        applySideBindsLive();
        scheduleMousePersist();
    }

    function removeButtonMap(key: string): void {
        const next = [];
        for (const m of buttonMaps) {
            if (m && m.key && m.key !== key)
                next.push(m);
        }
        buttonMaps = next;
        applySideBindsLive();
        scheduleMousePersist();
    }

    function setButtonMapAction(key: string, actionId: string): void {
        upsertButtonMap(key, actionId);
    }

    function applySideBindsLive(): void {
        if (capturing)
            return;
        // Always start from a clean slate for our namespace.
        const cmds = [];
        for (const k of managedBindKeys())
            cmds.push(`hyprctl keyword unbind ", ${k}" >/dev/null 2>&1 || true`);
        // Drop any leftover Xiaomi / keyboard keycode binds from older builds.
        for (const c of [14, 22, 28, 96, 158, 159, 171, 172])
            cmds.push(`hyprctl keyword unbind ", code:${c}" >/dev/null 2>&1 || true`);
        cmds.push(`hyprctl keyword unbind ", KP_Enter" >/dev/null 2>&1 || true`);

        for (const m of buttonMaps) {
            if (!m || !m.key || !isValidBindKey(m.key))
                continue;
            const k = normalizeBindKey(m.key);
            const dispatch = actionDispatch(m.action);
            if (!dispatch)
                continue; // pass-through
            cmds.push(`hyprctl keyword bind ", ${k}, ${dispatch}"`);
        }
        // Stop legacy Xiaomi side-key daemon if still running.
        cmds.push(`pkill -f '[v]illode-mi-side-daemon' >/dev/null 2>&1 || true`);
        sideBindProc.command = ["bash", "-lc", cmds.join(" ; ")];
        sideBindProc.running = true;
    }

    function applyMouseLive(): void {
        // Hyprland only converts middle-button drag to scroll when
        // scroll_method = on_button_down (scroll_button alone does nothing).
        const method = middleScroll ? "on_button_down" : "2fg";
        const btn = middleScroll ? btnMiddle : 0;
        const cmds = [
            `hyprctl keyword input:scroll_factor ${scrollFactor}`,
            `hyprctl keyword input:sensitivity ${sensitivity}`,
            `hyprctl keyword input:natural_scroll ${naturalScroll ? 1 : 0}`,
            `hyprctl keyword input:scroll_method ${method}`,
            `hyprctl keyword input:scroll_button ${btn}`,
            `hyprctl keyword input:scroll_button_lock ${middleScroll && middleScrollLock ? 1 : 0}`,
            `hyprctl keyword input:accel_profile ${flatAccel ? "flat" : "adaptive"}`
        ];
        // Also set on real mice (device section) — more reliable for some dongles.
        for (const m of mice) {
            const n = m.name;
            if (!n)
                continue;
            cmds.push(`hyprctl keyword "device[${n}]:scroll_method" ${method}`);
            cmds.push(`hyprctl keyword "device[${n}]:scroll_button" ${btn}`);
        }
        mouseApplyProc.command = ["bash", "-lc", cmds.join(" ; ")];
        mouseApplyProc.running = true;
        // Side-button binds live separately.
        applySideBindsLive();
    }

    function buildTouchpadConf(enabled: bool): string {
        const lines = ["# Managed by Caelestia settings — touchpad enable/disable", ""];
        if (!touchpads.length) {
            lines.push("# No touchpad detected at last save.");
            lines.push("");
            return lines.join("\n");
        }
        for (const pad of touchpads) {
            lines.push("device {");
            lines.push(`    name = ${pad.name}`);
            lines.push(`    enabled = ${enabled ? "true" : "false"}`);
            lines.push("}");
            lines.push("");
        }
        return lines.join("\n");
    }

    function buildMouseConf(): string {
        const method = middleScroll ? "on_button_down" : "2fg";
        const btn = middleScroll ? btnMiddle : 0;
        const lines = [
            "# Managed by Caelestia settings — mouse pointer & scroll",
            "input {",
            `    scroll_factor = ${scrollFactor}`,
            `    sensitivity = ${sensitivity}`,
            `    natural_scroll = ${naturalScroll ? "true" : "false"}`,
            // Required for middle-button drag-to-scroll:
            `    scroll_method = ${method}`,
            `    scroll_button = ${btn}`,
            `    scroll_button_lock = ${middleScroll && middleScrollLock ? "true" : "false"}`,
            `    accel_profile = ${flatAccel ? "flat" : "adaptive"}`,
            "}",
            ""
        ];
        for (const m of mice) {
            if (!m.name)
                continue;
            lines.push("device {");
            lines.push(`    name = ${m.name}`);
            lines.push(`    scroll_method = ${method}`);
            lines.push(`    scroll_button = ${btn}`);
            lines.push("}");
            lines.push("");
        }

        // Side-button mappings recorded via capture UI (only valid keys)
        const validMaps = [];
        for (const m of buttonMaps) {
            if (m && m.key && isValidBindKey(m.key) && actionDispatch(m.action))
                validMaps.push(m);
        }
        if (validMaps.length) {
            lines.push("# Mouse side-button mappings (Caelestia)");
            for (const m of validMaps) {
                lines.push(`unbind = , ${m.key}`);
                lines.push(`bind = , ${m.key}, ${actionDispatch(m.action)}`);
            }
            lines.push("");
        }
        return lines.join("\n");
    }

    function mouseStateJson(): string {
        return JSON.stringify({
            scrollFactor: scrollFactor,
            sensitivity: sensitivity,
            naturalScroll: naturalScroll,
            middleScroll: middleScroll,
            middleScrollLock: middleScrollLock,
            flatAccel: flatAccel,
            buttonMaps: buttonMaps
        }, null, 2) + "\n";
    }

    function persist(enabled: bool): void {
        writingMouse = false;
        pendingWriteContent = buildTouchpadConf(enabled);
        pendingWriteEnabled = enabled ? "1" : "0";
        mkdirProc.running = true;
    }

    function scheduleMousePersist(): void {
        mousePersistTimer.restart();
    }

    function persistMouse(): void {
        writingMouse = true;
        pendingMouseConf = buildMouseConf();
        pendingMouseJson = mouseStateJson();
        mkdirProc.running = true;
    }

    function writeFiles(): void {
        if (writingMouse) {
            mouseConfFile.path = hyprMousePath;
            villodeMouseFile.path = villodeMousePath;
            mouseStateFile.path = mouseStatePath;
            mouseConfFile.setText(pendingMouseConf);
            villodeMouseFile.setText(pendingMouseConf);
            mouseStateFile.setText(pendingMouseJson);
            ensureSourceProc.running = true;
            statusMessage = qsTr("Mouse settings saved.");
            writingMouse = false;
            return;
        }
        touchpadConfFile.path = hyprTouchpadPath;
        villodeTouchpadFile.path = villodeTouchpadPath;
        stateFile.path = touchpadStatePath;
        touchpadConfFile.setText(pendingWriteContent);
        villodeTouchpadFile.setText(pendingWriteContent);
        stateFile.setText(pendingWriteEnabled + "\n");
        ensureSourceProc.running = true;
    }

    function parseDevices(text: string): void {
        try {
            const data = JSON.parse(text);
            const allMice = data.mice || [];
            const pads = [];
            const pointerMice = [];
            for (const m of allMice) {
                const entry = {
                    name: m.name,
                    address: m.address || ""
                };
                if (isTouchpadName(m.name))
                    pads.push(entry);
                else
                    pointerMice.push(entry);
            }
            const strict = pads.filter(p => p.name.toLowerCase().includes("touchpad") || p.name.toLowerCase().includes("trackpad"));
            touchpads = strict.length ? strict : pads;
            mice = pointerMice;
        } catch (e) {
            statusMessage = qsTr("Could not read pointer device list.");
        }
    }

    function parseOptions(text: string): void {
        // Optional: pull live hypr values if no saved state yet.
        // Prefer mouse-settings.json when present (loaded via FileView).
        try {
            const lines = text.trim().split("\n");
            // format from: hyprctl getoption … printed multiple times - we use custom parse from combined dump
        } catch (e) {}
    }

    function applyParsedOptionBlock(block: string): void {
        // unused placeholder
    }

    function loadMouseStateText(text: string): void {
        try {
            const data = JSON.parse(text);
            if (typeof data.scrollFactor === "number")
                scrollFactor = clampScrollFactor(data.scrollFactor);
            if (typeof data.sensitivity === "number")
                sensitivity = clampSensitivity(data.sensitivity);
            if (typeof data.naturalScroll === "boolean")
                naturalScroll = data.naturalScroll;
            if (typeof data.middleScroll === "boolean")
                middleScroll = data.middleScroll;
            if (typeof data.middleScrollLock === "boolean")
                middleScrollLock = data.middleScrollLock;
            if (typeof data.flatAccel === "boolean")
                flatAccel = data.flatAccel;
            // New format
            if (Array.isArray(data.buttonMaps)) {
                const maps = [];
                const seen = {};
                for (const m of data.buttonMaps) {
                    if (!m || !m.key || !m.action)
                        continue;
                    const k = normalizeBindKey(String(m.key));
                    // Drop Xiaomi-only / invalid keys from older configs.
                    if (!k || seen[k] || !isValidBindKey(k))
                        continue;
                    seen[k] = true;
                    maps.push({
                        key: k,
                        action: String(m.action)
                    });
                }
                buttonMaps = maps;
            } else {
                // Migrate legacy fixed slots
                const maps = [];
                if (typeof data.mapSide === "string" && data.mapSide !== "default") {
                    maps.push({
                        key: "mouse:275",
                        action: data.mapSide
                    });
                    maps.push({
                        key: "XF86Back",
                        action: data.mapSide
                    });
                }
                if (typeof data.mapExtra === "string" && data.mapExtra !== "default") {
                    maps.push({
                        key: "mouse:276",
                        action: data.mapExtra
                    });
                    maps.push({
                        key: "XF86Forward",
                        action: data.mapExtra
                    });
                }
                if (typeof data.mapForward === "string" && data.mapForward !== "default") {
                    maps.push({
                        key: "mouse:277",
                        action: data.mapForward
                    });
                }
                if (typeof data.mapBack === "string" && data.mapBack !== "default") {
                    maps.push({
                        key: "mouse:278",
                        action: data.mapBack
                    });
                }
                if (maps.length)
                    buttonMaps = maps;
            }
            // Apply saved values to live session (in case conf wasn't sourced yet).
            Qt.callLater(() => applyMouseLive(), 200);
        } catch (e) {
            // keep defaults
        }
    }

    Component.onCompleted: {
        refresh();
        stateFile.path = touchpadStatePath;
        stateFile.reload();
        mouseStateFile.path = mouseStatePath;
        mouseStateFile.reload();
    }

    Process {
        id: listProc
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: root.parseDevices(text)
        }
    }

    // Read current hypr options to seed defaults when no state file.
    Process {
        id: optsProc
        command: ["bash", "-lc", `
sf=$(hyprctl getoption input:scroll_factor -j 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('float',1.0))" 2>/dev/null || echo 1)
se=$(hyprctl getoption input:sensitivity -j 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('float',0.0))" 2>/dev/null || echo 0)
ns=$(hyprctl getoption input:natural_scroll -j 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('int',0))" 2>/dev/null || echo 0)
sb=$(hyprctl getoption input:scroll_button -j 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('int',0))" 2>/dev/null || echo 0)
sl=$(hyprctl getoption input:scroll_button_lock -j 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('int',0))" 2>/dev/null || echo 0)
ap=$(hyprctl getoption input:accel_profile -j 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('str',''))" 2>/dev/null || echo)
printf '%s\\n' "$sf" "$se" "$ns" "$sb" "$sl" "$ap"
`]
        stdout: StdioCollector {
            onStreamFinished: {
                // Only seed if mouse state file missing (FileView loadFailed sets flag).
                if (root.mouseStateLoaded)
                    return;
                const parts = text.trim().split("\n");
                if (parts.length < 5)
                    return;
                const sf = parseFloat(parts[0]);
                const se = parseFloat(parts[1]);
                const ns = parseInt(parts[2], 10) === 1;
                const sb = parseInt(parts[3], 10);
                const sl = parseInt(parts[4], 10) === 1;
                const ap = (parts[5] || "").trim();
                if (!isNaN(sf))
                    root.scrollFactor = root.clampScrollFactor(sf);
                if (!isNaN(se))
                    root.sensitivity = root.clampSensitivity(se);
                root.naturalScroll = ns;
                root.middleScroll = sb === root.btnMiddle || sb === 2; // 2 sometimes used
                root.middleScrollLock = sl;
                root.flatAccel = ap === "flat";
            }
        }
    }

    property bool mouseStateLoaded: false

    Process {
        id: applyProc
        stdout: StdioCollector {}
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    root.statusMessage = text.trim();
            }
        }
        onExited: code => { // qmllint disable signal-handler-parameters
            root.busy = false;
            if (code === 0) {
                root.statusMessage = root.touchpadEnabled ? qsTr("Touchpad enabled.") : qsTr("Touchpad disabled.");
                root.persist(root.touchpadEnabled);
            } else {
                root.statusMessage = qsTr("Could not toggle touchpad.");
                root.touchpadEnabled = !root.touchpadEnabled;
            }
        }
    }

    Process {
        id: mouseApplyProc
        stdout: StdioCollector {}
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() && text.indexOf("ok") < 0)
                    root.statusMessage = text.trim();
            }
        }
    }

    Process {
        id: sideBindProc
        stdout: StdioCollector {}
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() && text.indexOf("ok") < 0)
                    root.statusMessage = text.trim();
            }
        }
        onExited: code => { // qmllint disable signal-handler-parameters
            if (code === 0 && !root.capturing)
                root.statusMessage = root.statusMessage || qsTr("Side-button mappings updated.");
        }
    }

    Process {
        id: chmodCaptureProc
        command: ["bash", "-lc", `mkdir -p \"$HOME/.local/bin\" && chmod +x \"${captureHitScript}\" \"${listenScript}\"`]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: code => { // qmllint disable signal-handler-parameters
            if (root.captureInstallPending && root.capturing)
                root.installCaptureBinds();
        }
    }

    Process {
        id: inputListenProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.captureAcceptsResults())
                    return;
                const lines = text.trim().split("\n");
                for (let i = lines.length - 1; i >= 0; i--) {
                    const l = lines[i].trim();
                    if (root.isCaptureKeyLine(l)) {
                        root.finishButtonCapture(l);
                        return;
                    }
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().includes("NO_DEVICES") && root.capturing)
                    root.captureStatus = qsTr("Could not read mouse devices. Add the user to the input group and log in again.");
            }
        }
        onExited: code => { // qmllint disable signal-handler-parameters
            if (!root.captureAcceptsResults())
                return;
            // Prefer the capture file after a successful listen exit.
            root.tryFinishFromCaptureFile();
            if (code !== 0 && !root.lastCapturedKey && root.capturing) {
                // Only reload FileView after arm window; never use it as primary.
                captureResultFile.path = root.captureFilePath;
                captureResultFile.reload();
            }
        }
    }

    Process {
        id: clearCaptureFileProc
        command: ["bash", "-lc", `rm -f \"${captureFilePath}\"`]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
    }

    Process {
        id: captureReadProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.captureAcceptsResults())
                    return;
                const key = text.trim();
                if (root.isCaptureKeyLine(key))
                    root.finishButtonCapture(key);
            }
        }
        stderr: StdioCollector {}
    }

    Timer {
        id: capturePollTimer
        interval: 150
        repeat: true
        onTriggered: {
            if (!root.captureAcceptsResults())
                return;
            root.tryFinishFromCaptureFile();
        }
    }

    // Wait out the arm window before polling so a leftover capture.key cannot finish instantly.
    Timer {
        id: pollArmTimer
        interval: 560
        onTriggered: {
            if (root.capturing)
                root.capturePollTimer.start();
        }
    }

    Timer {
        id: captureTimeoutTimer
        interval: 14000
        onTriggered: {
            if (root.capturing) {
                root.capturing = false;
                root.activeCaptureSession = 0;
                root.captureStatus = qsTr("Recording timed out; try again");
                root.capturePollTimer.stop();
                root.pollArmTimer.stop();
                if (inputListenProc.running)
                    inputListenProc.running = false;
                root.resumeMapsAfterCapture();
                root.applySideBindsLive();
                root.statusMessage = qsTr("Recording timed out; previous mappings restored.");
            }
        }
    }

    Process {
        id: pauseFlagProc
        stdout: StdioCollector {}
        stderr: StdioCollector {}
    }

    Process {
        id: resumeFlagProc
        stdout: StdioCollector {}
        stderr: StdioCollector {}
    }

    // Must exist: startButtonCapture() calls restart(). Missing this leaves
    // capturing=true with no listener (ReferenceError in qs log).
    Timer {
        id: listenStartTimer
        interval: 120
        onTriggered: {
            if (root.capturing)
                root.startInputListener();
        }
    }

    FileView {
        id: captureResultFile
        printErrors: false
        watchChanges: false
        onLoaded: {
            if (!root.captureAcceptsResults())
                return;
            const key = text().trim();
            if (root.isCaptureKeyLine(key))
                root.finishButtonCapture(key);
        }
    }

    FileView {
        id: captureScriptFile
        printErrors: false
        atomicWrites: true
    }

    Process {
        id: mkdirProc
        command: ["bash", "-lc", "mkdir -p \"${XDG_CONFIG_HOME:-$HOME/.config}/hypr/conf.d\" \"${XDG_CONFIG_HOME:-$HOME/.config}/villode-hyprland\" \"${XDG_STATE_HOME:-$HOME/.local/state}/caelestia\""]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: code => { // qmllint disable signal-handler-parameters
            if (code === 0)
                root.writeFiles();
            else if (!root.statusMessage)
                root.statusMessage = qsTr("Could not create configuration directory.");
        }
    }

    Process {
        id: ensureSourceProc
        command: ["bash", "-lc", `
set -euo pipefail
cfg_home="\${XDG_CONFIG_HOME:-$HOME/.config}"
# Create stub confs if missing so Hyprland source never fails.
hypr_tp="$cfg_home/hypr/conf.d/villode-touchpad.conf"
vh_tp="$cfg_home/villode-hyprland/touchpad.conf"
hypr_ms="$cfg_home/hypr/conf.d/villode-mouse.conf"
vh_ms="$cfg_home/villode-hyprland/mouse.conf"
mkdir -p "$(dirname "$hypr_tp")" "$(dirname "$vh_tp")" "$(dirname "$hypr_ms")" "$(dirname "$vh_ms")"
[[ -f "$hypr_tp" ]] || printf '%s\\n' '# Managed by Caelestia settings — touchpad' '' > "$hypr_tp"
[[ -f "$vh_tp" ]] || printf '%s\\n' '# Managed by Caelestia settings — touchpad' '' > "$vh_tp"
[[ -f "$hypr_ms" ]] || printf '%s\\n' '# Managed by Caelestia settings — mouse' '' > "$hypr_ms"
[[ -f "$vh_ms" ]] || printf '%s\\n' '# Managed by Caelestia settings — mouse' '' > "$vh_ms"
for conf in "$cfg_home/hypr/hyprland.conf" "$cfg_home/villode-hyprland/hyprland.conf"; do
  [[ -f "$conf" ]] || continue
  if [[ "$conf" == *villode-hyprland* ]]; then
    if ! grep -Fq 'villode-hyprland/touchpad.conf' "$conf"; then
      printf '\\n# Touchpad enable/disable (Caelestia)\\nsource = %s\\n' "$cfg_home/villode-hyprland/touchpad.conf" >> "$conf"
    fi
    if ! grep -Fq 'villode-hyprland/mouse.conf' "$conf"; then
      printf '\\n# Mouse pointer & scroll (Caelestia)\\nsource = %s\\n' "$cfg_home/villode-hyprland/mouse.conf" >> "$conf"
    fi
  else
    if ! grep -Fq 'conf.d/villode-touchpad.conf' "$conf"; then
      printf '\\n# Touchpad enable/disable (Caelestia)\\nsource = %s\\n' "$cfg_home/hypr/conf.d/villode-touchpad.conf" >> "$conf"
    fi
    if ! grep -Fq 'conf.d/villode-mouse.conf' "$conf"; then
      printf '\\n# Mouse pointer & scroll (Caelestia)\\nsource = %s\\n' "$cfg_home/hypr/conf.d/villode-mouse.conf" >> "$conf"
    fi
  fi
done
`]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
    }

    Timer {
        id: mousePersistTimer
        interval: 350
        onTriggered: root.persistMouse()
    }

    FileView {
        id: stateFile
        printErrors: false
        watchChanges: true
        onLoaded: {
            const v = text().trim();
            if (v === "0" || v === "false")
                root.touchpadEnabled = false;
            else if (v === "1" || v === "true")
                root.touchpadEnabled = true;
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                root.touchpadEnabled = true;
        }
    }

    FileView {
        id: mouseStateFile
        printErrors: false
        watchChanges: false
        onLoaded: {
            root.mouseStateLoaded = true;
            root.loadMouseStateText(text());
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                root.mouseStateLoaded = false;
        }
    }

    FileView {
        id: touchpadConfFile
        printErrors: false
        atomicWrites: true
    }

    FileView {
        id: villodeTouchpadFile
        printErrors: false
        atomicWrites: true
    }

    FileView {
        id: mouseConfFile
        printErrors: false
        atomicWrites: true
    }

    FileView {
        id: villodeMouseFile
        printErrors: false
        atomicWrites: true
    }

    Connections {
        target: Hyprland
        function onRawEvent(event): void {
            const n = event.name;
            if (n && (n.includes("config") || n.includes("device") || n.includes("monitor")))
                refreshTimer.restart();
        }
    }

    Timer {
        id: refreshTimer
        interval: 400
        onTriggered: root.refresh()
    }
}
