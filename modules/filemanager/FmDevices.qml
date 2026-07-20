pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Poll block devices + gvfs mounts; expose devices[] with capacity fields
Item {
    id: root
    width: 0
    height: 0
    visible: false

    property var devices: []
    property string lastError: ""
    property bool mounting: false
    property string mountStatus: ""
    property string pendingDevice: ""
    property string pendingName: ""

    signal mountFinished(bool ok, string message, string path)

    function refresh(): void {
        lsblkProc.running = false;
        lsblkProc.running = true;
    }

    function findMountedPath(device: string): string {
        const list = devices || [];
        for (let i = 0; i < list.length; i++) {
            if (list[i].device === device && list[i].mounted && list[i].path)
                return list[i].path;
        }
        return "";
    }

    function mountDevice(device: string, name: string): void {
        if (!device || mounting)
            return;
        mounting = true;
        mountStatus = qsTr("正在挂载…");
        pendingDevice = device;
        pendingName = name || device;
        gioMountProc.running = false;
        gioMountProc.command = ["gio", "mount", "-d", device];
        gioMountProc.running = true;
    }

    function mountWithPassword(device: string, name: string, _unused: string): void {
        if (!device)
            return;
        mounting = true;
        mountStatus = qsTr("等待系统授权…");
        pendingDevice = device;
        pendingName = name || device;
        // Prefer udisksctl when present; else mount to /mnt/villode-<dev>
        const base = device.split("/").pop();
        const mnt = "/mnt/villode-" + base;
        const script = "set -e; " + "if command -v udisksctl >/dev/null 2>&1; then " + "  out=$(udisksctl mount -b " + device + " 2>&1); echo \"$out\"; " + "  echo \"$out\" | sed -n 's/.*at \\(.*\\)\\.*/\\1/p'; " + "else " + "  mkdir -p " + mnt + "; " + "  mount " + device + " " + mnt + "; " + "  echo " + mnt + "; " + "fi";
        pkexecMountProc.running = false;
        pkexecMountProc.command = ["pkexec", "bash", "-c", script];
        pkexecMountProc.running = true;
    }

    function finishMount(ok: bool, msg: string, path: string): void {
        mounting = false;
        mountStatus = msg || "";
        mountFinished(ok, msg || "", path || "");
        refresh();
    }

    function parseBytes(v: var): real {
        if (v === null || v === undefined || v === "")
            return 0;
        const n = Number(v);
        return isNaN(n) ? 0 : n;
    }

    function humanBytes(bytes: real): string {
        if (!bytes || bytes <= 0)
            return "";
        const units = ["B", "KB", "MB", "GB", "TB", "PB"];
        let v = bytes;
        let i = 0;
        while (v >= 1024 && i < units.length - 1) {
            v /= 1024;
            i++;
        }
        return (v >= 10 || i === 0 ? v.toFixed(0) : v.toFixed(1)) + " " + units[i];
    }

    function mountPointOf(n: var): string {
        if (!n)
            return "";
        if (n.mountpoint && n.mountpoint !== "[SWAP]")
            return String(n.mountpoint);
        if (n.mountpoints && n.mountpoints.length) {
            for (let i = 0; i < n.mountpoints.length; i++) {
                const mp = n.mountpoints[i];
                if (mp && mp !== "[SWAP]")
                    return String(mp);
            }
        }
        return "";
    }

    function flatten(nodes: var, out: var): void {
        if (!nodes)
            return;
        for (let i = 0; i < nodes.length; i++) {
            const n = nodes[i];
            const type = n.type || "";
            const mp = mountPointOf(n);
            const fstype = n.fstype || "";
            const name = n.name || "";
            const label = n.label || n.partlabel || "";
            const sizeStr = n.size || "";
            const sizeBytes = parseBytes(n.fssize) || parseBytes(n.size);
            const usedBytes = parseBytes(n.fsused);
            const availBytes = parseBytes(n.fsavail);
            let usedPct = 0;
            if (sizeBytes > 0 && usedBytes > 0)
                usedPct = Math.min(100, Math.max(0, (usedBytes / sizeBytes) * 100));
            else if (n["fsuse%"]) {
                const p = parseFloat(String(n["fsuse%"]).replace("%", ""));
                if (!isNaN(p))
                    usedPct = p;
            }
            const rm = !!(n.rm || n.hotplug);
            const dev = name.startsWith("/dev/") ? name : ("/dev/" + name);

            const skipFs = !fstype || fstype === "swap" || fstype === "crypto_LUKS";
            const isPart = type === "part" || type === "lvm" || type === "crypt";
            if (isPart && !skipFs) {
                const interestingMp = mp.length > 0 && !mp.startsWith("/snap");
                const unmountedData = !mp && (rm || label || ["ntfs", "exfat", "vfat", "ext4", "btrfs", "xfs", "f2fs"].indexOf(fstype) >= 0);
                if (interestingMp || unmountedData) {
                    let kind = "disk";
                    let icon = "hard_drive";
                    if (rm) {
                        kind = "removable";
                        icon = "usb";
                    }
                    if (fstype === "ntfs")
                        icon = "folder_data";
                    if (mp === "/") {
                        kind = "system";
                        icon = "computer";
                    } else if (mp === "/boot" || mp === "/boot/efi") {
                        kind = "boot";
                        icon = "memory";
                    }

                    let display = label;
                    if (!display) {
                        if (mp === "/")
                            display = qsTr("本地磁盘 (系统)");
                        else if (mp === "/home")
                            display = qsTr("主目录卷");
                        else if (mp)
                            display = mp;
                        else
                            display = name;
                    }

                    // Windows-like letter suffix for common roots
                    let letter = "";
                    if (mp === "/")
                        letter = "C:";
                    else if (mp === "/home")
                        letter = "H:";
                    else if (label)
                        letter = "";

                    const freeBytes = availBytes > 0 ? availBytes : (sizeBytes > usedBytes ? sizeBytes - usedBytes : 0);
                    let capText = "";
                    if (mp && sizeBytes > 0) {
                        capText = qsTr("%1 可用，共 %2").arg(humanBytes(freeBytes) || "—").arg(humanBytes(sizeBytes) || sizeStr || "—");
                    } else if (sizeBytes > 0 || sizeStr) {
                        capText = (humanBytes(sizeBytes) || sizeStr) + (fstype ? " · " + fstype : "") + (mp ? "" : (" · " + qsTr("未挂载")));
                    } else {
                        capText = (fstype || "") + (mp ? (" · " + mp) : (" · " + qsTr("未挂载")));
                    }

                    out.push({
                        id: dev + "|" + (mp || "umount"),
                        name: display,
                        letter: letter,
                        subtitle: capText,
                        path: mp,
                        icon: icon,
                        kind: kind,
                        size: sizeStr,
                        sizeBytes: sizeBytes,
                        usedBytes: usedBytes,
                        freeBytes: freeBytes,
                        usedPct: usedPct,
                        removable: rm,
                        mounted: !!mp,
                        device: dev,
                        fstype: fstype
                    });
                }
            }
            if (n.children)
                flatten(n.children, out);
        }
    }

    function buildList(jsonText: string): void {
        try {
            const data = JSON.parse(jsonText);
            const out = [];
            const home = Quickshell.env("HOME") || "";
            // No folder section here — sidebar already has 主目录/常用

            const blocks = [];
            flatten(data.blockdevices || [], blocks);

            const byPath = {};
            const unmounted = [];
            for (let i = 0; i < blocks.length; i++) {
                const b = blocks[i];
                if (!b.mounted) {
                    unmounted.push(b);
                    continue;
                }
                if (b.path === home)
                    continue;
                if (b.path === "/var/tmp" || b.path === "/tmp" || b.path.startsWith("/run/"))
                    continue;
                if (!byPath[b.path])
                    byPath[b.path] = b;
            }
            // Prefer system first
            const ordered = Object.keys(byPath).map(p => byPath[p]);
            ordered.sort((a, b) => {
                const score = d => {
                    if (d.path === "/")
                        return 0;
                    if (d.path === "/home")
                        return 1;
                    if (d.kind === "boot")
                        return 9;
                    return 5;
                };
                return score(a) - score(b);
            });
            for (let i = 0; i < ordered.length; i++)
                out.push(ordered[i]);
            for (let i = 0; i < unmounted.length; i++)
                out.push(unmounted[i]);

            devices = out;
            lastError = "";
            gvfsProc.running = false;
            gvfsProc.running = true;
        } catch (e) {
            lastError = String(e);
        }
    }

    function appendGvfs(listing: string): void {
        const runtime = Quickshell.env("XDG_RUNTIME_DIR") || "";
        const gvfs = runtime ? `${runtime}/gvfs` : "";
        const lines = (listing || "").split("\n").map(s => s.trim()).filter(s => s.length > 0);
        let next = (devices || []).slice().filter(d => d.kind !== "network");
        if (!gvfs || !lines.length) {
            devices = next;
            return;
        }
        for (let i = 0; i < lines.length; i++) {
            const name = lines[i];
            const path = gvfs + "/" + name;
            let pretty = name;
            const m = name.match(/server=([^,]+).*share=([^,]+)/);
            if (m)
                pretty = `${m[2]} @ ${m[1]}`;
            next.push({
                id: "net:" + name,
                name: pretty,
                letter: "",
                subtitle: qsTr("网络位置"),
                path: path,
                icon: "cloud",
                kind: "network",
                size: "",
                sizeBytes: 0,
                usedBytes: 0,
                freeBytes: 0,
                usedPct: 0,
                removable: false,
                mounted: true,
                device: "",
                fstype: "gvfs"
            });
        }
        devices = next;
    }

    Process {
        id: lsblkProc
        // -b: bytes for SIZE/FSSIZE/FSUSED/FSAVAIL
        command: ["lsblk", "-b", "-J", "-o", "NAME,LABEL,PARTLABEL,SIZE,FSSIZE,FSUSED,FSAVAIL,FSUSE%,TYPE,MOUNTPOINT,MOUNTPOINTS,RM,HOTPLUG,FSTYPE"]
        stdout: StdioCollector {
            onStreamFinished: root.buildList(text)
        }
    }

    Process {
        id: gvfsProc
        command: ["bash", "-c", "d=\"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gvfs\"; [ -d \"$d\" ] && ls -1 \"$d\" 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: root.appendGvfs(text)
        }
    }

    Process {
        id: gioMountProc
        command: ["true"]
        stdout: StdioCollector {
            id: gioOut
        }
        stderr: StdioCollector {
            id: gioErr
        }
        onExited: code => {
            if (code === 0) {
                refreshTimer.okMsg = qsTr("已挂载：%1").arg(root.pendingName);
                refreshTimer.start();
            } else {
                root.mounting = false;
                root.mountStatus = qsTr("需要管理员权限");
                root.mountFinished(false, "need-auth:" + (gioErr.text || gioOut.text || ""), "");
            }
        }
    }

    Process {
        id: pkexecMountProc
        command: ["true"]
        stdout: StdioCollector {
            id: pkOut
        }
        stderr: StdioCollector {
            id: pkErr
        }
        onExited: code => {
            if (code === 0) {
                let path = (pkOut.text || "").trim().split("\n").filter(s => s.startsWith("/")).pop() || "";
                refreshTimer.okMsg = qsTr("已挂载：%1").arg(root.pendingName);
                refreshTimer.openPath = path;
                refreshTimer.start();
            } else {
                const err = (pkErr.text || pkOut.text || "").trim();
                root.finishMount(false, err.length ? err : qsTr("挂载失败或已取消"));
            }
        }
    }

    Timer {
        id: refreshTimer
        property string okMsg: ""
        property string openPath: ""
        interval: 600
        repeat: false
        onTriggered: {
            root.refresh();
            Qt.callLater(() => {
                let path = openPath || root.findMountedPath(root.pendingDevice);
                if (!path) {
                    const base = root.pendingDevice.split("/").pop();
                    path = "/mnt/villode-" + base;
                }
                root.finishMount(true, okMsg, path);
                openPath = "";
            });
        }
    }

    Timer {
        interval: 8000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: refresh()
}
