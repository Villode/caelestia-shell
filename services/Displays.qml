pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Caelestia.Config

Singleton {
    id: root

    property list<var> monitors: []
    property string selectedName: ""
    property bool busy: false
    property string statusMessage: ""
    property var pendingPersist: null
    property string pendingWriteContent: ""
    property int pendingWrites: 0

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || `${Quickshell.env("HOME")}/.config`
    readonly property string hyprMonitorsPath: `${configHome}/hypr/conf.d/villode-monitors.conf`
    readonly property string villodeMonitorsPath: `${configHome}/villode-hyprland/monitors.conf`

    readonly property var selected: {
        if (!monitors.length)
            return null;
        return monitors.find(m => m.name === selectedName) || monitors[0];
    }

    readonly property real shellUiScale: GlobalConfig.appearance.font.scale || 1

    function refresh(): void {
        if (!listProc.running)
            listProc.running = true;
    }

    function selectMonitor(name: string): void {
        if (name)
            selectedName = name;
    }

    function formatMode(mode: string): string {
        const m = String(mode).match(/^(\d+)x(\d+)@([\d.]+)Hz$/i);
        if (!m)
            return mode;
        const hz = Number(m[3]);
        const hzText = Number.isInteger(hz) ? String(hz) : hz.toFixed(2).replace(/\.?0+$/, "");
        return `${m[1]} × ${m[2]} · ${hzText} Hz`;
    }

    function normalizeMode(mode: string): string {
        return String(mode).replace(/Hz$/i, "");
    }

    function formatScale(scale: real): string {
        return String(Math.round(scale * 100) / 100);
    }

    function currentModeString(monitor: var): string {
        if (!monitor)
            return "";
        const modes = monitor.availableModes || [];
        const exact = `${monitor.width}x${monitor.height}@${Number(monitor.refreshRate).toFixed(2)}Hz`;
        if (modes.includes(exact))
            return exact;

        const sameRes = modes.filter(mode => mode.startsWith(`${monitor.width}x${monitor.height}@`));
        if (sameRes.length) {
            let best = sameRes[0];
            let bestDiff = Infinity;
            for (const mode of sameRes) {
                const match = mode.match(/@([\d.]+)Hz$/i);
                if (!match)
                    continue;
                const diff = Math.abs(Number(match[1]) - Number(monitor.refreshRate));
                if (diff < bestDiff) {
                    bestDiff = diff;
                    best = mode;
                }
            }
            return best;
        }

        return exact;
    }

    function applySelected(mode: string, scale: real): void {
        const mon = selected;
        if (!mon || !mode || busy)
            return;

        const clampedScale = Math.max(0.5, Math.min(3.0, scale));
        const scaleStr = formatScale(clampedScale);
        const pos = `${mon.x}x${mon.y}`;
        const normMode = normalizeMode(mode);

        busy = true;
        statusMessage = "";
        pendingPersist = {
            name: mon.name,
            mode: normMode,
            scale: scaleStr,
            x: mon.x,
            y: mon.y,
            disabled: !!mon.disabled
        };

        applyProc.command = ["hyprctl", "keyword", "monitor", `${mon.name},${normMode},${pos},${scaleStr}`];
        applyProc.running = true;
    }

    function applyScalePercent(percent: real): void {
        const mon = selected;
        if (!mon)
            return;
        applySelected(currentModeString(mon), percent / 100);
    }

    function applyMode(mode: string): void {
        const mon = selected;
        if (!mon)
            return;
        applySelected(mode, mon.scale || 1);
    }

    function setShellUiScalePercent(percent: real): void {
        const s = Math.max(0.5, Math.min(2.5, Math.round(percent) / 100));
        GlobalConfig.appearance.font.scale = s;
        GlobalConfig.appearance.padding.scale = s;
        GlobalConfig.appearance.spacing.scale = s;
        GlobalConfig.appearance.rounding.scale = s;
    }

    function buildMonitorConfig(): string {
        const byName = {};
        for (const mon of monitors) {
            byName[mon.name] = {
                name: mon.name,
                mode: normalizeMode(currentModeString(mon)),
                scale: formatScale(mon.scale || 1),
                x: mon.x,
                y: mon.y,
                disabled: !!mon.disabled
            };
        }
        if (pendingPersist && pendingPersist.name)
            byName[pendingPersist.name] = pendingPersist;

        const lines = ["# Managed by Caelestia Display settings.", ""];
        for (const name of Object.keys(byName).sort()) {
            const mon = byName[name];
            if (mon.disabled)
                lines.push(`monitor = ${mon.name}, disable`);
            else
                lines.push(`monitor = ${mon.name}, ${mon.mode}, ${mon.x}x${mon.y}, ${mon.scale}`);
        }
        lines.push("");
        return lines.join("\n");
    }

    function persistMonitors(): void {
        if (!monitors.length && !pendingPersist)
            return;

        pendingWriteContent = buildMonitorConfig();
        pendingWrites = 2;

        // Ensure parent directories exist, then write via FileView.
        mkdirProc.command = ["mkdir", "-p", `${configHome}/hypr/conf.d`, `${configHome}/villode-hyprland`];
        mkdirProc.running = true;
    }

    function writeMonitorFiles(): void {
        hyprMonitorsFile.path = hyprMonitorsPath;
        villodeMonitorsFile.path = villodeMonitorsPath;
        hyprMonitorsFile.setText(pendingWriteContent);
        villodeMonitorsFile.setText(pendingWriteContent);
        ensureSourceProc.running = true;
    }

    function parseMonitors(text: string): void {
        try {
            const data = JSON.parse(text);
            if (!Array.isArray(data)) {
                statusMessage = "无法解析显示器列表。";
                return;
            }

            const next = data.map(m => ({
                id: m.id,
                name: m.name,
                description: m.description || m.model || m.name,
                width: m.width,
                height: m.height,
                refreshRate: m.refreshRate,
                scale: m.scale,
                x: m.x,
                y: m.y,
                focused: !!m.focused,
                disabled: !!m.disabled,
                availableModes: Array.isArray(m.availableModes) ? m.availableModes : []
            }));

            monitors = next;

            if (!selectedName || !next.some(m => m.name === selectedName)) {
                const focused = next.find(m => m.focused);
                selectedName = focused?.name || next[0]?.name || "";
            }
        } catch (error) {
            statusMessage = "无法读取显示器信息。";
        }
    }

    Component.onCompleted: refresh()

    Connections {
        target: Hyprland

        function onRawEvent(event): void {
            const n = event.name;
            if (!n)
                return;
            if (n.includes("mon") || n === "configreloaded")
                refreshTimer.restart();
        }
    }

    Timer {
        id: refreshTimer
        interval: 250
        onTriggered: root.refresh()
    }

    Process {
        id: listProc
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: root.parseMonitors(text)
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    root.statusMessage = text.trim();
            }
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
                root.statusMessage = "显示设置已应用。";
                root.persistMonitors();
                root.refresh();
            } else if (!root.statusMessage) {
                root.statusMessage = "应用显示设置失败。";
            }
        }
    }

    Process {
        id: mkdirProc
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: code => { // qmllint disable signal-handler-parameters
            if (code === 0)
                root.writeMonitorFiles();
            else if (!root.statusMessage)
                root.statusMessage = "无法创建显示配置目录。";
        }
    }

    Process {
        id: ensureSourceProc
        command: ["bash", "-lc", `
set -euo pipefail
cfg_home="\${XDG_CONFIG_HOME:-$HOME/.config}"
hypr_conf="$cfg_home/hypr/hyprland.conf"
if [[ -f "$hypr_conf" ]] && ! grep -Fq 'conf.d/villode-monitors.conf' "$hypr_conf"; then
  printf '\\n# Villode / Caelestia display settings\\nsource = ~/.config/hypr/conf.d/villode-monitors.conf\\n' >> "$hypr_conf"
fi
vh_conf="$cfg_home/villode-hyprland/hyprland.conf"
if [[ -f "$vh_conf" ]] && ! grep -Fq 'villode-hyprland/monitors.conf' "$vh_conf" && ! grep -Fq 'source = ~/.config/villode-hyprland/monitors.conf' "$vh_conf"; then
  printf '\\n# Villode / Caelestia display settings\\nsource = ~/.config/villode-hyprland/monitors.conf\\n' >> "$vh_conf"
fi
`]
        stdout: StdioCollector {}
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    root.statusMessage = text.trim();
            }
        }
        onExited: code => { // qmllint disable signal-handler-parameters
            if (code === 0) {
                if (!root.statusMessage || root.statusMessage === "显示设置已应用。")
                    root.statusMessage = "显示设置已应用并保存。";
            } else if (!root.statusMessage) {
                root.statusMessage = "设置已应用，但写入 Hyprland source 失败。";
            }
        }
    }

    FileView {
        id: hyprMonitorsFile
        printErrors: false
        atomicWrites: true
        onSaved: {
            root.pendingWrites = Math.max(0, root.pendingWrites - 1);
            if (root.pendingWrites === 0 && (!root.statusMessage || root.statusMessage === "显示设置已应用。"))
                root.statusMessage = "显示设置已应用并保存。";
        }
        onSaveFailed: {
            root.pendingWrites = Math.max(0, root.pendingWrites - 1);
            root.statusMessage = "设置已应用，但保存配置失败。";
        }
    }

    FileView {
        id: villodeMonitorsFile
        printErrors: false
        atomicWrites: true
        onSaved: {
            root.pendingWrites = Math.max(0, root.pendingWrites - 1);
            if (root.pendingWrites === 0 && (!root.statusMessage || root.statusMessage === "显示设置已应用。"))
                root.statusMessage = "显示设置已应用并保存。";
        }
        onSaveFailed: {
            root.pendingWrites = Math.max(0, root.pendingWrites - 1);
            root.statusMessage = "设置已应用，但保存配置失败。";
        }
    }
}
