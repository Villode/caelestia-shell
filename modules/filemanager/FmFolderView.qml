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

    FileSystemModel {
        id: fsModel
        path: {
            const _ = root.state.refreshNonce;
            if (root.state.isThisPC)
                return "";
            return root.state.cwdPath();
        }
        showHidden: root.state.showHidden
        // Live name filter from toolbar search (QDir wildcards via ManagerState)
        nameFilters: root.state.nameFiltersForSearch()
        onPathChanged: {
            grid.currentIndex = -1;
            list.currentIndex = -1;
            if (!root.state.isThisPC)
                root.state.selection = [];
            if (path && path.length)
                root.reloadMtimes(path);
            else
                root.mtimeMap = {};
        }
        Component.onCompleted: {
            if (path && path.length)
                root.reloadMtimes(path);
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
                    ? qsTr("无匹配「%1」的项").arg(root.state.nameFilter)
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
        model: fsModel
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
        model: fsModel
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

    // Drag proxy for pin-to-sidebar (folder long-press then move)
    Item {
        id: dragProxy
        width: 1
        height: 1
        visible: false
        property string path: ""
        property string name: ""
        property var paths: []
        readonly property string uriList: {
            const list = (paths && paths.length) ? paths : (path ? [path] : []);
            let s = "";
            for (let i = 0; i < list.length; i++) {
                if (i)
                    s += "\n";
                s += "file://" + list[i];
            }
            return s;
        }
        readonly property string plainList: {
            const list = (paths && paths.length) ? paths : (path ? [path] : []);
            let s = "";
            for (let i = 0; i < list.length; i++) {
                if (i)
                    s += "\n";
                s += list[i];
            }
            return s;
        }
        Drag.dragType: Drag.Automatic
        Drag.mimeData: ({
            "text/uri-list": uriList,
            "text/plain": plainList
        })
        Drag.proposedAction: Qt.CopyAction
        Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
        Drag.hotSpot.x: 0
        Drag.hotSpot.y: 0
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

    // Soft highlight when dragging files over a folder / pane
    Rectangle {
        id: dropGlow
        anchors.fill: parent
        anchors.margins: Tokens.padding.extraSmall
        z: 34
        radius: Tokens.rounding.medium
        visible: root.dropHoverActive
        color: Qt.alpha(Colours.palette.m3primary, 0.08)
        border.width: 2
        border.color: Colours.palette.m3primary
        opacity: root.dropHoverActive ? 1 : 0
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
            // Empty area or left-drag multi-select: arm marquee (pin drag needs long-press first)
            if (mouse.button === Qt.LeftButton)
                marqueeArmed = true;
            mouse.accepted = true;
        }
        onPressAndHold: mouse => {
            if (mouse.button !== Qt.LeftButton)
                return;
            // Long-press on item → drag files (copy/move) or pin folder to sidebar
            if (pressHit?.modelData) {
                marqueeArmed = false;
                root.marqueeActive = false;
                dragArmed = true;
                let paths = root.state.selection.slice();
                if (paths.indexOf(pressHit.modelData.path) < 0)
                    paths = [pressHit.modelData.path];
                dragProxy.path = paths[0] || pressHit.modelData.path;
                dragProxy.name = pressHit.modelData.name;
                dragProxy.paths = paths;
                if (paths.length > 1)
                    root.state.statusText = qsTr("拖动 %1 项…").arg(paths.length);
                else if (pressHit.modelData.isDir)
                    root.state.statusText = qsTr("拖到文件夹放置，或拖到侧栏固定：%1").arg(pressHit.modelData.name);
                else
                    root.state.statusText = qsTr("拖动：%1").arg(pressHit.modelData.name);
            }
        }
        onPositionChanged: mouse => {
            if (Math.abs(mouse.x - pressX) > 6 || Math.abs(mouse.y - pressY) > 6)
                moved = true;

            if (dragArmed && moved && dragProxy.path.length && !dragProxy.Drag.active) {
                dragProxy.x = mouse.x;
                dragProxy.y = mouse.y;
                dragProxy.Drag.active = true;
                return;
            }

            // Rubber-band selection — corners always clamped to content area
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
            } else if (dragArmed && moved) {
                dragProxy.x = mouse.x;
                dragProxy.y = mouse.y;
            }
        }
        onReleased: mouse => {
            if (root.marqueeActive) {
                root.setMarqueeCorner("1", mouse.x, mouse.y);
                root.applyMarqueeSelection();
                root.marqueeActive = false;
            }
            if (dragProxy.Drag.active) {
                dragProxy.Drag.drop();
                dragProxy.Drag.active = false;
            }
            dragArmed = false;
            marqueeArmed = false;
            pressHit = null;
        }
        onClicked: mouse => {
            if (moved || dragProxy.Drag.active)
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
        required property FileSystemEntry modelData

        readonly property bool isSelected: modelData ? root.state.selection.indexOf(modelData.path) >= 0 : false
        readonly property bool isCut: modelData && root.state.clipboardMode === "cut" && root.state.clipboardPaths.indexOf(modelData.path) >= 0
        readonly property real nonAnimHeight: icon.implicitHeight + name.anchors.topMargin + name.implicitHeight + Tokens.padding.medium * 2

        // Slightly smaller than cell so adjacent tiles have breathing room
        width: GridView.view ? Math.max(root.minItemWidth, GridView.view.cellWidth - root.gridGap) : root.itemWidth
        implicitWidth: width
        implicitHeight: nonAnimHeight
        radius: Tokens.rounding.large
        opacity: isCut ? 0.42 : 1
        color: Qt.alpha(Colours.tPalette.m3surfaceContainerHighest, (GridView.isCurrentItem || isSelected) ? Colours.tPalette.m3surfaceContainerHighest.a : 0)
        z: GridView.isCurrentItem || isSelected || implicitHeight !== nonAnimHeight ? 1 : 0
        clip: true

        // Drag for pinning dirs
        Drag.active: dragArea.drag.active
        Drag.dragType: Drag.Automatic
        Drag.mimeData: modelData ? {
            "text/uri-list": "file://" + modelData.path,
            "text/plain": modelData.path
        } : ({})
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2

        MouseArea {
            id: dragArea
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            // Only start drag after hold so normal click works via overlay...
            // Overlay is z:40 above us — so drag won't work from here.
            // Instead: use delayed drag from overlay when item is dir — skip for now;
            // pin via context menu is primary; DropArea still accepts external drops.
            enabled: false
            drag.target: parent
        }

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
            Component.onCompleted: {
                if (item.modelData.isImage)
                    source = Qt.resolvedUrl(item.modelData.path);
                else
                    source = root.iconFor(item.modelData);
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
            elide: (item.GridView.isCurrentItem || item.isSelected) ? Text.ElideNone : Text.ElideRight
            wrapMode: (item.GridView.isCurrentItem || item.isSelected) ? Text.WrapAtWordBoundaryOrAnywhere : Text.NoWrap
        }

        Behavior on implicitHeight {
            Anim {}
        }
    }

    component ListEntry: StyledRect {
        id: row

        required property int index
        required property FileSystemEntry modelData

        readonly property bool isSelected: modelData ? root.state.selection.indexOf(modelData.path) >= 0 : false
        readonly property bool isCut: !!(modelData && root.state.clipboardMode === "cut" && root.state.clipboardPaths.indexOf(modelData.path) >= 0)

        width: ListView.view ? ListView.view.width : 200
        implicitHeight: 40
        radius: Tokens.rounding.medium
        opacity: isCut ? 0.42 : 1
        color: Qt.alpha(Colours.tPalette.m3surfaceContainerHighest, (ListView.isCurrentItem || isSelected) ? Colours.tPalette.m3surfaceContainerHighest.a : 0)

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
                Component.onCompleted: {
                    if (!row.modelData)
                        return;
                    if (row.modelData.isImage)
                        source = Qt.resolvedUrl(row.modelData.path);
                    else
                        source = root.iconFor(row.modelData);
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
