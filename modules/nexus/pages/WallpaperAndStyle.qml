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
        title: qsTr("Choose video wallpaper")
        filterLabel: qsTr("Video files")
        filters: ["mp4", "webm", "mkv", "mov", "m4v", "avi"]
        onAccepted: path => {
            root.videoSource = path;
            root.syncDesktopSource();
            root.desktopMessage = "";
        }
    }

    readonly property FileDialog htmlFileDialog: FileDialog {
        id: htmlFileDialog
        title: qsTr("Choose web file")
        filterLabel: qsTr("HTML files")
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

    title: qsTr("Wallpaper & style")

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
            desktopMessage = desktopMode === "video" ? qsTr("Choose a video file.") : qsTr("Enter an HTML file path or URL.");
            return;
        }
        desktopBusy = true;
        desktopMessage = qsTr("Applying...");
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
                    root.desktopMessage = qsTr("Could not read Villode Desktop configuration.");
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
                root.desktopMessage = qsTr("Dynamic wallpaper applied.");
                if (root.desktopMode === "video")
                    root.videoSource = desktopSource.text.trim();
                else
                    root.htmlSource = desktopSource.text.trim();
                root.refreshDesktop();
            } else if (!root.desktopMessage || root.desktopMessage === qsTr("Applying...")) {
                root.desktopMessage = qsTr("Could not apply the source. Check its path and dependencies.");
            }
        }
    }

    property Process desktopStop: Process {
        id: desktopStop
        command: ["villode-desktop", "--quit"]
        onExited: code => { // qmllint disable signal-handler-parameters
            root.desktopBusy = false;
            root.desktopMessage = code === 0 ? qsTr("Dynamic wallpaper stopped; static wallpaper remains active.") : qsTr("Could not stop dynamic wallpaper.");
            if (code === 0) {
                GlobalConfig.background.wallpaperEnabled = true;
                root.refreshDesktop();
            }
        }
    }

    Component.onCompleted: refreshDesktop()

    component SegmentedSlider: StyledRect {
        id: selector

        required property list<string> labels
        property list<string> icons: []
        property int currentIndex
        signal selected(int index)

        Layout.fillWidth: true
        implicitHeight: 48
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainerHigh

        readonly property real segmentWidth: (width - 8) / Math.max(1, labels.length)

        StyledRect {
            x: 4 + selector.currentIndex * selector.segmentWidth
            y: 4
            width: selector.segmentWidth
            height: parent.height - 8
            radius: Tokens.rounding.medium
            color: Colours.palette.m3secondaryContainer

            Behavior on x {
                Anim { type: Anim.Emphasized }
            }
        }

        Row {
            anchors.fill: parent
            anchors.margins: 4

            Repeater {
                model: selector.labels

                Item {
                    required property string modelData
                    required property int index
                    width: selector.segmentWidth
                    height: parent.height

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            visible: selector.icons.length > index && selector.icons[index].length > 0
                            text: visible ? selector.icons[index] : ""
                            color: index === selector.currentIndex ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.small
                            fill: index === selector.currentIndex ? 1 : 0
                        }

                        StyledText {
                            text: parent.parent.modelData
                            color: index === selector.currentIndex ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.large
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: selector.selected(index)
                    }
                }
            }
        }
    }

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

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                text: qsTr("Dynamic desktop")
                                font: Tokens.font.title.large
                            }

                            StyledText {
                                text: qsTr("Add motion to the desktop with video or web content")
                                color: Colours.palette.m3outline
                                font: Tokens.font.label.small
                            }
                        }

                        SegmentedSlider {
                            labels: [qsTr("Video"), qsTr("Web")]
                            icons: ["movie", "language"]
                            currentIndex: root.desktopMode === "video" ? 0 : 1
                            onSelected: index => {
                                if (index === 0) {
                                    root.desktopMode = "video";
                                } else {
                                    root.desktopMode = "html";
                                }
                                root.syncDesktopSource();
                                root.desktopMessage = "";
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.small

                        M3TextField {
                            id: desktopSource
                            Layout.fillWidth: true
                            label: root.desktopMode === "video" ? qsTr("Video files") : qsTr("HTML file or URL")
                            placeholder: root.desktopMode === "video" ? "/home/user/Videos/wallpaper.mp4" : "https://example.com"
                            text: root.desktopMode === "video" ? root.videoSource : root.htmlSource
                            leadingIcon: root.desktopMode === "video" ? "movie" : "language"
                            supportingText: root.desktopMode === "video" ? qsTr("Supports MP4, WebM, MKV, MOV, M4V and AVI; local 1080p video is recommended.") : qsTr("You can also enter an http(s) URL directly.")
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
                            text: qsTr("Picture fit")
                            font: Tokens.font.body.medium
                            color: Colours.palette.m3onSurfaceVariant
                        }

                        SegmentedSlider {
                            labels: [qsTr("Fill screen"), qsTr("Fit entire picture"), qsTr("Stretch to fill")]
                            icons: ["crop_free", "fit_screen", "open_in_full"]
                            currentIndex: root.desktopFit === "cover" ? 0 : root.desktopFit === "contain" ? 1 : 2
                            onSelected: index => root.desktopFit = ["cover", "contain", "stretch"][index]
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: root.desktopMessage
                        color: root.desktopMessage.includes(qsTr("Failed")) || root.desktopMessage.includes(qsTr("Unavailable")) ? Colours.palette.m3error : Colours.palette.m3outline
                        font: Tokens.font.label.small
                        wrapMode: Text.WordWrap
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Tokens.spacing.extraSmall
                        spacing: Tokens.spacing.medium

                        StyledText {
                            Layout.fillWidth: true
                            text: root.desktopMode === "video" ? qsTr("Video plays muted and loops") : qsTr("Web content runs in a separate view")
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }

                        IconTextButton {
                            icon: "stop_circle"
                            text: qsTr("Stop")
                            type: IconTextButton.Tonal
                            disabled: root.desktopBusy
                            onClicked: {
                                root.desktopBusy = true;
                                desktopStop.running = true;
                            }
                        }

                        IconTextButton {
                            icon: "check"
                            text: root.desktopBusy ? qsTr("Applying") : qsTr("Application")
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
                                text: qsTr("Appearance")
                                font: Tokens.font.title.large
                            }

                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.large

                        StyledText {
                            Layout.fillWidth: true
                            text: qsTr("Theme mode")
                            font: Tokens.font.body.medium
                        }

                        ButtonRow {
                            spacing: 0

                            IconTextButton {
                                icon: "dark_mode"
                                text: qsTr("Dark")
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
                                text: qsTr("Light")
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
                                text: qsTr("Automatic")
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
                            text: qsTr("Theme colour")
                            font: Tokens.font.body.medium
                        }

                        ButtonRow {
                            spacing: Tokens.spacing.extraSmall

                            PresetButton {
                                presetName: "blue"
                                presetColour: "#366385"
                                text: qsTr("Ocean")
                            }

                            PresetButton {
                                presetName: "teal"
                                presetColour: "#1c6a66"
                                text: qsTr("Teal")
                            }

                            PresetButton {
                                presetName: "violet"
                                presetColour: "#7657a8"
                                text: qsTr("Violet")
                            }

                            PresetButton {
                                presetName: "green"
                                presetColour: "#437653"
                                text: qsTr("Forest")
                            }

                            PresetButton {
                                presetName: "rose"
                                presetColour: "#9a526f"
                                text: qsTr("Rose")
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
                                text: qsTr("Transparency")
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
