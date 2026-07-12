pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.filedialog
import qs.components.images
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property real maximumTransparency: 0.75
    // PageBase caps settings content at 800px, so this must remain below that cap.
    // At this width the preview and compact appearance controls can sit side by side.
    readonly property bool twoColumnLayout: root.cappedWidth >= 640

    property string requestedMode
    property string desktopMode: "video"
    property string videoSource
    property string htmlSource
    property string desktopFit: "cover"
    property string desktopMessage
    property bool desktopBusy

    readonly property FileDialog videoFileDialog: FileDialog {
        id: videoFileDialog
        title: "选择视频壁纸"
        filterLabel: "视频文件"
        filters: ["mp4", "webm", "mkv", "mov", "m4v", "avi"]
        onAccepted: path => {
            root.videoSource = path;
            root.syncDesktopSource();
            root.desktopMessage = "";
        }
    }

    readonly property FileDialog htmlFileDialog: FileDialog {
        id: htmlFileDialog
        title: "选择网页文件"
        filterLabel: "HTML 文件"
        filters: ["html", "htm"]
        onAccepted: path => {
            root.htmlSource = path;
            root.syncDesktopSource();
            root.desktopMessage = "";
        }
    }

    readonly property string desiredMode: requestedMode || (Colours.light ? "light" : "dark")

    property Connections colourConnections: Connections {
        function onCurrentLightChanged(): void {
            root.requestedMode = Colours.light ? "light" : "dark";
        }

        target: Colours
    }

    title: "壁纸和样式"

    function syncDesktopSource(): void {
        desktopSource.text = root.desktopMode === "video" ? root.videoSource : root.htmlSource;
    }

    function refreshDesktop(): void {
        if (!desktopStatus.running)
            desktopStatus.running = true;
    }

    function applyDesktop(): void {
        const source = desktopSource.text.trim();
        if (!source) {
            desktopMessage = desktopMode === "video" ? "请选择视频文件。" : "请输入 HTML 文件路径或网址。";
            return;
        }
        desktopBusy = true;
        desktopMessage = "正在应用…";
        desktopApply.command = desktopMode === "video"
            ? ["villode-desktop", "--set-video", source, "--fit", desktopFit]
            : ["villode-desktop", "--set-html", source];
        desktopApply.running = true;
    }

    property Process desktopStatus: Process {
        id: desktopStatus
        command: ["villode-desktop", "--status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.videoSource = data.sources?.video ?? "";
                    root.htmlSource = data.sources?.html ?? "";
                    root.desktopFit = data.fit ?? "cover";
                    if (data.mode === "video" || data.mode === "html")
                        root.desktopMode = data.mode;
                    root.syncDesktopSource();
                } catch (error) {
                    root.desktopMessage = "无法读取 Villode Desktop 配置。";
                }
            }
        }
    }

    property Process desktopApply: Process {
        id: desktopApply
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    root.desktopMessage = text.trim();
            }
        }
        onExited: code => { // qmllint disable signal-handler-parameters
            root.desktopBusy = false;
            if (code === 0) {
                GlobalConfig.background.wallpaperEnabled = false;
                root.desktopMessage = "动态壁纸已应用。";
                if (root.desktopMode === "video")
                    root.videoSource = desktopSource.text.trim();
                else
                    root.htmlSource = desktopSource.text.trim();
                root.refreshDesktop();
            } else if (!root.desktopMessage || root.desktopMessage === "正在应用…") {
                root.desktopMessage = "应用失败，请检查来源和依赖。";
            }
        }
    }

    property Process desktopStop: Process {
        id: desktopStop
        command: ["villode-desktop", "--quit"]
        onExited: code => { // qmllint disable signal-handler-parameters
            root.desktopBusy = false;
            root.desktopMessage = code === 0 ? "已停止动态壁纸，继续使用静态壁纸。" : "停止动态壁纸失败。";
            if (code === 0) {
                GlobalConfig.background.wallpaperEnabled = true;
                root.refreshDesktop();
            }
        }
    }

    Component.onCompleted: refreshDesktop()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.medium

        Item {
            id: monitorPreview

            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(root.cappedWidth, 560)
            readonly property real screenHeight: {
                const screen = root.nState.screen;
                return width / screen.width * screen.height;
            }
            Layout.preferredHeight: screenHeight + 30

            StyledRect {
                anchors.horizontalCenter: parent.horizontalCenter
                y: monitorScreen.height - 1
                width: 44
                height: 20
                color: Colours.palette.m3outlineVariant
                radius: Tokens.rounding.small
            }

            StyledRect {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                width: 108
                height: 5
                color: Colours.palette.m3outlineVariant
                radius: Tokens.rounding.full
            }

            StyledRect {
                id: monitorScreen

                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                height: monitorPreview.screenHeight
                color: Colours.palette.m3outlineVariant
                radius: Tokens.rounding.large

                StyledClippingRect {
                    id: wallWrapper

                    anchors.fill: parent
                    anchors.margins: 3
                    radius: Math.max(0, parent.radius - 3)
                    color: Colours.palette.m3surface

                    Loader {
                        id: wallIndicatorLoader
                        anchors.centerIn: parent
                        opacity: 0
                        active: opacity > 0

                        sourceComponent: StyledRect {
                            implicitWidth: wallLoadingIndicator.implicitSize + Tokens.padding.largeIncreased * 2
                            implicitHeight: wallLoadingIndicator.implicitSize + Tokens.padding.largeIncreased * 2
                            color: Colours.palette.m3primaryContainer
                            radius: Tokens.rounding.full

                            LoadingIndicator {
                                id: wallLoadingIndicator
                                anchors.centerIn: parent
                                containsIcon: true
                                implicitSize: Math.min(wallWrapper.width, wallWrapper.height) * 0.25
                            }
                        }

                        Behavior on opacity {
                            Anim { type: Anim.DefaultEffects }
                        }
                    }

                    Timer {
                        id: wallLoadDebounceTimer
                        interval: 100
                        onTriggered: {
                            if (wallImg.status !== Image.Ready)
                                wallIndicatorLoader.opacity = 1;
                        }
                    }

                    FadeImage {
                        id: wallImg
                        anchors.fill: parent
                        source: Wallpapers.current
                        preventInit: wallIndicatorLoader.opacity > 0
                        fadeOutAnim: Anim.DefaultEffects
                        fadeInAnim: Anim.SlowEffects
                        onSourceChanged: wallLoadDebounceTimer.restart()
                        onStatusChanged: {
                            if (status === Image.Ready) {
                                wallLoadDebounceTimer.stop();
                                wallIndicatorLoader.opacity = 0;
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.nState.openSubPage(1)
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            ConnectedRect {
                Layout.fillWidth: true
                first: true
                last: true
                implicitHeight: desktopLayout.implicitHeight + Tokens.padding.large * 2

                ColumnLayout {
                    id: desktopLayout
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.medium

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                text: "动态桌面"
                                font: Tokens.font.title.large
                            }

                            StyledText {
                                text: "用视频或网页为桌面增加动态效果"
                                color: Colours.palette.m3outline
                                font: Tokens.font.label.small
                            }
                        }

                        ButtonRow {
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            spacing: 0

                            IconTextButton {
                                icon: "movie"
                                text: "视频"
                                isToggle: false
                                checked: root.desktopMode === "video"
                                type: IconTextButton.Tonal
                                onClicked: {
                                    root.desktopMode = "video";
                                    root.syncDesktopSource();
                                    root.desktopMessage = "";
                                }
                            }

                            IconTextButton {
                                icon: "language"
                                text: "网页"
                                isToggle: false
                                checked: root.desktopMode === "html"
                                type: IconTextButton.Tonal
                                onClicked: {
                                    root.desktopMode = "html";
                                    root.syncDesktopSource();
                                    root.desktopMessage = "";
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        M3TextField {
                            id: desktopSource
                            Layout.fillWidth: true
                            label: root.desktopMode === "video" ? "视频文件" : "HTML 文件或网址"
                            placeholder: root.desktopMode === "video" ? "/home/user/Videos/wallpaper.mp4" : "https://example.com"
                            text: root.desktopMode === "video" ? root.videoSource : root.htmlSource
                            leadingIcon: root.desktopMode === "video" ? "movie" : "language"
                            supportingText: root.desktopMode === "video" ? "支持 MP4、WebM、MKV、MOV、M4V、AVI，建议使用本地 1080p 视频。" : "也可以直接输入 http(s) 地址。"
                            onTextChanged: {
                                if (root.desktopMode === "video")
                                    root.videoSource = text;
                                else
                                    root.htmlSource = text;
                            }
                            onAccepted: root.applyDesktop()
                        }

                        IconButton {
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 7
                            icon: "folder_open"
                            type: IconButton.Tonal
                            isRound: true
                            onClicked: {
                                if (root.desktopMode === "video")
                                    videoFileDialog.open();
                                else
                                    htmlFileDialog.open();
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.desktopMode === "video"
                        spacing: Tokens.spacing.small

                        StyledText {
                            text: "画面适配"
                            font: Tokens.font.body.medium
                            color: Colours.palette.m3onSurfaceVariant
                        }

                        ButtonRow {
                            Layout.alignment: Qt.AlignLeft
                            spacing: 0

                            IconTextButton {
                                text: "铺满屏幕"
                                isToggle: false
                                checked: root.desktopFit === "cover"
                                type: IconTextButton.Tonal
                                onClicked: root.desktopFit = "cover"
                            }

                            IconTextButton {
                                text: "完整显示"
                                isToggle: false
                                checked: root.desktopFit === "contain"
                                type: IconTextButton.Tonal
                                onClicked: root.desktopFit = "contain"
                            }

                            IconTextButton {
                                text: "拉伸填满"
                                isToggle: false
                                checked: root.desktopFit === "stretch"
                                type: IconTextButton.Tonal
                                onClicked: root.desktopFit = "stretch"
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: root.desktopMessage
                        color: root.desktopMessage.includes("失败") || root.desktopMessage.includes("无法") ? Colours.palette.m3error : Colours.palette.m3outline
                        font: Tokens.font.label.small
                        wrapMode: Text.WordWrap
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Tokens.spacing.extraSmall
                        spacing: Tokens.spacing.medium

                        StyledText {
                            Layout.fillWidth: true
                            text: root.desktopMode === "video" ? "视频将静音循环播放" : "网页将在独立视图中运行"
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }

                        IconTextButton {
                            icon: "stop_circle"
                            text: "停止"
                            type: IconTextButton.Tonal
                            disabled: root.desktopBusy
                            onClicked: {
                                root.desktopBusy = true;
                                desktopStop.running = true;
                            }
                        }

                        IconTextButton {
                            icon: "check"
                            text: root.desktopBusy ? "正在应用" : "应用"
                            type: IconTextButton.Filled
                            disabled: root.desktopBusy
                            onClicked: root.applyDesktop()
                        }
                    }
                }
            }

            ConnectedRect {
                Layout.fillWidth: true
                first: true
                last: true
                implicitHeight: appearanceLayout.implicitHeight + Tokens.padding.large * 2

                ColumnLayout {
                    id: appearanceLayout
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                text: "外观"
                                font: Tokens.font.title.large
                            }

                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.large

                        StyledText {
                            Layout.fillWidth: true
                            text: "主题模式"
                            font: Tokens.font.body.medium
                        }

                        ButtonRow {
                            spacing: 0

                            IconTextButton {
                                icon: "dark_mode"
                                text: "深色"
                                isToggle: false
                                checked: !Colours.autoMode && !Colours.light
                                type: IconTextButton.Tonal
                                onClicked: {
                                    root.requestedMode = "dark";
                                    Colours.setAutoMode(false);
                                    Colours.setMode("dark");
                                }
                            }

                            IconTextButton {
                                icon: "light_mode"
                                text: "亮色"
                                isToggle: false
                                checked: !Colours.autoMode && Colours.light
                                type: IconTextButton.Tonal
                                onClicked: {
                                    root.requestedMode = "light";
                                    Colours.setAutoMode(false);
                                    Colours.setMode("light");
                                }
                            }

                            IconTextButton {
                                icon: "brightness_auto"
                                text: "自动"
                                isToggle: false
                                checked: Colours.autoMode
                                type: IconTextButton.Tonal
                                onClicked: {
                                    root.requestedMode = "";
                                    Colours.setAutoMode(true);
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.large

                        StyledText {
                            Layout.fillWidth: true
                            text: "主题色"
                            font: Tokens.font.body.medium
                        }

                        ButtonRow {
                            spacing: Tokens.spacing.extraSmall

                            PresetButton {
                                presetName: "blue"
                                presetColour: "#366385"
                                text: "海蓝"
                            }

                            PresetButton {
                                presetName: "teal"
                                presetColour: "#1c6a66"
                                text: "青绿"
                            }

                            PresetButton {
                                presetName: "violet"
                                presetColour: "#7657a8"
                                text: "紫罗兰"
                            }

                            PresetButton {
                                presetName: "green"
                                presetColour: "#437653"
                                text: "森林"
                            }

                            PresetButton {
                                presetName: "rose"
                                presetColour: "#9a526f"
                                text: "玫瑰"
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        RowLayout {
                            Layout.fillWidth: true
                            StyledText {
                                Layout.fillWidth: true
                                text: "透明度"
                                font: Tokens.font.body.medium
                            }

                            StyledText {
                                text: `${Math.round(transparencySlider.value * root.maximumTransparency * 100)}%`
                                color: Colours.palette.m3outline
                                font: Tokens.font.body.small
                            }
                        }

                        StyledSlider {
                            id: transparencySlider
                            Layout.fillWidth: true
                            Layout.preferredHeight: Tokens.padding.medium * 2
                            value: GlobalConfig.appearance.transparency.enabled ? Math.min(root.maximumTransparency, 1 - GlobalConfig.appearance.transparency.base) / root.maximumTransparency : 0
                            radius: Tokens.rounding.small
                            onInteraction: v => {
                                GlobalConfig.appearance.transparency.enabled = v > 0.005;
                                GlobalConfig.appearance.transparency.base = 1 - v * root.maximumTransparency;
                            }
                        }
                    }
                }
            }
        }
    }

    component PresetButton: IconTextButton {
        required property string presetName
        required property color presetColour

        icon: "circle"
        isToggle: false
        checked: Colours.preset === presetName
        type: IconTextButton.Tonal
        activeColour: presetColour
        inactiveColour: Qt.alpha(presetColour, 0.18)
        activeOnColour: "white"
        inactiveOnColour: Colours.palette.m3onSurfaceVariant
        onClicked: {
            Colours.setPreset(presetName, root.desiredMode);
        }
    }
}
