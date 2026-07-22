pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.Models
import qs.components
import qs.components.controls
import qs.components.effects
import qs.components.images
import qs.services
import qs.utils

Item {
    id: root

    required property var state
    required property var actions

    // Set by ManagerWindow for FmDrag hit-testing
    property string windowId: ""

    // Min tile size; actual itemWidth grows so columns fill the view (no empty right column gap)
    readonly property int minItemWidth: 103
    readonly property int gridGap: Tokens.spacing.small
    readonly property int gridColumns: {
        const w = grid.width;
        if (w <= 0)
            return 1;
        return Math.max(1, Math.floor((w + gridGap) / (minItemWidth + gridGap)));
    }
    readonly property real itemWidth: {
        const w = grid.width;
        if (w <= 0)
            return minItemWidth;
        return Math.max(minItemWidth, (w / gridColumns) - gridGap);
    }
    readonly property bool isGrid: state.viewMode !== "list"

    signal contextMenuRequested(real x, real y, string path, bool isDir, string name)

    function clearSelection(): void {
        grid.currentIndex = -1;
        list.currentIndex = -1;
        root.state.setSelection([]);
    }

    function currentPath(): string {
        const item = isGrid ? grid.currentItem : list.currentItem;
        return item?.modelData?.path ?? "";
    }

    function currentMeta(): var {
        const item = isGrid ? grid.currentItem : list.currentItem;
        const d = item?.modelData;
        if (d)
            return {
                path: d.path || "",
                name: d.name || "",
                isDir: !!d.isDir,
                isImage: !!d.isImage
            };
        // Fall back to first selected path without type info
        if (root.state.selection.length === 1) {
            const p = root.state.selection[0];
            return {
                path: p,
                name: p.split("/").pop() || p,
                isDir: false,
                isImage: false
            };
        }
        return null;
    }

    function selectHit(hit: var, ctrl: bool): void {
        if (!hit?.modelData)
            return;
        if (isGrid)
            grid.currentIndex = hit.index;
        else
            list.currentIndex = hit.index;
        if (ctrl)
            root.state.toggleSelection(hit.modelData.path);
        else
            root.state.setSelection([hit.modelData.path]);
    }

    function activateHit(hit: var): void {
        if (!hit?.modelData)
            return;
        root.actions.openEntry(hit.modelData.isDir, hit.modelData.name, hit.modelData.path);
    }

    function pathAtViewPos(vx: real, vy: real): string {
        // vx/vy in coordinates of grid/list content viewport (same as input MouseArea)
        const flick = root.isGrid ? grid : list;
        const hit = flick.itemAt(vx + flick.contentX, vy + flick.contentY);
        if (hit?.modelData?.isDir)
            return hit.modelData.path;
        return root.state.cwdPath();
    }

    property string dropHoverPath: ""
    property bool dropHoverActive: false
    property bool dragVisualActive: false
    // Snapshot of selection while this window is drag source (Windows freezes selection)
    property var frozenSelection: []

    // Bump path through empty so FileSystemModel.setPath reloads same dir
    property int fsPathTick: 0
    property string fsPathOverride: ""

    Connections {
        target: root.state
        function onRefreshNonceChanged(): void {
            const p = root.state.isThisPC ? "" : root.state.cwdPath();
            // Force setPath: empty first, then real path on next tick
            root.fsPathOverride = "__refresh__";
            root.fsPathTick = root.fsPathTick + 1;
            Qt.callLater(() => {
                root.fsPathOverride = "";
                root.fsPathTick = root.fsPathTick + 1;
                if (p && p.length)
                    root.reloadMtimes(p);
            });
        }
        function onSortByChanged(): void { root.scheduleSortRebuild(); }
        function onSortReverseChanged(): void { root.scheduleSortRebuild(); }
        function onFoldersFirstChanged(): void { root.scheduleSortRebuild(); }
    }

    function humanSize(bytes: real): string {
        if (bytes < 1024)
            return `${Math.round(bytes)} B`;
        const units = ["KB", "MB", "GB", "TB"];
        let v = bytes / 1024;
        let i = 0;
        while (v >= 1024 && i < units.length - 1) {
            v /= 1024;
            i++;
        }
        return `${v.toFixed(v >= 10 ? 0 : 1)} ${units[i]}`;
    }

    function iconFor(file: var): string {
        if (!file)
            return "inode-directory";
        if (file.isImage)
            return ""; // use path
        if (!file.isDir)
            return Quickshell.iconPath(file.mimeType.replace("/", "-"), "application-x-zerosize");
        if (root.state.cwd.length === 1) {
            const special = {
                "Desktop": "desktop", "桌面": "desktop",
                "Documents": "documents", "文档": "documents",
                "Downloads": "download", "下载": "download",
                "Music": "music", "音乐": "music",
                "Pictures": "pictures", "图片": "pictures",
                "Public": "publicshare", "公共": "publicshare",
                "Templates": "templates", "模板": "templates",
                "Videos": "videos", "视频": "videos"
            };
            const key = special[file.name];
            if (key)
                return Quickshell.iconPath(`folder-${key}`);
        }
        return Quickshell.iconPath("inode-directory");
    }

    // name -> "YYYY-MM-DD HH:MM" for list view
    property var mtimeMap: ({})

    function mtimeFor(name: string): string {
        return (mtimeMap && mtimeMap[name]) || "";
    }

    function reloadMtimes(dirPath: string): void {
        mtimeMap = {};
        if (!dirPath || dirPath.length === 0)
            return;
        mtimeProc.running = false;
        mtimeProc.command = ["find", dirPath, "-maxdepth", "1", "-mindepth", "1", "-printf", "%f\\t%TY-%Tm-%Td %TH:%TM\\n"];
        mtimeProc.running = true;
    }

    // Sorted view of FileSystemModel (name/size/type/mtime)
    ListModel {
        id: sortedModel
    }

    property int sortEpoch: 0

    function entryTypeKey(e: var): string {
        if (!e)
            return "";
        if (e.isDir)
            return "0_dir";
        const mime = (e.mimeType || "").toLowerCase();
        const suf = (e.suffix || "").toLowerCase();
        if (mime.length)
            return "1_" + mime;
        return "2_" + suf;
    }

    function naturalKey(s: string): string {
        // Lowercase for case-insensitive compare
        return (s || "").toLocaleLowerCase();
    }

    function mtimeKey(name: string): string {
        // reloadMtimes fills "YYYY-MM-DD HH:MM" — lexicographic works
        return root.mtimeFor(name) || "";
    }

    function compareEntries(a: var, b: var): int {
        const foldersFirst = root.state.foldersFirst;
        if (foldersFirst && !!a.isDir !== !!b.isDir)
            return a.isDir ? -1 : 1;

        const rev = root.state.sortReverse;
        const by = root.state.sortBy || "name";
        let cmp = 0;

        if (by === "size") {
            const sa = a.isDir ? -1 : (a.size || 0);
            const sb = b.isDir ? -1 : (b.size || 0);
            cmp = sa < sb ? -1 : (sa > sb ? 1 : 0);
        } else if (by === "type") {
            const ta = entryTypeKey(a);
            const tb = entryTypeKey(b);
            cmp = ta < tb ? -1 : (ta > tb ? 1 : 0);
            if (cmp === 0) {
                const na = naturalKey(a.name);
                const nb = naturalKey(b.name);
                cmp = na < nb ? -1 : (na > nb ? 1 : 0);
            }
        } else if (by === "mtime") {
            const ma = mtimeKey(a.name);
            const mb = mtimeKey(b.name);
            cmp = ma < mb ? -1 : (ma > mb ? 1 : 0);
            if (cmp === 0) {
                const na = naturalKey(a.name);
                const nb = naturalKey(b.name);
                cmp = na < nb ? -1 : (na > nb ? 1 : 0);
            }
        } else {
            // name
            const na = naturalKey(a.name);
            const nb = naturalKey(b.name);
            cmp = na < nb ? -1 : (na > nb ? 1 : 0);
        }

        if (cmp === 0)
            return 0;
        return rev ? -cmp : cmp;
    }

    function rebuildSorted(): void {
        const items = [];
        const seen = ({});
        try {
            // At $HOME: one folder per ZH/EN place pair. At place root: merge twin dir.
            const atHome = !root.state.isThisPC && root.state.cwd.length === 1 && root.state.cwd[0] === "Home";
            const atPlaceRoot = root.state.isAtPlaceRoot && root.state.isAtPlaceRoot();

            function pushEntry(e) {
                if (!e)
                    return;
                const name = e.name || "";
                if (!name.length)
                    return;
                if (atHome && e.isDir && root.state.isHiddenPlaceSibling(name))
                    return;
                if (seen[name])
                    return;
                seen[name] = true;
                items.push(e);
            }

            const entries = fsModel.entries;
            const n = entries ? entries.length : 0;
            for (let i = 0; i < n; i++)
                pushEntry(entries[i]);

            if (atPlaceRoot) {
                try {
                    const sib = fsModelSibling.entries;
                    const sn = sib ? sib.length : 0;
                    for (let i = 0; i < sn; i++)
                        pushEntry(sib[i]);
                } catch (e2) {}
            }
        } catch (err) {
            // leave empty
        }

        items.sort((a, b) => root.compareEntries(a, b));

        sortedModel.clear();
        for (let j = 0; j < items.length; j++) {
            const e = items[j];
            sortedModel.append({
                path: e.path || "",
                name: e.name || "",
                isDir: !!e.isDir,
                isImage: !!e.isImage,
                size: e.size || 0,
                mimeType: e.mimeType || "",
                suffix: e.suffix || "",
                baseName: e.baseName || ""
            });
        }
        root.sortEpoch = root.sortEpoch + 1;
    }

    Timer {
        id: sortRebuildTimer
        interval: 16
        repeat: false
        onTriggered: root.rebuildSorted()
    }

    function scheduleSortRebuild(): void {
        sortRebuildTimer.restart();
    }

    FileSystemModel {
        id: fsModel
        path: {
            const _tick = root.fsPathTick;
            if (root.state.isThisPC)
                return "";
            if (root.fsPathOverride === "__refresh__")
                return "";
            return root.state.cwdPath();
        }
        showHidden: root.state.showHidden
        // Read nameFilter in this binding so clear/search always re-evaluates
        nameFilters: {
            const _ = root.state.nameFilter;
            const scope = root.state.searchScope;
            if (scope === "global")
                return ["*"];
            return root.state.nameFiltersActive;
        }
        onPathChanged: {
            grid.currentIndex = -1;
            list.currentIndex = -1;
            if (!root.state.isThisPC)
                root.state.selection = [];
            if (path && path.length)
                root.reloadMtimes(path);
            else {
                root.mtimeMap = {};
                root.scheduleSortRebuild();
            }
        }
        onEntriesChanged: root.scheduleSortRebuild()
        onNameFiltersChanged: root.scheduleSortRebuild()
        onShowHiddenChanged: root.scheduleSortRebuild()
        Component.onCompleted: {
            if (path && path.length)
                root.reloadMtimes(path);
            root.scheduleSortRebuild();
        }
    }

    // Twin of current place (e.g. ~/图片 while cwd is ~/Pictures) so side-bar 图片 shows both.
    FileSystemModel {
        id: fsModelSibling
        path: {
            const _tick = root.fsPathTick;
            if (root.state.isThisPC)
                return "";
            if (root.fsPathOverride === "__refresh__")
                return "";
            if (!(root.state.isAtPlaceRoot && root.state.isAtPlaceRoot()))
                return "";
            return root.state.placeSiblingPath() || "";
        }
        showHidden: root.state.showHidden
        nameFilters: {
            const _ = root.state.nameFilter;
            const scope = root.state.searchScope;
            if (scope === "global")
                return ["*"];
            return root.state.nameFiltersActive;
        }
        onPathChanged: root.scheduleSortRebuild()
        onEntriesChanged: root.scheduleSortRebuild()
        onNameFiltersChanged: root.scheduleSortRebuild()
        onShowHiddenChanged: root.scheduleSortRebuild()
    }

    Process {
        id: mtimeProc
        command: ["true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                const lines = text.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i];
                    if (!line.length)
                        continue;
                    const tab = line.indexOf("\t");
                    if (tab < 0)
                        continue;
                    map[line.slice(0, tab)] = line.slice(tab + 1);
                }
                root.mtimeMap = map;
                root.scheduleSortRebuild();
            }
        }
    }

    StyledRect {
        anchors.fill: parent
        color: Colours.tPalette.m3surfaceContainer
        layer.enabled: true
        layer.effect: Mask {
            maskSource: mask
            maskInverted: true
        }
    }

    Item {
        id: mask
        anchors.fill: parent
        layer.enabled: true
        visible: false
        Rectangle {
            anchors.fill: parent
            anchors.margins: Tokens.padding.extraSmall
            radius: Tokens.rounding.medium
        }
    }

    Loader {
        asynchronous: true
        anchors.centerIn: parent
        opacity: (grid.count === 0 && list.count === 0) ? 1 : 0
        active: opacity > 0
        z: 1
        sourceComponent: ColumnLayout {
            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                text: "scan_delete"
                color: Colours.palette.m3outline
                fontStyle: Tokens.font.icon.builders.extraLarge.scale(2).weight(Font.Medium).build()
            }
            StyledText {
                text: (root.state.nameFilter && root.state.nameFilter.length)
                    ? qsTr("无搜索结果「%1」").arg(root.state.nameFilter)
                    : qsTr("此文件夹为空")
                color: Colours.palette.m3outline
                font: Tokens.font.body.builders.large.weight(Font.Medium).build()
            }
        }
        Behavior on opacity {
            Anim { type: Anim.DefaultEffects }
        }
    }

    // —— Grid ——
    GridView {
        id: grid
        anchors.fill: parent
        anchors.margins: Tokens.padding.extraSmall + Tokens.padding.medium
        visible: root.isGrid
        enabled: root.isGrid
        // Fill full width: cellWidth * columns ≈ available width
        cellWidth: width > 0 ? width / root.gridColumns : (root.minItemWidth + root.gridGap)
        cellHeight: root.itemWidth + Tokens.spacing.large + Tokens.padding.medium * 2 + 1
        clip: true
        focus: root.isGrid
        currentIndex: -1
        keyNavigationEnabled: true
        interactive: true
        model: sortedModel
        delegate: GridEntry {}

        Keys.onEscapePressed: root.clearSelection()
        Keys.onReturnPressed: {
            if (currentItem?.modelData)
                root.activateHit(currentItem);
        }
        Keys.onEnterPressed: {
            if (currentItem?.modelData)
                root.activateHit(currentItem);
        }
        Keys.onPressed: event => root.handleKeys(event)

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: grid
        }
    }

    // —— List ——
    ListView {
        id: list
        anchors.fill: parent
        anchors.margins: Tokens.padding.extraSmall + Tokens.padding.medium
        visible: !root.isGrid
        enabled: !root.isGrid
        clip: true
        focus: !root.isGrid
        currentIndex: -1
        keyNavigationEnabled: true
        spacing: 2
        model: sortedModel
        delegate: ListEntry {}

        Keys.onEscapePressed: root.clearSelection()
        Keys.onReturnPressed: {
            if (currentItem?.modelData)
                root.activateHit(currentItem);
        }
        Keys.onEnterPressed: {
            if (currentItem?.modelData)
                root.activateHit(currentItem);
        }
        Keys.onPressed: event => root.handleKeys(event)

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: list
        }
    }

    function handleKeys(event: var): void {
        if (event.modifiers & Qt.ControlModifier) {
            if (event.key === Qt.Key_C) {
                root.actions.copy(root.state.selection.length ? root.state.selection : (currentPath() ? [currentPath()] : []));
                event.accepted = true;
            } else if (event.key === Qt.Key_X) {
                root.actions.cut(root.state.selection.length ? root.state.selection : (currentPath() ? [currentPath()] : []));
                event.accepted = true;
            } else if (event.key === Qt.Key_V) {
                root.actions.paste();
                event.accepted = true;
            } else if ((event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_N) {
                if (typeof root.actions.requestMkdir === "function")
                    root.actions.requestMkdir();
                else
                    root.actions.mkdir("");
                event.accepted = true;
            }
        } else if (event.key === Qt.Key_F5) {
            root.state.bumpRefresh();
            root.state.statusText = qsTr("已刷新");
            event.accepted = true;
        } else if (event.key === Qt.Key_F2) {
            const p = root.state.selection.length === 1 ? root.state.selection[0] : currentPath();
            if (p && typeof root.actions.requestRename === "function")
                root.actions.requestRename(p);
            event.accepted = true;
        } else if (event.key === Qt.Key_Delete) {
            const paths = root.state.selection.length ? root.state.selection : (currentPath() ? [currentPath()] : []);
            if (!paths.length) {
                event.accepted = true;
                return;
            }
            // Shift+Delete → permanent delete with confirm; Delete → trash with confirm
            if (event.modifiers & Qt.ShiftModifier) {
                if (typeof root.actions.requestDelete === "function")
                    root.actions.requestDelete(paths);
                else
                    root.actions.deletePermanent(paths);
            } else {
                if (typeof root.actions.requestTrash === "function")
                    root.actions.requestTrash(paths);
                else
                    root.actions.trash(paths);
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_Backspace) {
            root.state.popDir();
            event.accepted = true;
        }
    }

    // On-cursor ghost — local mouse-follow (smooth). Cross-window uses FmDrag singleton.
    Item {
        id: dragProxy
        width: ghostCard.implicitWidth
        height: ghostCard.implicitHeight
        // Payload-only; single screen-space ghost lives in FileManager overlay
        visible: false
        z: 200
        opacity: visible ? 0.92 : 0
        property string path: ""
        property string name: ""
        property var paths: []
        property bool isDir: false
        property bool isImage: false
        property string iconSource: ""
        property real hotX: 20
        property real hotY: 20
        readonly property int count: (paths && paths.length) ? paths.length : (path ? 1 : 0)

        function moveToInputLocal(mx, my) {
            const p = input.mapToItem(dragProxy.parent, mx, my);
            dragProxy.x = p.x - hotX;
            dragProxy.y = p.y - hotY;
        }

        function clear() {
            path = "";
            name = "";
            paths = [];
            iconSource = "";
            isDir = false;
            isImage = false;
        }

        StyledRect {
            id: ghostCard
            anchors.left: parent.left
            anchors.top: parent.top
            implicitWidth: Math.min(220, ghostRow.implicitWidth + Tokens.padding.medium * 2)
            implicitHeight: ghostRow.implicitHeight + Tokens.padding.small * 2
            radius: Tokens.rounding.large
            color: Colours.palette.m3surfaceContainerHigh
            border.width: 1
            border.color: Colours.palette.m3outlineVariant

            RowLayout {
                id: ghostRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.padding.small
                spacing: Tokens.spacing.small

                CachingIconImage {
                    id: ghostIcon
                    implicitSize: 36
                    source: dragProxy.iconSource
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        text: dragProxy.name
                        elide: Text.ElideMiddle
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                    }
                    StyledText {
                        visible: dragProxy.count > 1
                        text: qsTr("%1 项").arg(dragProxy.count)
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.builders.small.scale(0.85).build()
                    }
                }
            }

            Rectangle {
                visible: dragProxy.count > 1
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: -6
                width: badgeTxt.implicitWidth + 10
                height: badgeTxt.implicitHeight + 4
                radius: height / 2
                color: Colours.palette.m3primary
                StyledText {
                    id: badgeTxt
                    anchors.centerIn: parent
                    text: String(dragProxy.count)
                    color: Colours.palette.m3onPrimary
                    font: Tokens.font.body.builders.small.scale(0.85).weight(Font.Bold).build()
                }
            }
        }
    }

    // Rubber-band multi-select (coords are local to `input` MouseArea)
    property bool marqueeActive: false
    property real marqueeX0: 0
    property real marqueeY0: 0
    property real marqueeX1: 0
    property real marqueeY1: 0

    // Keep marquee inside the content/input area only
    function clampMarqueeX(x: real): real {
        return Math.max(0, Math.min(x, Math.max(0, input.width)));
    }

    function clampMarqueeY(y: real): real {
        return Math.max(0, Math.min(y, Math.max(0, input.height)));
    }

    function setMarqueeCorner(which: string, x: real, y: real): void {
        const cx = clampMarqueeX(x);
        const cy = clampMarqueeY(y);
        if (which === "0") {
            marqueeX0 = cx;
            marqueeY0 = cy;
        } else {
            marqueeX1 = cx;
            marqueeY1 = cy;
        }
    }

    function rectsOverlap(ax, ay, aw, ah, bx, by, bw, bh) {
        return ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by;
    }

    function applyMarqueeSelection(): void {
        const flick = root.isGrid ? grid : list;
        const ox = Math.min(marqueeX0, marqueeX1);
        const oy = Math.min(marqueeY0, marqueeY1);
        const ow = Math.abs(marqueeX1 - marqueeX0);
        const oh = Math.abs(marqueeY1 - marqueeY0);
        if (ow < 2 && oh < 2)
            return;
        // overlay → content coordinates
        const rx = ox + flick.contentX;
        const ry = oy + flick.contentY;
        const paths = [];
        const n = flick.count;
        for (let i = 0; i < n; i++) {
            const it = flick.itemAtIndex(i);
            if (!it || !it.modelData)
                continue;
            if (rectsOverlap(rx, ry, ow, oh, it.x, it.y, it.width, it.height))
                paths.push(it.modelData.path);
        }
        root.state.setSelection(paths);
        if (paths.length === 1) {
            for (let j = 0; j < n; j++) {
                const it2 = flick.itemAtIndex(j);
                if (it2?.modelData?.path === paths[0]) {
                    if (root.isGrid)
                        grid.currentIndex = j;
                    else
                        list.currentIndex = j;
                    break;
                }
            }
        }
        root.state.statusText = paths.length ? qsTr("已选中 %1 项").arg(paths.length) : root.state.statusText;
    }


    // External / internal file drop: copy (default) or move (Qt.MoveAction)
    DropArea {
        id: fileDrop
        anchors.fill: parent
        anchors.margins: Tokens.padding.extraSmall + Tokens.padding.medium
        keys: ["text/uri-list", "text/plain"]
        z: 35

        onEntered: drag => {
            // Local ghost drag uses finishInternalDrag; skip DropArea for it
            if (root.dragVisualActive) {
                drag.accepted = false;
                return;
            }
            drag.accepted = drag.hasUrls || drag.hasText;
            if (drag.accepted) {
                root.dropHoverActive = true;
                const dest = root.pathAtViewPos(drag.x, drag.y);
                root.dropHoverPath = dest;
            }
        }
        onPositionChanged: drag => {
            if (!root.dropHoverActive)
                return;
            const dest = root.pathAtViewPos(drag.x, drag.y);
            if (dest !== root.dropHoverPath)
                root.dropHoverPath = dest;
        }
        onExited: {
            root.dropHoverActive = false;
            root.dropHoverPath = "";
        }
        onDropped: drop => {
            const dest = root.pathAtViewPos(drop.x, drop.y) || root.state.cwdPath();
            root.dropHoverActive = false;
            root.dropHoverPath = "";
            const n = root.actions.dropFromEvent(drop, dest);
            if (n > 0)
                drop.acceptProposedAction();
        }
    }

    // Subtle pane hint only while DnD active over this view (not a solid full-window frame)
    Rectangle {
        id: dropGlow
        anchors.fill: parent
        anchors.margins: Tokens.padding.extraSmall
        z: 34
        radius: Tokens.rounding.medium
        // Only show when drop target is current folder (not a subfolder — those highlight on the tile)
        visible: root.dropHoverActive && !root.dragVisualActive && FmDrag.active
            && (!FmDrag.pendingWindowId || !root.windowId || FmDrag.pendingWindowId === root.windowId)
            && root.dropHoverPath === root.state.cwdPath()
        color: Qt.alpha(Colours.palette.m3primary, 0.04)
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3primary, 0.35)
        opacity: visible ? 1 : 0
        Behavior on opacity { Anim { type: Anim.DefaultEffects } }
    }

    // Clip layer so the rubber-band never paints outside the file pane
    Item {
        id: marqueeClip
        anchors.fill: parent
        anchors.margins: Tokens.padding.extraSmall + Tokens.padding.medium
        z: 45
        clip: true

        Rectangle {
            id: marqueeRect
            visible: root.marqueeActive
            x: Math.min(root.marqueeX0, root.marqueeX1)
            y: Math.min(root.marqueeY0, root.marqueeY1)
            width: Math.abs(root.marqueeX1 - root.marqueeX0)
            height: Math.abs(root.marqueeY1 - root.marqueeY0)
            color: Qt.alpha(Colours.palette.m3primary, 0.16)
            border.width: 1
            border.color: Colours.palette.m3primary
            radius: 2
        }
    }



    // Authoritative screen cursor while dragging (do NOT use mapToGlobal — wrong on FloatingWindow)
    Timer {
        id: fmDragPoll
        interval: 16
        repeat: true
        running: root.dragVisualActive
        onTriggered: {
            if (!cursorPosProc.running)
                cursorPosProc.running = true;
        }
    }

    Process {
        id: cursorPosProc
        command: ["hyprctl", "cursorpos", "-j"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.dragVisualActive && !FmDrag.active)
                    return;
                try {
                    const pos = JSON.parse(text());
                    if (pos && pos.x !== undefined && pos.y !== undefined)
                        FmDrag.updateGlobal(Number(pos.x), Number(pos.y));
                } catch (e) {}
            }
        }
    }

    // Accept drops from another FM window via FmDrag (no Qt system DnD)
    Connections {
        target: FmDrag
        function onGlobalXChanged() { root._fmDragHoverTick(); }
        function onGlobalYChanged() { root._fmDragHoverTick(); }
        function onActiveChanged() {
            if (!FmDrag.active) {
                root.dragVisualActive = false;
                root.dropHoverActive = false;
                root.dropHoverPath = "";
                root.frozenSelection = [];
            } else {
                root._fmDragHoverTick();
            }
        }
        function onFinished(moved) {
            root.dragVisualActive = false;
            root.dropHoverActive = false;
            root.dropHoverPath = "";
            root.frozenSelection = [];
            if (moved > 0)
                root.state.statusText = qsTr("已移动 %1 项").arg(moved);
            else
                root.state.statusText = qsTr("已取消拖动");
        }
        function onCancelled() {
            root.dragVisualActive = false;
            root.dropHoverActive = false;
            root.dropHoverPath = "";
            root.frozenSelection = [];
        }
    }

    function _fmDragHoverTick() {
        if (!FmDrag.active || root.dragVisualActive)
            return;
        if (!root.windowId)
            return;

        const win = FmDrag.windowAt(FmDrag.globalX, FmDrag.globalY);
        if (!win || win.id !== root.windowId) {
            if (root.dropHoverActive) {
                root.dropHoverActive = false;
                root.dropHoverPath = "";
            }
            return;
        }

        // Default: drop into this window's current folder (reliable)
        let dest = root.state.cwdPath();

        // Optional finer target: map global → this view (only if result is sane)
        try {
            const mapped = root.mapFromGlobal(FmDrag.globalX, FmDrag.globalY);
            if (mapped && mapped.x >= 0 && mapped.y >= 0
                    && mapped.x <= root.width && mapped.y <= root.height) {
                const margin = Tokens.padding.extraSmall + Tokens.padding.medium;
                const tileDest = root.pathAtViewPos(mapped.x - margin, mapped.y - margin);
                if (tileDest && tileDest.length)
                    dest = tileDest;
            }
        } catch (e) {}

        const paths = FmDrag.paths || [];
        if (paths.indexOf && paths.indexOf(dest) >= 0)
            dest = root.state.cwdPath();

        root.dropHoverActive = true;
        if (dest !== root.dropHoverPath)
            root.dropHoverPath = dest;
        FmDrag.setHoverDest(root.windowId, dest);
    }




    // Input overlay
    MouseArea {
        id: input
        anchors.fill: parent
        anchors.margins: Tokens.padding.extraSmall + Tokens.padding.medium
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        z: 40
        preventStealing: true
        hoverEnabled: true
        pressAndHoldInterval: 350

        property real pressX: 0
        property real pressY: 0
        property bool moved: false
        property bool dragArmed: false
        property bool marqueeArmed: false
        property var pressHit: null
        property int pressModifiers: 0

        function armDragFromHit(): void {
            if (!pressHit?.modelData)
                return;
            marqueeArmed = false;
            root.marqueeActive = false;
            dragArmed = true;
            let paths = root.state.selection.slice();
            // Drag selection if pressed item is part of it; otherwise only that item
            if (paths.indexOf(pressHit.modelData.path) < 0)
                paths = [pressHit.modelData.path];
            const md = pressHit.modelData;
            dragProxy.path = paths[0] || md.path;
            dragProxy.name = md.name;
            dragProxy.paths = paths;
            dragProxy.isDir = !!md.isDir;
            dragProxy.isImage = !!md.isImage;
            // Always use icon (never full-res image) — decoding large photos freezes the drag
            dragProxy.iconSource = root.iconFor(md);
            if (paths.length > 1)
                root.state.statusText = qsTr("拖动 %1 项…").arg(paths.length);
            else if (md.isDir)
                root.state.statusText = qsTr("拖到文件夹放置，或拖到侧栏固定：%1").arg(md.name);
            else
                root.state.statusText = qsTr("拖动：%1").arg(md.name);
        }

        function beginInternalDrag(mx, my) {
            if (!dragArmed || !dragProxy.path.length || root.dragVisualActive)
                return;
            const paths = (dragProxy.paths && dragProxy.paths.length)
                ? dragProxy.paths.slice()
                : (dragProxy.path ? [dragProxy.path] : []);
            if (!paths.length)
                return;
            root.frozenSelection = paths.slice();
            root.dragVisualActive = true;
            root.dropHoverActive = false;
            root.dropHoverPath = "";
            dragProxy.moveToInputLocal(mx, my);
            // dropHandler runs from screen overlay on release (source window may not get release)
            FmDrag.begin(
                paths,
                root.state.cwdPath(),
                dragProxy.name,
                dragProxy.iconSource,
                root.windowId,
                (plist, dest) => root.actions.dropInto(plist, dest, "move")
            );
            cursorPosProc.running = true;
        }

        function updateInternalDrag(mx, my) {
            if (!root.dragVisualActive)
                return;
            dragProxy.moveToInputLocal(mx, my);
        }

        function finishInternalDrag(mx, my) {
            if (!root.dragVisualActive) {
                dragArmed = false;
                return;
            }
            // If still over source, refine dest from local pos before completeDrop
            try {
                const win = FmDrag.windowAt(FmDrag.globalX, FmDrag.globalY);
                if (win && root.windowId && win.id === root.windowId) {
                    const dest = root.pathAtViewPos(mx, my) || root.state.cwdPath();
                    FmDrag.setHoverDest(root.windowId, dest);
                }
            } catch (e) {}

            root.dragVisualActive = false;
            root.dropHoverActive = false;
            root.dropHoverPath = "";
            root.frozenSelection = [];
            dragArmed = false;
            dragProxy.clear();

            const n = FmDrag.completeDrop();
            if (n > 0)
                root.state.statusText = qsTr("已移动 %1 项").arg(n);
            else if (!FmDrag.active)
                root.state.statusText = root.state.statusText;
        }

        function cancelInternalDrag() {
            root.dragVisualActive = false;
            root.dropHoverActive = false;
            root.dropHoverPath = "";
            root.frozenSelection = [];
            dragArmed = false;
            dragProxy.clear();
            // Do not cancel session here if overlay will complete — only clear local UI.
            // Real cancel is right-click on overlay or Escape.
        }


        onPressed: mouse => {
            // Windows-like: foreign drag only paints drop target — ignore clicks/selection
            if (FmDrag.active && !root.dragVisualActive) {
                mouse.accepted = true;
                return;
            }
            pressX = mouse.x;
            pressY = mouse.y;
            moved = false;
            dragArmed = false;
            marqueeArmed = false;
            root.marqueeActive = false;
            pressModifiers = mouse.modifiers;
            const flick = root.isGrid ? grid : list;
            pressHit = flick.itemAt(mouse.x + flick.contentX, mouse.y + flick.contentY);
            if (mouse.button === Qt.LeftButton) {
                if (pressHit?.modelData) {
                    // Item press: ready to drag after small movement (no long-press)
                    armDragFromHit();
                } else {
                    // Empty area: rubber-band multi-select
                    marqueeArmed = true;
                }
            }
            mouse.accepted = true;
        }
        onPressAndHold: mouse => {
            if (mouse.button !== Qt.LeftButton)
                return;
            // Long-press still re-arms drag (status hint) if user held still
            if (pressHit?.modelData && !root.dragVisualActive)
                armDragFromHit();
        }
        onPositionChanged: mouse => {
            if (Math.abs(mouse.x - pressX) > 6 || Math.abs(mouse.y - pressY) > 6)
                moved = true;

            // Local drag: ghost follows cursor while left button held
            if (dragArmed && (mouse.buttons & Qt.LeftButton)) {
                if (moved) {
                    if (!root.dragVisualActive)
                        beginInternalDrag(mouse.x, mouse.y);
                    else
                        updateInternalDrag(mouse.x, mouse.y);
                    return;
                }
            }

            // Rubber-band selection — only when press started on empty space
            if (marqueeArmed && moved && !dragArmed && mouse.buttons & Qt.LeftButton) {
                if (!root.marqueeActive) {
                    root.marqueeActive = true;
                    root.setMarqueeCorner("0", pressX, pressY);
                    if (!(pressModifiers & Qt.ControlModifier))
                        root.state.setSelection([]);
                }
                root.setMarqueeCorner("1", mouse.x, mouse.y);
                root.applyMarqueeSelection();

                // Auto-scroll near edges (selection rect still clamped to viewport)
                const flick = root.isGrid ? grid : list;
                const edge = 28;
                if (mouse.y < edge)
                    flick.contentY = Math.max(0, flick.contentY - 18);
                else if (mouse.y > height - edge)
                    flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height), flick.contentY + 18);
            }
        }
        onReleased: mouse => {
            if (root.marqueeActive) {
                root.setMarqueeCorner("1", mouse.x, mouse.y);
                root.applyMarqueeSelection();
                root.marqueeActive = false;
            }
            if (root.dragVisualActive) {
                finishInternalDrag(mouse.x, mouse.y);
            } else {
                dragArmed = false;
                dragProxy.clear();
            }
            marqueeArmed = false;
            pressHit = null;
        }
        onCanceled: {
            // Pointer left FloatingWindow — keep FmDrag session; hypr mouse-release bind completes drop
            if (root.dragVisualActive || FmDrag.active) {
                root.dragVisualActive = false;
                root.dropHoverActive = false;
                root.dropHoverPath = "";
                root.frozenSelection = [];
                dragArmed = false;
                dragProxy.clear();
            } else {
                cancelInternalDrag();
            }
            marqueeArmed = false;
            pressHit = null;
            root.marqueeActive = false;
        }
        onExited: {
            // Keep ghost if still holding button (pointer left the pane briefly)
            // actual cancel only on release outside without finish — Hypr may still deliver release
        }
        onClicked: mouse => {
            if (moved || root.dragVisualActive)
                return;
            const flick = root.isGrid ? grid : list;
            const hit = flick.itemAt(mouse.x + flick.contentX, mouse.y + flick.contentY);
            if (!hit) {
                if (mouse.button === Qt.RightButton) {
                    const g = mapToItem(root, mouse.x, mouse.y);
                    root.contextMenuRequested(g.x, g.y, "", false, "");
                } else {
                    root.clearSelection();
                }
                return;
            }
            if (mouse.button === Qt.RightButton) {
                if (root.state.selection.indexOf(hit.modelData.path) < 0)
                    root.state.setSelection([hit.modelData.path]);
                if (root.isGrid)
                    grid.currentIndex = hit.index;
                else
                    list.currentIndex = hit.index;
                const g = mapToItem(root, mouse.x, mouse.y);
                root.contextMenuRequested(g.x, g.y, hit.modelData.path, hit.modelData.isDir, hit.modelData.name);
                return;
            }
            root.selectHit(hit, !!(mouse.modifiers & Qt.ControlModifier));
        }
        onDoubleClicked: mouse => {
            if (mouse.button !== Qt.LeftButton)
                return;
            const flick = root.isGrid ? grid : list;
            const hit = flick.itemAt(mouse.x + flick.contentX, mouse.y + flick.contentY);
            root.activateHit(hit);
        }
        onWheel: wheel => {
            const flick = root.isGrid ? grid : list;
            flick.flick(0, wheel.angleDelta.y * 4);
            wheel.accepted = true;
        }
    }

    component GridEntry: StyledRect {
        id: item

        required property int index
        // ListModel roles — must be required so Qt binds them from the model
        required property string path
        required property string name
        required property bool isDir
        required property bool isImage
        required property var size
        required property string mimeType
        required property string suffix
        required property string baseName

        readonly property var modelData: ({
            path: path,
            name: name,
            isDir: isDir,
            isImage: isImage,
            size: size,
            mimeType: mimeType,
            suffix: suffix,
            baseName: baseName
        })

        readonly property bool isSelected: {
            if (!modelData)
                return false;
            const list = root.dragVisualActive && root.frozenSelection && root.frozenSelection.length
                ? root.frozenSelection
                : root.state.selection;
            return list.indexOf(modelData.path) >= 0;
        }
        readonly property bool isCut: modelData && root.state.clipboardMode === "cut" && root.state.clipboardPaths.indexOf(modelData.path) >= 0
        readonly property real nonAnimHeight: icon.implicitHeight + nameLabel.anchors.topMargin + nameLabel.implicitHeight + Tokens.padding.medium * 2

        // Slightly smaller than cell so adjacent tiles have breathing room
        width: GridView.view ? Math.max(root.minItemWidth, GridView.view.cellWidth - root.gridGap) : root.itemWidth
        implicitWidth: width
        implicitHeight: nonAnimHeight
        radius: Tokens.rounding.large
        opacity: isCut ? 0.42 : 1
        readonly property bool isDropTarget: {
            if (!modelData || !modelData.isDir || !root.dropHoverActive)
                return false;
            // Source: freeze UI — no tile chrome walking under cursor
            if (root.dragVisualActive)
                return false;
            if (!FmDrag.active)
                return false;
            if (FmDrag.pendingWindowId && root.windowId && FmDrag.pendingWindowId !== root.windowId)
                return false;
            return root.dropHoverPath === modelData.path;
        }
        // Drop target = outline only (not selection fill) so it never looks like selection moving
        color: isDropTarget
            ? "transparent"
            : Qt.alpha(Colours.tPalette.m3surfaceContainerHighest, (GridView.isCurrentItem || isSelected) ? Colours.tPalette.m3surfaceContainerHighest.a : 0)
        border.width: isDropTarget ? 2 : 0
        border.color: isDropTarget ? Colours.palette.m3primary : "transparent"
        z: GridView.isCurrentItem || isSelected || isDropTarget || implicitHeight !== nonAnimHeight ? 1 : 0
        clip: true

        Behavior on opacity {
            Anim { type: Anim.DefaultEffects }
        }

        StateLayer {
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
        }

        Rectangle {
            visible: item.isCut
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 6
            width: cutBadge.implicitWidth + 10
            height: cutBadge.implicitHeight + 4
            radius: height / 2
            color: Colours.palette.m3tertiary
            z: 2
            StyledText {
                id: cutBadge
                anchors.centerIn: parent
                text: qsTr("剪切")
                color: Colours.palette.m3onTertiary
                font: Tokens.font.body.builders.small.scale(0.85).weight(Font.Bold).build()
            }
        }

        CachingIconImage {
            id: icon
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Tokens.padding.medium
            implicitSize: root.itemWidth - Tokens.padding.medium * 2
            opacity: item.isCut ? 0.85 : 1
            // Reactive: roles change when delegate is recycled
            source: {
                const d = item.modelData;
                if (!d || !d.path)
                    return "";
                if (d.isImage)
                    return Qt.resolvedUrl(d.path);
                return root.iconFor(d);
            }
        }

        StyledText {
            id: nameLabel
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: icon.bottom
            anchors.topMargin: Tokens.spacing.small
            anchors.margins: Tokens.padding.medium
            horizontalAlignment: Text.AlignHCenter
            text: {
                // Prefer role properties (avoid id shadowing of "name")
                const d = {
                    path: item.path,
                    name: item.name,
                    isDir: item.isDir,
                    isImage: item.isImage,
                    size: item.size,
                    mimeType: item.mimeType,
                    suffix: item.suffix,
                    baseName: item.baseName
                };
                return root.state.displayName(d);
            }
            // Keep tile height stable: always elide; at most 2 lines when focused/selected
            wrapMode: (item.GridView.isCurrentItem || item.isSelected) ? Text.WrapAtWordBoundaryOrAnywhere : Text.NoWrap
            maximumLineCount: (item.GridView.isCurrentItem || item.isSelected) ? 2 : 1
            elide: Text.ElideRight
        }

        Behavior on implicitHeight {
            Anim {}
        }
    }

    component ListEntry: StyledRect {
        id: row

        required property int index
        required property string path
        required property string name
        required property bool isDir
        required property bool isImage
        required property var size
        required property string mimeType
        required property string suffix
        required property string baseName

        readonly property var modelData: ({
            path: path,
            name: name,
            isDir: isDir,
            isImage: isImage,
            size: size,
            mimeType: mimeType,
            suffix: suffix,
            baseName: baseName
        })

        readonly property bool isSelected: {
            if (!modelData)
                return false;
            const list = root.dragVisualActive && root.frozenSelection && root.frozenSelection.length
                ? root.frozenSelection
                : root.state.selection;
            return list.indexOf(modelData.path) >= 0;
        }
        readonly property bool isCut: !!(modelData && root.state.clipboardMode === "cut" && root.state.clipboardPaths.indexOf(modelData.path) >= 0)

        width: ListView.view ? ListView.view.width : 200
        implicitHeight: 40
        radius: Tokens.rounding.medium
        opacity: isCut ? 0.42 : 1
        readonly property bool isDropTarget: {
            if (!modelData || !modelData.isDir || !root.dropHoverActive)
                return false;
            // Source: freeze UI — no tile chrome walking under cursor
            if (root.dragVisualActive)
                return false;
            if (!FmDrag.active)
                return false;
            if (FmDrag.pendingWindowId && root.windowId && FmDrag.pendingWindowId !== root.windowId)
                return false;
            return root.dropHoverPath === modelData.path;
        }
        color: isDropTarget
            ? "transparent"
            : Qt.alpha(Colours.tPalette.m3surfaceContainerHighest, (ListView.isCurrentItem || isSelected) ? Colours.tPalette.m3surfaceContainerHighest.a : 0)
        border.width: isDropTarget ? 2 : 0
        border.color: isDropTarget ? Colours.palette.m3primary : "transparent"

        Behavior on opacity {
            Anim { type: Anim.DefaultEffects }
        }

        StateLayer {
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.medium
            anchors.rightMargin: Tokens.padding.medium
            spacing: Tokens.spacing.medium

            CachingIconImage {
                implicitSize: 24
                source: {
                    const d = row.modelData;
                    if (!d || !d.path)
                        return "";
                    if (d.isImage)
                        return Qt.resolvedUrl(d.path);
                    return root.iconFor(d);
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: root.state.displayName({
                    path: row.path,
                    name: row.name,
                    isDir: row.isDir,
                    isImage: row.isImage,
                    size: row.size,
                    mimeType: row.mimeType,
                    suffix: row.suffix,
                    baseName: row.baseName
                })
                color: Colours.palette.m3onSurface
                font: Tokens.font.body.small
                elide: Text.ElideMiddle
            }

            StyledText {
                visible: row.modelData && !row.modelData.isDir
                Layout.preferredWidth: 72
                horizontalAlignment: Text.AlignRight
                text: row.modelData ? root.humanSize(row.modelData.size) : ""
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.builders.small.scale(0.9).build()
            }

            StyledText {
                visible: !!(row.modelData && row.modelData.isDir)
                Layout.preferredWidth: 72
                horizontalAlignment: Text.AlignRight
                text: qsTr("文件夹")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.builders.small.scale(0.9).build()
            }

            StyledText {
                Layout.preferredWidth: 118
                horizontalAlignment: Text.AlignRight
                text: row.modelData ? (root.mtimeFor(row.modelData.name) || "—") : "—"
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.builders.small.scale(0.9).build()
            }

            StyledText {
                visible: row.isCut
                text: qsTr("剪切")
                color: Colours.palette.m3tertiary
                font: Tokens.font.body.builders.small.weight(Font.Bold).build()
            }
        }
    }
}
