pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root

    property list<var> touchpads: []
    property bool touchpadEnabled: true
    property bool busy: false
    property string statusMessage: ""
    property string pendingEnabled: ""

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || `${Quickshell.env("HOME")}/.config`
    readonly property string hyprTouchpadPath: `${configHome}/hypr/conf.d/villode-touchpad.conf`
    readonly property string villodeTouchpadPath: `${configHome}/villode-hyprland/touchpad.conf`
    readonly property string statePath: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/caelestia/touchpad-enabled`

    function refresh(): void {
        if (!listProc.running)
            listProc.running = true;
    }

    function isTouchpadName(name: string): bool {
        const n = String(name || "").toLowerCase();
        return n.includes("touchpad") || n.includes("trackpad") || n.includes("synaptics") || (n.includes("elan") && n.includes("touchpad"));
    }

    function setTouchpadEnabled(enabled: bool): void {
        if (busy)
            return;
        if (!touchpads.length) {
            statusMessage = "未检测到触摸板。";
            return;
        }

        busy = true;
        statusMessage = "";
        pendingEnabled = enabled ? "1" : "0";
        touchpadEnabled = enabled;

        const cmds = [];
        for (const pad of touchpads) {
            // Hyprland device keywords: device[name]:enabled 0/1
            cmds.push(`hyprctl keyword "device[${pad.name}]:enabled" ${enabled ? 1 : 0}`);
        }
        applyProc.command = ["bash", "-lc", cmds.join(" && ")];
        applyProc.running = true;
    }

    function toggleTouchpad(): void {
        setTouchpadEnabled(!touchpadEnabled);
    }

    function buildConf(enabled: bool): string {
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

    function persist(enabled: bool): void {
        pendingWriteContent = buildConf(enabled);
        pendingWriteEnabled = enabled ? "1" : "0";
        // Always materialize conf files before adding `source =` lines (Hyprland errors if missing).
        mkdirProc.running = true;
    }

    property string pendingWriteContent: ""
    property string pendingWriteEnabled: "1"

    function writeFiles(): void {
        touchpadConfFile.path = hyprTouchpadPath;
        villodeTouchpadFile.path = villodeTouchpadPath;
        stateFile.path = statePath;
        // Write both confs first; only then append source lines.
        touchpadConfFile.setText(pendingWriteContent);
        villodeTouchpadFile.setText(pendingWriteContent);
        stateFile.setText(pendingWriteEnabled + "\n");
        ensureSourceProc.running = true;
    }

    function parseDevices(text: string): void {
        try {
            const data = JSON.parse(text);
            const mice = data.mice || [];
            const pads = [];
            for (const m of mice) {
                if (isTouchpadName(m.name)) {
                    pads.push({
                        name: m.name,
                        address: m.address || ""
                    });
                }
            }
            // Prefer names ending with -touchpad when both mouse+touchpad nodes exist
            const strict = pads.filter(p => p.name.toLowerCase().includes("touchpad") || p.name.toLowerCase().includes("trackpad"));
            touchpads = strict.length ? strict : pads;
        } catch (e) {
            statusMessage = "无法读取指针设备列表。";
        }
    }

    Component.onCompleted: {
        refresh();
        // Load saved preference after devices are known
        stateFile.path = statePath;
        stateFile.reload();
    }

    Process {
        id: listProc
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: root.parseDevices(text)
        }
    }

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
                root.statusMessage = root.touchpadEnabled ? "触摸板已启用。" : "触摸板已禁用。";
                root.persist(root.touchpadEnabled);
            } else {
                root.statusMessage = "切换触摸板失败。";
                // Revert optimistic UI
                root.touchpadEnabled = !root.touchpadEnabled;
            }
        }
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
                root.statusMessage = "无法创建触摸板配置目录。";
        }
    }

    Process {
        id: ensureSourceProc
        command: ["bash", "-lc", `
set -euo pipefail
cfg_home="\${XDG_CONFIG_HOME:-$HOME/.config}"
# Create stub confs if missing so Hyprland source never glob-fails.
hypr_tp="$cfg_home/hypr/conf.d/villode-touchpad.conf"
vh_tp="$cfg_home/villode-hyprland/touchpad.conf"
mkdir -p "$(dirname "$hypr_tp")" "$(dirname "$vh_tp")"
if [[ ! -f "$hypr_tp" ]]; then
  printf '%s\\n' '# Managed by Caelestia settings — touchpad enable/disable' '' > "$hypr_tp"
fi
if [[ ! -f "$vh_tp" ]]; then
  printf '%s\\n' '# Managed by Caelestia settings — touchpad enable/disable' '' > "$vh_tp"
fi
for conf in "$cfg_home/hypr/hyprland.conf" "$cfg_home/villode-hyprland/hyprland.conf"; do
  [[ -f "$conf" ]] || continue
  if [[ "$conf" == *villode-hyprland* ]]; then
    marker='villode-hyprland/touchpad.conf'
    # Absolute path avoids ~ expansion / glob issues in some Hyprland versions.
    line="source = $cfg_home/villode-hyprland/touchpad.conf"
  else
    marker='conf.d/villode-touchpad.conf'
    line="source = $cfg_home/hypr/conf.d/villode-touchpad.conf"
  fi
  if ! grep -Fq "$marker" "$conf"; then
    printf '\\n# Touchpad enable/disable (Caelestia)\\n%s\\n' "$line" >> "$conf"
  fi
done
`]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
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
            // default enabled
            if (err === FileViewError.FileNotFound)
                root.touchpadEnabled = true;
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
