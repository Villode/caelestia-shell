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

    signal networkSelected(ap: Nmcli.AccessPoint)

    title: qsTr("网络")

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
            function onWifiEnabledChanged(): void {
                if (Nmcli.wifiEnabled)
                    wifiScanDelay.start();
            }

            target: Nmcli
        }

        // —— 有线 ——
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

        // —— 无线 ——
        ToggleRow {
            Layout.topMargin: Nmcli.hasAvailableEthernet ? Tokens.spacing.large : 0
            first: true
            text: qsTr("无线网络")
            font: Tokens.font.body.medium
            horizontalPadding: Tokens.padding.largeIncreased
            checked: Nmcli.wifiEnabled
            onToggled: Nmcli.enableWifi(checked)
        }

        ItemList {
            id: networkList

            showList: Nmcli.wifiEnabled
            placeholderIcon: Nmcli.wifiEnabled ? "wifi_find" : "signal_wifi_off"
            placeholderText: Nmcli.wifiEnabled ? qsTr("未找到网络") : qsTr("无线网络已关闭")
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
                property bool currentSelected
                property real textOpacity: (currentSelected || Nmcli.connectingSsid() === modelData.ssid) ? 0.5 : 1

                anchors.left: networkList.list.contentItem.left
                anchors.right: networkList.list.contentItem.right
                implicitHeight: networkLayout.implicitHeight + Tokens.padding.large * 2

                Behavior on textOpacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }

                Connections {
                    function onActiveChanged(): void {
                        if (network.modelData.active)
                            network.currentSelected = false;
                    }

                    target: network.modelData
                }

                Connections {
                    function onNetworkSelected(ap: Nmcli.AccessPoint): void {
                        if (ap !== network.modelData)
                            network.currentSelected = false;
                    }

                    target: root
                }

                StateLayer {
                    anchors.fill: parent
                    radius: Tokens.rounding.extraSmall
                    disabled: network.currentSelected || Nmcli.connectingSsid() === network.modelData.ssid
                    onClicked: {
                        if (network.modelData.active || Nmcli.hasSavedProfile(network.modelData.ssid)) {
                            root.nState.selectedWifiSsid = network.modelData.ssid;
                            root.nState.openSubPage(2);
                        } else {
                            NetworkConnection.handleConnect(network.modelData);
                            network.currentSelected = true;
                            root.networkSelected(network.modelData);
                        }
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
                                const sec = network.modelData.security || qsTr("开放");
                                if (network.modelData.active)
                                    return qsTr("%1 · 已连接").arg(sec);
                                if (Nmcli.hasSavedProfile(network.modelData.ssid))
                                    return qsTr("%1 · 已保存").arg(sec);
                                return qsTr("安全性：%1").arg(sec);
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

        // —— VPN ——
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
                                return qsTr("正在切换…");
                            if (VPN.status.state === "needs-auth")
                                return qsTr("需要身份验证");
                            if (VPN.status.state === "error")
                                return qsTr("错误");
                            return VPN.connected ? qsTr("已连接") : qsTr("未连接");
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
                                return modelData.active ? qsTr("%1 · 已连接").arg(kind) : qsTr("%1 · 未连接").arg(kind);
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
                    text: qsTr("暂无 VPN 配置")
                    font: Tokens.font.body.small
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("可通过 nmcli 或系统导入 OpenVPN / WireGuard 配置文件。也支持在快捷工具中启用 Warp、Tailscale 等提供商。")
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                    wrapMode: Text.WordWrap
                }
            }
        }

        // —— 其他 ——
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
                    text: qsTr("重新扫描无线网络")
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
