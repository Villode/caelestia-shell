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
        // Emit enough precision for fractional clean divisors (e.g. 5/6 ≈ 0.833333).
        if (!(scale > 0))
            return "1";
        if (Math.abs(scale - Math.round(scale)) < 1e-6)
            return String(Math.round(scale));
        // Trim trailing zeros but keep up to 6 decimals.
        let s = scale.toFixed(6);
        s = s.replace(/\.?0+$/, "");
        return s || "1";
    }

    function parseModeSize(mode: string): var {
        const m = String(mode || "").match(/^(\d+)x(\d+)/);
        if (!m)
            return null;
        return {
            width: Number(m[1]),
            height: Number(m[2])
        };
    }

    // Hyprland only accepts scales on a 1/120 grid that also yield integer
    // logical pixels (see Monitor.cpp: searchScale = round(scale * 120)).
    // Illegal values toast: "被设置了非法的缩放 … 将使用建议的缩放".
    readonly property int scaleGrid: 120

    function isCleanScale(width: int, height: int, scale: real): bool {
        if (!(width > 0) || !(height > 0) || !(scale > 0))
            return false;
        const n = Math.round(scale * scaleGrid);
        if (n <= 0)
            return false;
        // Must sit on the N/120 grid Hyprland searches.
        if (Math.abs(n / scaleGrid - scale) > 1e-6)
            return false;
        // width*120/n and height*120/n must be integers.
        return (width * scaleGrid) % n === 0 && (height * scaleGrid) % n === 0;
    }

    function validScalesFor(width: int, height: int, minScale: real, maxScale: real): list<real> {
        const lo = minScale > 0 ? minScale : 0.5;
        const hi = maxScale > 0 ? maxScale : 3.0;
        if (!(width > 0) || !(height > 0))
            return [1];

        const scales = [];
        const minN = Math.max(1, Math.ceil(lo * scaleGrid - 1e-9));
        const maxN = Math.floor(hi * scaleGrid + 1e-9);

        for (let n = minN; n <= maxN; n++) {
            if ((width * scaleGrid) % n !== 0)
                continue;
            if ((height * scaleGrid) % n !== 0)
                continue;
            scales.push(n / scaleGrid);
        }

        if (!scales.length)
            scales.push(1);
        return scales;
    }

    function nearestValidScale(width: int, height: int, desired: real): real {
        const scales = validScalesFor(width, height, 0.5, 3.0);
        let best = scales[0];
        let bestDiff = Math.abs(best - desired);
        for (const s of scales) {
            const diff = Math.abs(s - desired);
            if (diff < bestDiff - 1e-12) {
                best = s;
                bestDiff = diff;
            }
        }
        return best;
    }

    // Familiar percentage steps that are clean for this resolution on the N/120 grid.
    function preferredScales(width: int, height: int): list<real> {
        const targets = [0.5, 0.75, 1.0, 1.2, 1.25, 1.5, 1.6, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0];
        const out = [];
        const seen = {};
        for (const t of targets) {
            // Snap each familiar target onto Hyprland's grid first, then keep if clean.
            const n = Math.round(t * scaleGrid);
            const candidate = n / scaleGrid;
            if (!isCleanScale(width, height, candidate))
                continue;
            const key = candidate.toFixed(6);
            if (seen[key])
                continue;
            seen[key] = true;
            out.push(candidate);
        }
        if (!out.length)
            out.push(nearestValidScale(width, height, 1));
        return out;
    }

    function scaleChoicesForMonitor(monitor: var, mode: string): list<real> {
        const size = parseModeSize(mode) || (monitor ? {
                width: monitor.width,
                height: monitor.height
            } : null);
        if (!size)
            return [1];

        const choices = preferredScales(size.width, size.height);
        // Keep the active scale visible even when it is not a common preset
        // (e.g. Hyprland previously snapped 0.90 → ≈0.8333).
        const current = monitor?.scale;
        if (current > 0 && isCleanScale(size.width, size.height, current)) {
            const key = current.toFixed(6);
            const has = choices.some(s => s.toFixed(6) === key);
            if (!has) {
                choices.push(current);
                choices.sort((a, b) => a - b);
            }
        }
        return choices;
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

        const size = parseModeSize(mode) || {
            width: mon.width,
            height: mon.height
        };
        // Never send an illegal scale: Hyprland toasts and rewrites it (e.g. 0.90 → 0.83).
        const desired = Math.max(0.5, Math.min(3.0, scale));
        const cleanScale = isCleanScale(size.width, size.height, desired) ? desired : nearestValidScale(size.width, size.height, desired);
        const scaleStr = formatScale(cleanScale);
        const pos = `${mon.x}x${mon.y}`;
        const normMode = normalizeMode(mode);
        const snapped = Math.abs(cleanScale - desired) > 1e-3;

        busy = true;
        statusMessage = snapped ? `已自动调整为合法缩放 ${formatScale(cleanScale)}（约 ${Math.round(cleanScale * 100)}%）。` : "";
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

    function applyScale(scale: real): void {
        const mon = selected;
        if (!mon)
            return;
        applySelected(currentModeString(mon), scale);
    }

    function applyMode(mode: string): void {
        const mon = selected;
        if (!mon)
            return;
        // Re-validate scale against the *new* resolution.
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
                if (!root.statusMessage || root.statusMessage.startsWith("已自动调整"))
                    root.statusMessage = (root.statusMessage && root.statusMessage.startsWith("已自动调整") ? root.statusMessage + " " : "") + "显示设置已应用。";
                else
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
