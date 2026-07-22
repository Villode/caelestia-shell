pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.Services
import qs.utils

Singleton {
    id: root

    // [{ id, preview, isImage, mime, pinned }] newest first among unpinned; pinned first overall
    property var entries: []
    property var pinnedIds: []
    property bool loading: false
    property string filter: ""
    property string statusText: ""

    readonly property string pinsPath: `${Paths.cache}/clipboard-pins.json`

    readonly property var filteredEntries: {
        const q = filter.trim().toLowerCase();
        const list = entries;
        if (!q)
            return list;
        return list.filter(e => (e.preview || "").toLowerCase().includes(q) || (e.mime || "").toLowerCase().includes(q));
    }

    function isPinned(entryId: string): bool {
        return pinnedIds.indexOf(entryId) >= 0;
    }

    function togglePin(entryId: string): void {
        if (!entryId)
            return;
        const idx = pinnedIds.indexOf(entryId);
        let next;
        if (idx >= 0) {
            next = pinnedIds.slice();
            next.splice(idx, 1);
        } else {
            // Newest pin first among pins
            next = [entryId].concat(pinnedIds.filter(id => id !== entryId));
        }
        pinnedIds = next;
        savePins();
        reorderEntries();
    }

    function pin(entryId: string): void {
        if (!entryId || isPinned(entryId))
            return;
        pinnedIds = [entryId].concat(pinnedIds.filter(id => id !== entryId));
        savePins();
        reorderEntries();
    }

    function unpin(entryId: string): void {
        if (!entryId || !isPinned(entryId))
            return;
        pinnedIds = pinnedIds.filter(id => id !== entryId);
        savePins();
        reorderEntries();
    }

    function reorderEntries(): void {
        if (!entries || entries.length === 0)
            return;
        const pinOrder = {};
        for (let i = 0; i < pinnedIds.length; i++)
            pinOrder[pinnedIds[i]] = i;
        const withFlags = entries.map(e => ({
                id: e.id,
                preview: e.preview,
                isImage: e.isImage,
                mime: e.mime,
                pinned: pinOrder[e.id] !== undefined
            }));
        withFlags.sort((a, b) => {
            if (a.pinned !== b.pinned)
                return a.pinned ? -1 : 1;
            if (a.pinned && b.pinned)
                return pinOrder[a.id] - pinOrder[b.id];
            return 0; // keep relative order among unpinned (already newest-first from cliphist)
        });
        // Preserve unpinned relative order: stable sort by original index
        // Rebuild: pinned (by pinOrder) then unpinned in original order
        const byId = {};
        for (const e of entries)
            byId[e.id] = e;
        const pinned = [];
        for (const id of pinnedIds) {
            if (byId[id]) {
                const e = byId[id];
                pinned.push({
                    id: e.id,
                    preview: e.preview,
                    isImage: e.isImage,
                    mime: e.mime,
                    pinned: true
                });
            }
        }
        const unpinned = [];
        for (const e of entries) {
            if (pinOrder[e.id] === undefined) {
                unpinned.push({
                    id: e.id,
                    preview: e.preview,
                    isImage: e.isImage,
                    mime: e.mime,
                    pinned: false
                });
            }
        }
        entries = pinned.concat(unpinned);
    }

    function savePins(): void {
        pinFile.setText(JSON.stringify({
                ids: pinnedIds
            }));
    }

    function loadPins(): void {
        pinFile.reload();
    }

    function refresh(): void {
        if (listProc.running)
            return;
        loading = true;
        listProc.running = true;
    }

    function clearFilter(): void {
        filter = "";
    }

    function copyEntry(entryId: string): void {
        if (!entryId)
            return;
        Quickshell.execDetached(["sh", "-c", "cliphist decode \"$1\" | wl-copy", "sh", entryId]);
        try {
            Toaster.toast(qsTr("已复制"), qsTr("内容已放入系统剪切板"), "content_paste", Toast.Success, 1800);
        } catch (e) {}
    }

    function deleteEntry(entryId: string): void {
        if (!entryId)
            return;
        if (isPinned(entryId))
            unpin(entryId);
        Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" | cliphist delete", "sh", entryId]);
        entries = entries.filter(e => e.id !== entryId);
        Qt.callLater(refresh);
    }

    function wipe(): void {
        // Keep pinned ids in state file but entries will drop; clear pins too for wipe
        pinnedIds = [];
        savePins();
        wipeProc.running = true;
    }

    function ensureWatcher(): void {
        if (!GlobalConfig.utilities.clipboard.watchClipboard)
            return;
        if (watchProc.running)
            return;
        watchProc.running = true;
    }

    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", Paths.cache]);
        loadPins();
        ensureWatcher();
        refresh();
    }

    FileView {
        id: pinFile

        path: root.pinsPath
        // Create empty pins on first write failure
        onLoaded: {
            try {
                const data = JSON.parse(text());
                const ids = Array.isArray(data?.ids) ? data.ids.map(String) : [];
                root.pinnedIds = ids;
                root.reorderEntries();
            } catch (e) {
                root.pinnedIds = [];
            }
        }
        onLoadFailed: () => {
            root.pinnedIds = [];
            // Seed empty pins file so next reload is quiet.
            root.savePins();
        }
    }

    Process {
        id: listProc

        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                const maxItems = GlobalConfig.utilities.clipboard.maxItems;
                const maxPreview = GlobalConfig.utilities.clipboard.maxPreviewChars;
                const lines = text.split("\n").filter(l => l.length > 0);
                const out = [];
                for (let i = 0; i < lines.length && out.length < maxItems; i++) {
                    const line = lines[i];
                    const tab = line.indexOf("\t");
                    if (tab < 0)
                        continue;
                    const id = line.slice(0, tab).trim();
                    let preview = line.slice(tab + 1);
                    const isImage = /\[\[?\s*binary data/i.test(preview) || /\bimage\//i.test(preview);
                    let mime = "";
                    if (isImage) {
                        const m = preview.match(/image\/[a-z0-9.+-]+/i);
                        mime = m ? m[0] : "image/*";
                        preview = qsTr("图片");
                    } else {
                        preview = preview.replace(/\s+/g, " ").trim();
                        if (preview.length > maxPreview)
                            preview = preview.slice(0, maxPreview) + "…";
                    }
                    out.push({
                        id: id,
                        preview: preview,
                        isImage: isImage,
                        mime: mime,
                        pinned: root.pinnedIds.indexOf(id) >= 0
                    });
                }
                root.entries = out;
                root.reorderEntries();
                root.statusText = "";
            }
        }
        onExited: code => {
            root.loading = false;
            if (code !== 0 && root.entries.length === 0)
                root.statusText = qsTr("无法读取剪切板历史（需要 cliphist）");
        }
    }

    Process {
        id: wipeProc

        command: ["cliphist", "wipe"]
        onExited: () => {
            root.entries = [];
            root.refresh();
            try {
                Toaster.toast(qsTr("已清空"), qsTr("剪切板历史已清除"), "delete_sweep", Toast.Info, 2000);
            } catch (e) {}
        }
    }

    Process {
        id: watchProc

        command: ["sh", "-c", "wl-paste --watch cliphist store"]
        running: false
        onExited: () => {
            if (GlobalConfig.utilities.clipboard.watchClipboard)
                Qt.callLater(() => {
                    if (!watchProc.running)
                        watchProc.running = true;
                });
        }
    }
}
