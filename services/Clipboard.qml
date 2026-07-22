pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.Services

Singleton {
    id: root

    // [{ id, preview, isImage, mime }] newest first
    property var entries: []
    property bool loading: false
    property string filter: ""
    property string statusText: ""

    readonly property var filteredEntries: {
        const q = filter.trim().toLowerCase();
        if (!q)
            return entries;
        return entries.filter(e => (e.preview || "").toLowerCase().includes(q) || (e.mime || "").toLowerCase().includes(q));
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
        Toaster.toast(qsTr("已复制"), qsTr("内容已放入系统剪切板"), "content_paste", Toast.Success, 1800);
    }

    function deleteEntry(entryId: string): void {
        if (!entryId)
            return;
        // cliphist delete reads id from stdin
        Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" | cliphist delete", "sh", entryId]);
        // Optimistic remove
        entries = entries.filter(e => e.id !== entryId);
        Qt.callLater(refresh);
    }

    function wipe(): void {
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
        ensureWatcher();
        refresh();
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
                        mime: mime
                    });
                }
                root.entries = out;
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
            Toaster.toast(qsTr("已清空"), qsTr("剪切板历史已清除"), "delete_sweep", Toast.Info, 2000);
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
