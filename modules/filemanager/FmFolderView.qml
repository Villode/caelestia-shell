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
        try {
            const entries = fsModel.entries;
            const n = entries ? entries.length : 0;
            for (let i = 0; i < n; i++) {
                const e = entries[i];
                if (e)
                    items.push(e);
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

    // On-cursor ghost for internal drag (no Qt Drag grab — follows mouse while pressed)
    Item {
        id: dragProxy
        width: ghostCard.implicitWidth
        height: ghostCard.implicitHeight
        visible: root.dragVisualActive
        z: 200
        opacity: root.dragVisualActive ? 0.92 : 0
        property string path: ""
        property string name: ""
        property var paths: []
        property bool isDir: false
        property bool isImage: false
        property string iconSource: ""
        property real hotX: 20
        property real hotY: 20
        readonly property int count: (paths && paths.length) ? paths.length : (path ? 1 : 0)

        function moveToInputLocal(mx: real, my: real): void {
            const p = input.mapToItem(dragProxy.parent, mx, my);
            dragProxy.x = p.x - hotX;
            dragProxy.y = p.y - hotY;
        }

        function clear(): void {
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
            // Soft lift
            layer.enabled: true

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

            // Multi-select badge
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
            // Internal drag uses mouse-follow ghost + dropInto on release (skip DropArea)
            if (root.dragVisualActive) {
                drag.accepted = false;
                return;
            }
            drag.accepted = drag.hasUrls || drag.hasText;
            if (drag.accepted) {
                root.dropHoverActive = true;
                root.dropHoverPath = root.pathAtViewPos(drag.x, drag.y);
            }
        }
        onPositionChanged: drag => {
            if (!root.dropHoverActive)
                return;
            root.dropHoverPath = root.pathAtViewPos(drag.x, drag.y);
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
        visible: root.dropHoverActive && root.dropHoverPath === root.state.cwdPath()
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
            if (md.isImage)
                dragProxy.iconSource = Qt.resolvedUrl(md.path);
            else
                dragProxy.iconSource = root.iconFor(md);
            if (paths.length > 1)
                root.state.statusText = qsTr("拖动 %1 项…").arg(paths.length);
            else if (md.isDir)
                root.state.statusText = qsTr("拖到文件夹放置，或拖到侧栏固定：%1").arg(md.name);
            else
                root.state.statusText = qsTr("拖动：%1").arg(md.name);
        }

        function beginInternalDrag(mx: real, my: real): void {
            if (!dragArmed || !dragProxy.path.length || root.dragVisualActive)
                return;
            root.dragVisualActive = true;
            dragProxy.moveToInputLocal(mx, my);
            root.dropHoverActive = true;
            root.dropHoverPath = root.pathAtViewPos(mx, my);
        }

        function updateInternalDrag(mx: real, my: real): void {
            if (!root.dragVisualActive)
                return;
            dragProxy.moveToInputLocal(mx, my);
            root.dropHoverActive = true;
            root.dropHoverPath = root.pathAtViewPos(mx, my);
        }

        function finishInternalDrag(mx: real, my: real): void {
            if (!root.dragVisualActive) {
                dragArmed = false;
                return;
            }
            const paths = (dragProxy.paths && dragProxy.paths.length)
                ? dragProxy.paths.slice()
                : (dragProxy.path ? [dragProxy.path] : []);
            const dest = root.pathAtViewPos(mx, my) || root.state.cwdPath();
            root.dragVisualActive = false;
            root.dropHoverActive = false;
            root.dropHoverPath = "";
            dragArmed = false;
            dragProxy.clear();
            if (!paths.length)
                return;
            // Default internal: move when dropping into a different folder (same volume UX)
            // Use move if destination is a subfolder of cwd, else copy for safety on same dir cancel
            if (dest === root.state.cwdPath()) {
                root.state.statusText = qsTr("已取消（放到原目录）");
                return;
            }
            // Same-parent check handled in dropInto
            root.actions.dropInto(paths, dest, "move");
        }

        function cancelInternalDrag(): void {
            root.dragVisualActive = false;
            root.dropHoverActive = false;
            root.dropHoverPath = "";
            dragArmed = false;
            dragProxy.clear();
        }

        onPressed: mouse => {
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

            // Internal drag: ghost follows cursor while left button held
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
            cancelInternalDrag();
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

        readonly property bool isSelected: modelData ? root.state.selection.indexOf(modelData.path) >= 0 : false
        readonly property bool isCut: modelData && root.state.clipboardMode === "cut" && root.state.clipboardPaths.indexOf(modelData.path) >= 0
        readonly property real nonAnimHeight: icon.implicitHeight + name.anchors.topMargin + name.implicitHeight + Tokens.padding.medium * 2

        // Slightly smaller than cell so adjacent tiles have breathing room
        width: GridView.view ? Math.max(root.minItemWidth, GridView.view.cellWidth - root.gridGap) : root.itemWidth
        implicitWidth: width
        implicitHeight: nonAnimHeight
        radius: Tokens.rounding.large
        opacity: isCut ? 0.42 : 1
        readonly property bool isDropTarget: !!(modelData && modelData.isDir && root.dropHoverActive && root.dropHoverPath === modelData.path)
        color: isDropTarget
            ? Qt.alpha(Colours.palette.m3primary, 0.18)
            : Qt.alpha(Colours.tPalette.m3surfaceContainerHighest, (GridView.isCurrentItem || isSelected) ? Colours.tPalette.m3surfaceContainerHighest.a : 0)
        border.width: isDropTarget ? 2 : 0
        border.color: Colours.palette.m3primary
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
            id: name
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: icon.bottom
            anchors.topMargin: Tokens.spacing.small
            anchors.margins: Tokens.padding.medium
            horizontalAlignment: Text.AlignHCenter
            text: root.state.displayName(item.modelData)
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

        readonly property bool isSelected: modelData ? root.state.selection.indexOf(modelData.path) >= 0 : false
        readonly property bool isCut: !!(modelData && root.state.clipboardMode === "cut" && root.state.clipboardPaths.indexOf(modelData.path) >= 0)

        width: ListView.view ? ListView.view.width : 200
        implicitHeight: 40
        radius: Tokens.rounding.medium
        opacity: isCut ? 0.42 : 1
        readonly property bool isDropTarget: !!(modelData && modelData.isDir && root.dropHoverActive && root.dropHoverPath === modelData.path)
        color: isDropTarget
            ? Qt.alpha(Colours.palette.m3primary, 0.18)
            : Qt.alpha(Colours.tPalette.m3surfaceContainerHighest, (ListView.isCurrentItem || isSelected) ? Colours.tPalette.m3surfaceContainerHighest.a : 0)
        border.width: isDropTarget ? 2 : 0
        border.color: Colours.palette.m3primary

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
                text: row.modelData ? root.state.displayName(row.modelData) : ""
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
