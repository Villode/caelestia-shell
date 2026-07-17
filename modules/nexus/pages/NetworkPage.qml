pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    signal networkSelected(var ap)

    // Inline Wi-Fi password sheet (settings has no bar password popout).
    property var pendingWifi: null
    property bool showWifiPassword: false
    property string wifiPassword: ""
    property bool wifiConnecting: false
    property string wifiConnectError: ""

    title: qsTr("Network")

    function askWifiPassword(network): void {
        root.pendingWifi = network;
        root.wifiPassword = "";
        root.wifiConnectError = "";
        root.wifiConnecting = false;
        root.showWifiPassword = true;
    }

    function cancelWifiPassword(): void {
        root.showWifiPassword = false;
        root.pendingWifi = null;
        root.wifiPassword = "";
        root.wifiConnectError = "";
        root.wifiConnecting = false;
        // Clear greyed-out selection state on all rows via signal
        root.networkSelected(null);
    }

    function submitWifiPassword(): void {
        if (!root.pendingWifi || root.wifiConnecting)
            return;
        const pass = root.wifiPassword;
        if (!pass || pass.length === 0)
            return;
        root.wifiConnecting = true;
        root.wifiConnectError = "";
        NetworkConnection.connectWithPassword(root.pendingWifi, pass, result => {
            root.wifiConnecting = false;
            if (result && result.success) {
                root.cancelWifiPassword();
                return;
            }
            root.wifiConnectError = qsTr("Connection failed. Check the password and try again.");
            root.wifiPassword = "";
        });
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Timer {
            running: root.visible && Nmcli.wifiEnabled
            repeat: true
            triggeredOnStart: true
            interval: GlobalConfig.nexus.networkRescanInterval
            onTriggered: Nmcli.rescanWifi()
        }

        Timer {
            id: wifiScanDelay
            interval: 100
            onTriggered: Nmcli.rescanWifi()
        }

        Timer {
            running: root.visible
            repeat: true
            triggeredOnStart: true
            interval: 4000
            onTriggered: Nmcli.refreshVpnConnections(() => {})
        }

        Connections {
            function onWifiEnabledChanged() {
                if (Nmcli.wifiEnabled)
                    wifiScanDelay.start();
            }

            target: Nmcli
        }

        // -- 有线 --
        Loader {
            Layout.fillWidth: true
            active: Nmcli.hasAvailableEthernet
            visible: active
            asynchronous: true

            sourceComponent: EthernetSection {
                nState: root.nState
                cappedWidth: root.cappedWidth
            }
        }

        // -- 无线 --
        ToggleRow {
            Layout.topMargin: Nmcli.hasAvailableEthernet ? Tokens.spacing.large : 0
            first: true
            text: qsTr("Wireless")
            font: Tokens.font.body.medium
            horizontalPadding: Tokens.padding.largeIncreased
            checked: Nmcli.wifiEnabled
            onToggled: Nmcli.enableWifi(checked)
        }

        ItemList {
            id: networkList

            showList: Nmcli.wifiEnabled
            placeholderIcon: Nmcli.wifiEnabled ? "wifi_find" : "signal_wifi_off"
            placeholderText: Nmcli.wifiEnabled ? qsTr("No networks found") : qsTr("Wireless is disabled")
            extraHeight: Nmcli.scanning ? Tokens.rounding.extraSmall : 0
            list.anchors.top: scanningIndicator.bottom

            model: ScriptModel {
                values: {
                    const connecting = Nmcli.connectingSsid();
                    const rank = n => n.active ? 0 : n.ssid === connecting ? 1 : Nmcli.hasSavedProfile(n.ssid) ? 2 : 3;
                    return [...Nmcli.networks].sort((a, b) => rank(a) - rank(b) || b.strength - a.strength);
                }
            }

            delegate: Item {
                id: network

                required property Nmcli.AccessPoint modelData
                property bool currentSelected: false
                property real textOpacity: (Nmcli.connectingSsid() === modelData.ssid || (root.pendingWifi && root.pendingWifi.ssid === modelData.ssid && root.wifiConnecting)) ? 0.5 : 1

                anchors.left: networkList.list.contentItem.left
                anchors.right: networkList.list.contentItem.right
                implicitHeight: networkLayout.implicitHeight + Tokens.padding.large * 2

                Behavior on textOpacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }

                Connections {
                    function onActiveChanged() {
                        if (network.modelData.active)
                            network.currentSelected = false;
                    }

                    target: network.modelData
                }

                Connections {
                    function onNetworkSelected(ap) {
                        if (!ap || ap !== network.modelData)
                            network.currentSelected = false;
                    }

                    target: root
                }

                StateLayer {
                    anchors.fill: parent
                    radius: Tokens.rounding.extraSmall
                    // Only disable while actively connecting to THIS ssid, not after a failed click.
                    disabled: Nmcli.connectingSsid() === network.modelData.ssid || root.wifiConnecting
                    onClicked: {
                        if (network.modelData.active || Nmcli.hasSavedProfile(network.modelData.ssid)) {
                            root.nState.selectedWifiSsid = network.modelData.ssid;
                            root.nState.openSubPage(2);
                            return;
                        }
                        network.currentSelected = false;
                        // New network: show password sheet under the Wi-Fi list for secured APs.
                        // Do not attempt connect first (would drop the current link without secrets).
                        const secured = network.modelData.isSecure || (network.modelData.security && network.modelData.security.length > 0 && network.modelData.security !== "--");
                        if (secured) {
                            root.askWifiPassword(network.modelData);
                            return;
                        }
                        NetworkConnection.handleConnect(network.modelData, null, n => root.askWifiPassword(n));
                    }
                }

                RowLayout {
                    id: networkLayout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    anchors.leftMargin: Tokens.padding.extraLarge
                    anchors.rightMargin: Tokens.padding.extraLarge
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: Icons.getNetworkIcon(network.modelData.strength)
                        color: network.modelData.active ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.medium
                        opacity: network.textOpacity
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        opacity: network.textOpacity

                        StyledText {
                            Layout.fillWidth: true
                            text: network.modelData.ssid
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                const sec = network.modelData.security || qsTr("Open");
                                if (network.modelData.active)
                                    return qsTr("%1 · Connected").arg(sec);
                                if (Nmcli.hasSavedProfile(network.modelData.ssid))
                                    return qsTr("%1 · Saved").arg(sec);
                                return qsTr("Security: %1").arg(sec);
                            }
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    IconButton {
                        visible: network.modelData.active
                        z: 2
                        type: IconButton.Tonal
                        isRound: true
                        icon: "link_off"
                        onClicked: Nmcli.disconnectFromNetwork()
                    }

                    AnimLoader {
                        sourceComp: Nmcli.connectingSsid() === network.modelData.ssid ? loadingComp : iconComp

                        Component {
                            id: iconComp

                            MaterialIcon {
                                text: network.modelData.active ? "settings" : (Nmcli.hasSavedProfile(network.modelData.ssid) ? "chevron_right" : "lock")
                                color: network.modelData.active ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                fontStyle: Tokens.font.icon.medium
                                opacity: network.textOpacity
                            }
                        }

                        Component {
                            id: loadingComp

                            LoadingIndicator {
                                implicitSize: Math.round(Tokens.font.icon.medium.pointSize * 1.3)
                            }
                        }
                    }
                }
            }

            StyledProgressBar {
                id: scanningIndicator

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 1
                implicitHeight: Nmcli.scanning ? Tokens.rounding.extraSmall : 0
                indeterminate: true

                Behavior on implicitHeight {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }
        }

        // -- Wi-Fi 密码（紧挨列表下方）--
        ConnectedRect {
            Layout.fillWidth: true
            visible: root.showWifiPassword
            first: true
            last: true
            implicitHeight: passCol.implicitHeight + Tokens.padding.large * 2

            ColumnLayout {
                id: passCol
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: root.pendingWifi ? qsTr("Connect to %1").arg(root.pendingWifi.ssid || "") : qsTr("Wi-Fi password")
                    font: Tokens.font.body.large
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Enter the network password. Your current connection stays up until this succeeds.")
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                    wrapMode: Text.WordWrap
                }

                M3TextField {
                    id: wifiPassField
                    Layout.fillWidth: true
                    label: qsTr("Password")
                    placeholder: qsTr("Wi-Fi password")
                    leadingIcon: "password"
                    password: true
                    text: root.wifiPassword
                    onTextChanged: root.wifiPassword = text
                    onAccepted: root.submitWifiPassword()
                    Component.onCompleted: {
                        if (root.showWifiPassword)
                            forceFieldFocus();
                    }
                }

                // Focus password field when sheet opens
                Connections {
                    target: root
                    function onShowWifiPasswordChanged() {
                        if (root.showWifiPassword)
                            Qt.callLater(function() { wifiPassField.forceFieldFocus(); });
                    }
                }

                StyledText {
                    visible: root.wifiConnectError.length > 0
                    Layout.fillWidth: true
                    text: root.wifiConnectError
                    color: Colours.palette.m3error
                    font: Tokens.font.label.small
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Item {
                        Layout.fillWidth: true
                    }

                    IconTextButton {
                        icon: "close"
                        text: qsTr("Cancel")
                        type: IconTextButton.Tonal
                        enabled: !root.wifiConnecting
                        onClicked: root.cancelWifiPassword()
                    }

                    IconTextButton {
                        icon: "link"
                        text: root.wifiConnecting ? qsTr("Connecting...") : qsTr("Connect")
                        type: IconTextButton.Filled
                        enabled: !root.wifiConnecting && root.wifiPassword.length > 0
                        onClicked: root.submitWifiPassword()
                    }
                }
            }
        }

        // -- VPN --
        SectionHeader {
            Layout.topMargin: Tokens.spacing.large - parent.spacing
            text: qsTr("VPN")
        }

        // 快捷工具中配置的 VPN 提供商（Warp / Tailscale / WireGuard 等）
        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: Nmcli.vpnConnections.length === 0 && !VPN.enabled
            visible: VPN.enabled
            implicitHeight: utilVpnLayout.implicitHeight + Tokens.padding.medium * 2

            RowLayout {
                id: utilVpnLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "vpn_key"
                    color: VPN.connected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: (VPN.currentConfig && VPN.currentConfig.displayName) ? VPN.currentConfig.displayName : qsTr("VPN")
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            if (VPN.connecting)
                                return qsTr("Switching...");
                            if (VPN.status.state === "needs-auth")
                                return qsTr("Authentication required");
                            if (VPN.status.state === "error")
                                return qsTr("Error");
                            return VPN.connected ? qsTr("Connected") : qsTr("Disconnected");
                        }
                        color: VPN.connected ? Colours.palette.m3primary : Colours.palette.m3outline
                        font: Tokens.font.label.small
                        elide: Text.ElideRight
                    }
                }

                IconButton {
                    type: IconButton.Tonal
                    isToggle: true
                    isRound: true
                    checked: VPN.connected && VPN.status.state !== "needs-auth" && VPN.status.state !== "error"
                    enabled: !VPN.connecting
                    icon: VPN.connected ? "link_off" : "link"
                    onClicked: VPN.toggle()
                }
            }
        }

        // NetworkManager 中的 VPN / WireGuard 配置
        Repeater {
            model: Nmcli.vpnConnections

            ConnectedRect {
                id: vpnRow

                required property var modelData
                required property int index

                Layout.fillWidth: true
                first: !VPN.enabled && index === 0
                last: index === Nmcli.vpnConnections.length - 1
                implicitHeight: vpnLayout.implicitHeight + Tokens.padding.medium * 2

                RowLayout {
                    id: vpnLayout
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: modelData.type === "wireguard" ? "shield" : "vpn_lock"
                        color: modelData.active ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.medium
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.name
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                const kind = modelData.type === "wireguard" ? "WireGuard" : "VPN";
                                return modelData.active ? qsTr("%1 · Connected").arg(kind) : qsTr("%1 · Disconnected").arg(kind);
                            }
                            color: modelData.active ? Colours.palette.m3primary : Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    IconButton {
                        type: IconButton.Tonal
                        isToggle: true
                        isRound: true
                        checked: modelData.active
                        icon: modelData.active ? "link_off" : "link"
                        onClicked: Nmcli.setVpnActive(modelData.name, !modelData.active, () => {})
                    }
                }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: !VPN.enabled && Nmcli.vpnConnections.length === 0
            last: true
            visible: !VPN.enabled && Nmcli.vpnConnections.length === 0
            implicitHeight: vpnEmptyLayout.implicitHeight + Tokens.padding.large * 2

            ColumnLayout {
                id: vpnEmptyLayout
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("No VPN configurations")
                    font: Tokens.font.body.small
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Import OpenVPN or WireGuard profiles using nmcli or your system. Providers such as Warp and Tailscale can also be enabled in quick utilities.")
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                    wrapMode: Text.WordWrap
                }
            }
        }

        // -- 其他 --
        ConnectedRect {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.large - parent.spacing
            first: true
            last: true
            implicitHeight: addNetworkLayout.implicitHeight + addNetworkLayout.anchors.margins * 2

            StateLayer {
                onClicked: {
                    // 重新扫描无线网络
                    if (Nmcli.wifiEnabled)
                        Nmcli.rescanWifi();
                }
            }

            RowLayout {
                id: addNetworkLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "refresh"
                    fontStyle: Tokens.font.icon.medium
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Rescan wireless networks")
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }
            }
        }
    }

    Component.onCompleted: {
        Nmcli.refreshVpnConnections(() => {});
        if (VPN.enabled)
            VPN.checkStatus();
    }
}
