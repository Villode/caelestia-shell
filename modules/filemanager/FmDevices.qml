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

    function mountDevice(device: string, name: string, uri: string): void {
        // device: /dev/sdX for block, or empty for MTP; uri: mtp://... for phone
        const target = (uri && uri.length) ? uri : device;
        if (!target || mounting)
            return;
        mounting = true;
        mountStatus = qsTr("正在挂载…");
        pendingDevice = device || uri || target;
        pendingName = name || target;
        gioMountProc.running = false;
        // Block devices: gio mount -d /dev/...
        // MTP/phone: gio mount mtp://...
        if (uri && uri.length)
            gioMountProc.command = ["gio", "mount", uri];
        else
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

    function isPhoneScheme(name: string): bool {
        const n = (name || "").toLowerCase();
        return n.startsWith("mtp:") || n.startsWith("gphoto2:") || n.startsWith("afc:") || n.indexOf("mtp:host=") === 0 || n.indexOf("gphoto2:host=") === 0;
    }

    function appendGvfs(listing: string): void {
        const runtime = Quickshell.env("XDG_RUNTIME_DIR") || "";
        const gvfs = runtime ? `${runtime}/gvfs` : "";
        const lines = (listing || "").split("\n").map(s => s.trim()).filter(s => s.length > 0);
        // Drop previous virtual mounts; re-add from listing + volume probe
        let next = (devices || []).slice().filter(d => d.kind !== "network" && d.kind !== "phone" && d.kind !== "mtp");
        const seenPaths = {};
        for (let i = 0; i < next.length; i++) {
            if (next[i].path)
                seenPaths[next[i].path] = true;
        }
        if (gvfs && lines.length) {
            for (let i = 0; i < lines.length; i++) {
                const name = lines[i];
                const path = gvfs + "/" + name;
                if (seenPaths[path])
                    continue;
                seenPaths[path] = true;
                let pretty = name;
                const m = name.match(/server=([^,]+).*share=([^,]+)/);
                if (m)
                    pretty = `${m[2]} @ ${m[1]}`;
                else if (name.indexOf("mtp:host=") === 0) {
                    pretty = name.replace(/^mtp:host=/, "").replace(/_/g, " ");
                }
                const phone = isPhoneScheme(name);
                next.push({
                    id: (phone ? "phone:" : "net:") + name,
                    name: pretty,
                    letter: "",
                    subtitle: phone ? qsTr("手机 · MTP（已连接）") : qsTr("网络位置"),
                    path: path,
                    icon: phone ? "smartphone" : "cloud",
                    kind: phone ? "phone" : "network",
                    size: "",
                    sizeBytes: 0,
                    usedBytes: 0,
                    freeBytes: 0,
                    usedPct: 0,
                    removable: phone,
                    mounted: true,
                    device: "",
                    uri: phone ? ("mtp://" + name.replace(/^mtp:host=/, "") + "/") : "",
                    fstype: phone ? "mtp" : "gvfs"
                });
            }
        }
        devices = next;
        // Probe unmounted MTP / virtual volumes (phone file transfer)
        volProc.running = false;
        volProc.running = true;
    }

    function appendVolumes(jsonText: string): void {
        let vols = [];
        try {
            vols = JSON.parse(jsonText || "[]");
        } catch (e) {
            return;
        }
        if (!vols || !vols.length)
            return;
        let next = (devices || []).slice();
        const seen = {};
        for (let i = 0; i < next.length; i++) {
            if (next[i].path)
                seen["p:" + next[i].path] = true;
            if (next[i].uri)
                seen["u:" + next[i].uri] = true;
            if (next[i].id)
                seen["i:" + next[i].id] = true;
        }
        for (let i = 0; i < vols.length; i++) {
            const v = vols[i];
            if (!v)
                continue;
            const uri = v.uri || "";
            const path = v.path || "";
            if (path && seen["p:" + path])
                continue;
            if (uri && seen["u:" + uri])
                continue;
            const id = v.id || ("vol:" + (uri || path || i));
            if (seen["i:" + id])
                continue;
            const kind = v.kind || "phone";
            next.push({
                id: id,
                name: v.name || qsTr("移动设备"),
                letter: "",
                subtitle: v.mounted ? (v.subtitle || qsTr("已连接")) : qsTr("未挂载 · 点击挂载"),
                path: path,
                icon: kind === "phone" ? "smartphone" : "cloud",
                kind: kind,
                size: "",
                sizeBytes: 0,
                usedBytes: 0,
                freeBytes: 0,
                usedPct: 0,
                removable: true,
                mounted: !!v.mounted && !!path,
                device: v.device || "",
                uri: uri,
                fstype: v.fstype || "mtp"
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
        id: volProc
        // List MTP/gphoto/afc volumes via GIO; fuse path often only on GDaemonMount
        command: [
            "python3", "-c",
            "import json,os,sys\n" +
            "try:\n import gi\n gi.require_version('Gio','2.0')\n from gi.repository import Gio\nexcept Exception:\n print('[]'); raise SystemExit(0)\n" +
            "vm=Gio.VolumeMonitor.get()\n" +
            "runtime=os.environ.get('XDG_RUNTIME_DIR') or ('/run/user/%d'%os.getuid())\n" +
            "gvfs=os.path.join(runtime,'gvfs')\n" +
            "uri_to_path={}\n" +
            "for m in vm.get_mounts():\n" +
            " r=m.get_root()\n" +
            " if not r: continue\n" +
            " u=r.get_uri() or ''\n" +
            " p=r.get_path() or ''\n" +
            " if u and p: uri_to_path[u.rstrip('/')]=p\n" +
            " # also index host-style fuse dir\n" +
            "if os.path.isdir(gvfs):\n" +
            " for name in os.listdir(gvfs):\n" +
            "  p=os.path.join(gvfs,name)\n" +
            "  if name.startswith('mtp:host='):\n" +
            "   host=name[len('mtp:host='):]\n" +
            "   uri_to_path['mtp://'+host]=p\n" +
            "   uri_to_path['mtp://'+host+'/']=p\n" +
            "out=[]\n" +
            "for v in vm.get_volumes():\n" +
            " root=v.get_activation_root()\n" +
            " uri=root.get_uri() if root else ''\n" +
            " if not uri: continue\n" +
            " scheme=uri.split(':',1)[0].lower()\n" +
            " if scheme not in ('mtp','gphoto2','afc','smb','sftp','dav','nfs'): continue\n" +
            " key=uri.rstrip('/')\n" +
            " path=uri_to_path.get(key) or uri_to_path.get(key+'/') or ''\n" +
            " mounted=bool(v.get_mount()) or bool(path)\n" +
            " if not path and mounted:\n" +
            "  m=v.get_mount()\n" +
            "  if m and m.get_root(): path=m.get_root().get_path() or ''\n" +
            " kind='phone' if scheme in ('mtp','gphoto2','afc') else 'network'\n" +
            " out.append({'id':'vol:'+uri,'name':v.get_name() or uri,'uri':uri,'path':path or '','mounted':mounted,'device':v.get_identifier(Gio.VOLUME_IDENTIFIER_KIND_UNIX_DEVICE) or '','kind':kind,'fstype':scheme,'subtitle':('已连接' if mounted else '未挂载')})\n" +
            "print(json.dumps(out,ensure_ascii=False))"
        ]
        stdout: StdioCollector {
            onStreamFinished: root.appendVolumes(text)
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
                const err = (gioErr.text || gioOut.text || "").trim();
                // MTP rarely needs pkexec; surface real error
                const needsAuth = err.indexOf("Permission") >= 0 || err.indexOf("授权") >= 0 || err.indexOf("polkit") >= 0;
                root.mounting = false;
                if (needsAuth && root.pendingDevice && root.pendingDevice.indexOf("/dev/") === 0) {
                    root.mountStatus = qsTr("需要管理员权限");
                    root.mountFinished(false, "need-auth:" + err, "");
                } else {
                    root.finishMount(false, err.length ? err : qsTr("挂载失败（请确认手机已选「文件传输/MTP」）"));
                }
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

    function findPhonePath(uri: string): string {
        const list = devices || [];
        for (let i = 0; i < list.length; i++) {
            const d = list[i];
            if ((d.kind === "phone" || d.kind === "mtp") && d.path) {
                if (!uri || d.uri === uri || (d.device && d.device === root.pendingDevice))
                    return d.path;
            }
        }
        return "";
    }

    Timer {
        id: refreshTimer
        property string okMsg: ""
        property string openPath: ""
        interval: 800
        repeat: false
        onTriggered: {
            root.refresh();
            // second pass after gvfs/volume probe finishes
            Qt.callLater(() => {
                let path = openPath || root.findMountedPath(root.pendingDevice) || root.findPhonePath(root.pendingDevice);
                if (!path && root.pendingDevice && root.pendingDevice.indexOf("/dev/") === 0) {
                    const base = root.pendingDevice.split("/").pop();
                    path = "/mnt/villode-" + base;
                }
                root.finishMount(true, okMsg, path || "");
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
