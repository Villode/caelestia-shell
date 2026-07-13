pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

// Wi-Fi 已连接（或已保存）网络的详情与设置页。
PageBase {
    id: root

    readonly property string ssid: nState.selectedWifiSsid
    readonly property var accessPoint: Nmcli.networks.find(n => n.ssid === root.ssid) ?? null
    readonly property string connectionName: Nmcli.resolveWifiConnectionName(root.ssid)
    readonly property var details: Nmcli.wirelessDeviceDetails
    readonly property bool isActive: !!(root.accessPoint && root.accessPoint.active)

    property string ipMethod: "auto"
    property bool ipLoaded: false
    property bool formDirty: false // user touched the form; block async reloads
    property bool savingIp: false
    property bool autoconnect: true
    property string metered: "unknown" // yes | no | unknown
    property bool busyAction: false

    // 分享：密码 + 二维码
    property string wifiPassword: ""
    property bool showPassword: false
    property bool secretsLoaded: false
    property string qrImagePath: ""
    property string qrStatus: "" // "", loading, ready, error, missing
    property string passwordCopiedHint: ""

    property string origMethod: "auto"
    property string origAddress: ""
    property string origGateway: ""
    property string origDns: ""

    readonly property bool hasChanges: root.ipLoaded && (root.ipMethod !== root.origMethod || (root.ipMethod === "manual" && (addressField.text.trim() !== root.origAddress || gatewayField.text.trim() !== root.origGateway)) || ((root.ipMethod === "manual" || root.ipMethod === "auto-dns") && dnsField.text.trim() !== root.origDns))
    readonly property string maskedPassword: root.wifiPassword ? "•".repeat(Math.min(root.wifiPassword.length, 24)) : ""

    title: root.ssid || qsTr("无线网络")
    isSubPage: true

    // Live status only (IP/MAC rows). Never reloads the form — that was
    // resetting ipMethod back to "auto" every few seconds while editing.
    function refreshLiveStatus(): void {
        const iface = Nmcli.wirelessInterfaces.find(i => Nmcli.isConnectedState(i.state));
        if (iface && iface.device)
            Nmcli.getWirelessDeviceDetails(iface.device, () => {});
    }

    function loadIpConfig(): void {
        if (!root.connectionName)
            return;
        Nmcli.getIpv4Config(root.connectionName, cfg => {
            if (!cfg)
                return;
            // Never clobber in-progress edits (timer races / late nmcli replies).
            if (root.formDirty)
                return;
            root.ipMethod = cfg.method;
            addressField.text = cfg.address;
            gatewayField.text = cfg.gateway;
            dnsField.text = cfg.dns;
            root.origMethod = cfg.method;
            root.origAddress = cfg.address;
            root.origGateway = cfg.gateway;
            root.origDns = cfg.dns;
            root.ipLoaded = true;
        });
    }

    function loadFlags(): void {
        if (!root.connectionName)
            return;
        Nmcli.getConnectionFlags(root.connectionName, flags => {
            if (!flags)
                return;
            root.autoconnect = flags.autoconnect;
            root.metered = flags.metered || "unknown";
        });
    }

    function loadShareInfo(): void {
        if (!root.connectionName) {
            root.secretsLoaded = true;
            root.qrStatus = "missing";
            return;
        }
        root.qrStatus = "loading";
        Nmcli.getWifiSecrets(root.connectionName, secrets => {
            root.secretsLoaded = true;
            if (!secrets) {
                root.wifiPassword = "";
                root.qrStatus = "error";
                root.qrImagePath = "";
                return;
            }
            root.wifiPassword = secrets.password || "";
            if (!secrets.payload) {
                root.qrStatus = "error";
                return;
            }
            // Stable path so Image can reload after generation.
            const cacheBase = Quickshell.env("XDG_CACHE_HOME") || `${Quickshell.env("HOME")}/.cache`;
            const dir = `${cacheBase}/villode-caelestia/wifi-qr`;
            const safeName = (root.ssid || "wifi").replace(/[^a-zA-Z0-9._-]+/g, "_").slice(0, 48);
            const outPath = `${dir}/${safeName}.png`;
            Nmcli.generateWifiQrImage(secrets.payload, outPath, result => {
                if (result && result.success) {
                    root.qrImagePath = "";
                    root.qrImagePath = "file://" + outPath + "?t=" + Date.now();
                    root.qrStatus = "ready";
                } else {
                    root.qrImagePath = "";
                    root.qrStatus = "error";
                }
            });
        });
    }

    function copyPassword(): void {
        if (!root.wifiPassword)
            return;
        Quickshell.clipboardText = root.wifiPassword;
        root.passwordCopiedHint = qsTr("已复制");
        copyHintTimer.restart();
    }

    function saveIpConfig(): void {
        if (!root.connectionName)
            return;
        root.savingIp = true;
        Nmcli.setIpv4Config(root.connectionName, {
            method: root.ipMethod,
            address: addressField.text.trim(),
            gateway: gatewayField.text.trim(),
            dns: dnsField.text.trim()
        }, result => {
            root.savingIp = false;
            if (!(result && result.success)) {
                if (root.ipMethod === "manual")
                    addressField.isError = true;
                else
                    dnsField.isError = true;
            } else {
                root.origMethod = root.ipMethod;
                root.origAddress = addressField.text.trim();
                root.origGateway = gatewayField.text.trim();
                root.origDns = dnsField.text.trim();
                root.formDirty = false;
                root.refreshLiveStatus();
            }
        });
    }

    Component.onCompleted: {
        root.refreshLiveStatus();
        root.loadIpConfig();
        root.loadFlags();
        root.loadShareInfo();
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Timer {
            id: copyHintTimer
            interval: 1800
            onTriggered: root.passwordCopiedHint = ""
        }

        Timer {
            running: root.visible && root.isActive
            repeat: true
            interval: 5000
            onTriggered: root.refreshLiveStatus()
        }

        // —— 分享：二维码 + 密码 ——
        SectionHeader {
            first: true
            text: qsTr("分享网络")
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: shareCol.implicitHeight + Tokens.padding.large * 2

            ColumnLayout {
                id: shareCol
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                // QR
                StyledRect {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 200
                    implicitHeight: 200
                    radius: Tokens.rounding.large
                    color: "white"

                    Image {
                        anchors.centerIn: parent
                        width: 176
                        height: 176
                        visible: root.qrStatus === "ready" && root.qrImagePath
                        source: root.qrImagePath
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: false
                        smooth: false
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall
                        visible: root.qrStatus !== "ready"

                        MaterialIcon {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.qrStatus === "loading" ? "hourglass_top" : "qr_code_2"
                            color: Colours.palette.m3outline
                            fontStyle: Tokens.font.icon.large
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.qrStatus === "loading" ? qsTr("生成中…") : root.qrStatus === "error" ? qsTr("无法生成二维码") : qsTr("暂无二维码")
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("用手机相机扫描即可加入此网络")
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                }

                // Password row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: "password"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            text: qsTr("密码")
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                if (!root.secretsLoaded)
                                    return qsTr("读取中…");
                                if (!root.wifiPassword)
                                    return qsTr("无密码（开放网络）或无法读取");
                                return root.showPassword ? root.wifiPassword : root.maskedPassword;
                            }
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }
                    }

                    IconButton {
                        visible: root.wifiPassword.length > 0
                        type: IconButton.Tonal
                        isRound: true
                        icon: root.showPassword ? "visibility_off" : "visibility"
                        onClicked: root.showPassword = !root.showPassword
                    }

                    IconButton {
                        visible: root.wifiPassword.length > 0
                        type: IconButton.Tonal
                        isRound: true
                        icon: root.passwordCopiedHint ? "check" : "content_copy"
                        onClicked: root.copyPassword()
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.passwordCopiedHint.length > 0
                    horizontalAlignment: Text.AlignHCenter
                    text: root.passwordCopiedHint
                    color: Colours.palette.m3primary
                    font: Tokens.font.label.small
                }
            }
        }

        // —— 连接信息 ——
        SectionHeader {
            text: qsTr("连接信息")
        }

        InfoRow {
            first: true
            icon: "link"
            label: qsTr("状态")
            value: root.isActive ? qsTr("已连接") : (Nmcli.hasSavedProfile(root.ssid) ? qsTr("已保存") : qsTr("未连接"))
        }

        InfoRow {
            icon: "wifi"
            label: qsTr("网络名称")
            value: root.ssid || qsTr("—")
        }

        InfoRow {
            icon: "security"
            label: qsTr("安全性")
            value: root.accessPoint?.security || qsTr("—")
        }

        InfoRow {
            icon: "network_wifi"
            label: qsTr("信号强度")
            visible: root.accessPoint !== null
            value: root.accessPoint ? `${root.accessPoint.strength}%` : qsTr("—")
        }

        InfoRow {
            icon: "lan"
            label: qsTr("IP 地址")
            visible: root.isActive
            value: root.details?.ipAddress || qsTr("—")
        }

        InfoRow {
            icon: "router"
            label: qsTr("网关")
            visible: root.isActive
            value: root.details?.gateway || qsTr("—")
        }

        InfoRow {
            icon: "dns"
            label: qsTr("DNS")
            visible: root.isActive
            value: (root.details?.dns && root.details.dns.length) ? root.details.dns.join(", ") : qsTr("—")
        }

        InfoRow {
            last: true
            icon: "memory"
            label: qsTr("MAC 地址")
            visible: root.isActive
            value: root.details?.macAddress || qsTr("—")
        }

        // —— 偏好 ——
        SectionHeader {
            text: qsTr("偏好设置")
        }

        ToggleRow {
            first: true
            text: qsTr("自动连接")
            subtext: qsTr("在范围内时自动加入此网络")
            checked: root.autoconnect
            onToggled: {
                root.autoconnect = checked;
                Nmcli.setAutoconnect(root.connectionName, checked, () => {});
            }
        }

        ToggleRow {
            last: true
            text: qsTr("按流量计费")
            subtext: qsTr("系统将减少此网络上的后台数据")
            checked: root.metered === "yes" || root.metered === "true"
            onToggled: {
                root.metered = checked ? "yes" : "no";
                Nmcli.setConnectionMetered(root.connectionName, root.metered, () => {});
            }
        }

        // —— IPv4（内联选项，避免下拉在滚动页里被误关）——
        SectionHeader {
            text: qsTr("IPv4")
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: root.ipMethod === "auto"
            implicitHeight: ipMethodCol.implicitHeight + Tokens.padding.small * 2

            ColumnLayout {
                id: ipMethodCol
                anchors.fill: parent
                anchors.margins: Tokens.padding.extraSmall
                spacing: 0

                IpMethodOption {
                    methodId: "auto"
                    iconName: "lan"
                    label: qsTr("自动 (DHCP)")
                    first: true
                    last: false
                }

                IpMethodOption {
                    methodId: "auto-dns"
                    iconName: "dns"
                    label: qsTr("自动，仅自定义 DNS")
                    first: false
                    last: false
                }

                IpMethodOption {
                    methodId: "manual"
                    iconName: "edit"
                    label: qsTr("手动")
                    first: false
                    last: true
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.large
            spacing: Tokens.spacing.large
            visible: root.ipMethod === "manual" || root.ipMethod === "auto-dns"

            M3TextField {
                id: addressField
                Layout.fillWidth: true
                visible: root.ipMethod === "manual"
                label: qsTr("地址 (CIDR)")
                placeholder: qsTr("192.168.1.50/24")
                leadingIcon: "router"
                supportingText: qsTr("IP 与前缀，例如 192.168.1.50/24")
                errorText: qsTr("请输入有效的 CIDR 地址")
                inputMethodHints: Qt.ImhNoPredictiveText
                onTextChanged: if (root.ipLoaded && text !== root.origAddress)
                    root.formDirty = true
            }

            M3TextField {
                id: gatewayField
                Layout.fillWidth: true
                visible: root.ipMethod === "manual"
                label: qsTr("网关")
                placeholder: qsTr("192.168.1.1")
                leadingIcon: "exit_to_app"
                inputMethodHints: Qt.ImhNoPredictiveText
                onTextChanged: if (root.ipLoaded && text !== root.origGateway)
                    root.formDirty = true
            }

            M3TextField {
                id: dnsField
                Layout.fillWidth: true
                label: qsTr("DNS 服务器")
                placeholder: qsTr("1.1.1.1, 8.8.8.8")
                leadingIcon: "dns"
                supportingText: qsTr("多个地址用逗号分隔")
                errorText: qsTr("请输入有效的 DNS 地址")
                inputMethodHints: Qt.ImhNoPredictiveText
                onTextChanged: if (root.ipLoaded && text !== root.origDns)
                    root.formDirty = true
            }
        }

        // 应用 IPv4 — 轻量文字按钮
        ConnectedRect {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            first: true
            last: true
            visible: root.hasChanges || root.savingIp
            implicitHeight: applyRow.implicitHeight + Tokens.padding.medium * 2
            color: Colours.palette.m3primaryContainer

            StateLayer {
                radius: parent.topLeftRadius
                disabled: !root.ipLoaded || root.savingIp
                onClicked: if (root.ipLoaded && !root.savingIp)
                    root.saveIpConfig()
            }

            RowLayout {
                id: applyRow
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased

                Item {
                    Layout.fillWidth: true
                }

                AnimLoader {
                    sourceComp: root.savingIp ? applyLoadingComp : applyTextComp
                }

                Item {
                    Layout.fillWidth: true
                }
            }

            Component {
                id: applyLoadingComp
                LoadingIndicator {
                    implicitSize: Math.round(Tokens.font.body.medium.pointSize * 1.3)
                }
            }

            Component {
                id: applyTextComp
                StyledText {
                    text: qsTr("应用 IP 设置")
                    color: Colours.palette.m3onPrimaryContainer
                    font: Tokens.font.body.small
                }
            }
        }

        // —— 操作（Mac 风格列表行）——
        SectionHeader {
            text: qsTr("操作")
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: false
            implicitHeight: disconnectRow.implicitHeight + Tokens.padding.medium * 2

            StateLayer {
                radius: parent.topLeftRadius
                disabled: root.busyAction
                onClicked: {
                    root.busyAction = true;
                    if (root.isActive) {
                        Nmcli.disconnectFromNetwork();
                        Qt.callLater(() => {
                            root.busyAction = false;
                            root.nState.closeSubPage();
                        }, 600);
                    } else {
                        const ap = root.accessPoint;
                        if (ap)
                            NetworkConnection.handleConnect(ap);
                        else
                            Nmcli.connectToNetwork(root.ssid, "", "", null);
                        Qt.callLater(() => root.busyAction = false, 1500);
                    }
                }
            }

            RowLayout {
                id: disconnectRow
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.isActive ? qsTr("断开连接") : qsTr("连接")
                    color: Colours.palette.m3primary
                    font: Tokens.font.body.small
                    opacity: root.busyAction ? 0.5 : 1
                }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: false
            last: true
            implicitHeight: forgetRow.implicitHeight + Tokens.padding.medium * 2

            StateLayer {
                radius: parent.bottomLeftRadius
                disabled: root.busyAction || !root.connectionName
                onClicked: {
                    root.busyAction = true;
                    Nmcli.forgetNetwork(root.ssid, () => {
                        root.busyAction = false;
                        root.nState.closeSubPage();
                    });
                }
            }

            RowLayout {
                id: forgetRow
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("忘记此网络")
                    color: Colours.palette.m3error
                    font: Tokens.font.body.small
                    opacity: (root.busyAction || !root.connectionName) ? 0.4 : 1
                }
            }
        }
    }

    // Mac 风格单选行：点选即切换，无弹出菜单
    component IpMethodOption: Item {
        id: opt

        required property string methodId
        required property string iconName
        required property string label
        property bool first
        property bool last

        readonly property bool selected: root.ipMethod === methodId

        Layout.fillWidth: true
        implicitHeight: optRow.implicitHeight + Tokens.padding.medium * 2

        StateLayer {
            anchors.fill: parent
            radius: {
                if (opt.first && opt.last)
                    return Tokens.rounding.large;
                if (opt.first)
                    return Tokens.rounding.large;
                if (opt.last)
                    return Tokens.rounding.large;
                return Tokens.rounding.extraSmall;
            }
            onClicked: {
                root.formDirty = true;
                root.ipMethod = opt.methodId;
            }
        }

        RowLayout {
            id: optRow
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.largeIncreased
            anchors.rightMargin: Tokens.padding.largeIncreased
            anchors.topMargin: Tokens.padding.medium
            anchors.bottomMargin: Tokens.padding.medium
            spacing: Tokens.spacing.medium

            MaterialIcon {
                text: opt.iconName
                color: opt.selected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }

            StyledText {
                Layout.fillWidth: true
                text: opt.label
                color: opt.selected ? Colours.palette.m3primary : Colours.palette.m3onSurface
                font: Tokens.font.body.small
            }

            MaterialIcon {
                visible: opt.selected
                text: "check"
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.small
            }
        }
    }
}
