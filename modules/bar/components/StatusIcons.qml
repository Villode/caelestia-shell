pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

StyledRect {
    id: root

    readonly property string barPosition: {
        const value = String(Config.bar.position || "left").toLowerCase();
        if (value === "right" || value === "top")
            return value;
        return "left";
    }
    readonly property bool isVertical: barPosition !== "top"

    property color colour: Colours.palette.m3secondary
    readonly property alias items: iconColumn

    color: Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.full

    clip: true
    implicitWidth: root.isVertical ? Tokens.sizes.bar.innerWidth : (iconColumn.implicitWidth + Tokens.padding.medium * 2)
    implicitHeight: root.isVertical ? (iconColumn.implicitHeight + Tokens.padding.medium * 2) : Tokens.sizes.bar.innerWidth

    GridLayout {
        id: iconColumn

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.isVertical ? 0 : Tokens.padding.medium
        anchors.rightMargin: root.isVertical ? 0 : Tokens.padding.medium
        anchors.topMargin: root.isVertical ? Tokens.padding.medium : 0
        anchors.bottomMargin: root.isVertical ? Tokens.padding.medium : 0
        columns: root.isVertical ? 1 : 100
        rows: root.isVertical ? 100 : 1
        flow: root.isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight

        columnSpacing: Tokens.spacing.medium / 2
        rowSpacing: Tokens.spacing.medium / 2

        // Lock keys status
        WrappedLoader {
            name: "lockstatus"
            active: Config.bar.status.showLockStatus

            sourceComponent: ColumnLayout {
                spacing: 0

                Item {
                    implicitWidth: capslockIcon.implicitWidth
                    implicitHeight: Hypr.capsLock ? capslockIcon.implicitHeight : 0

                    MaterialIcon {
                        id: capslockIcon

                        anchors.centerIn: parent

                        scale: Hypr.capsLock ? 1 : 0.5
                        opacity: Hypr.capsLock ? 1 : 0

                        text: "keyboard_capslock_badge"
                        color: root.colour

                        Behavior on opacity {
                            Anim {
                                type: Anim.DefaultEffects
                            }
                        }

                        Behavior on scale {
                            Anim {}
                        }
                    }

                    Behavior on implicitHeight {
                        Anim {}
                    }
                }

                Item {
                    Layout.topMargin: root.isVertical && Hypr.capsLock && Hypr.numLock ? iconColumn.rowSpacing : 0
                    Layout.leftMargin: !root.isVertical && Hypr.capsLock && Hypr.numLock ? iconColumn.columnSpacing : 0

                    implicitWidth: numlockIcon.implicitWidth
                    implicitHeight: Hypr.numLock ? numlockIcon.implicitHeight : 0

                    MaterialIcon {
                        id: numlockIcon

                        anchors.centerIn: parent

                        scale: Hypr.numLock ? 1 : 0.5
                        opacity: Hypr.numLock ? 1 : 0

                        text: "looks_one"
                        color: root.colour

                        Behavior on opacity {
                            Anim {
                                type: Anim.DefaultEffects
                            }
                        }

                        Behavior on scale {
                            Anim {}
                        }
                    }

                    Behavior on implicitHeight {
                        Anim {}
                    }
                }
            }
        }

        // Audio icon
        WrappedLoader {
            name: "audio"
            active: Config.bar.status.showAudio

            sourceComponent: MaterialIcon {
                animate: true
                text: Icons.getVolumeIcon(Audio.volume, Audio.muted)
                color: root.colour
            }
        }

        // Microphone icon
        WrappedLoader {
            name: "audio"
            active: Config.bar.status.showMicrophone

            sourceComponent: MaterialIcon {
                animate: true
                text: Icons.getMicVolumeIcon(Audio.sourceVolume, Audio.sourceMuted)
                color: root.colour
            }
        }

        // Keyboard layout icon
        WrappedLoader {
            name: "kblayout"
            active: Config.bar.status.showKbLayout

            sourceComponent: StyledText {
                animate: true
                text: Hypr.kbLayout
                color: root.colour
                font: Tokens.font.mono.medium
            }
        }

        // Network icon
        WrappedLoader {
            name: "network"
            active: Config.bar.status.showNetwork && (!Nmcli.activeEthernet || Config.bar.status.showWifi)

            sourceComponent: MaterialIcon {
                animate: true
                text: Nmcli.active ? Icons.getNetworkIcon(Nmcli.active.strength ?? 0) : "wifi_off"
                color: root.colour
            }
        }

        // Ethernet icon
        WrappedLoader {
            name: "ethernet"
            active: Config.bar.status.showNetwork && Nmcli.activeEthernet

            sourceComponent: MaterialIcon {
                animate: true
                text: "cable"
                color: root.colour
            }
        }

        // Bluetooth section
        WrappedLoader {
            Layout.preferredWidth: root.isVertical ? undefined : implicitWidth
            Layout.preferredHeight: root.isVertical ? implicitHeight : undefined

            name: "bluetooth"
            active: Config.bar.status.showBluetooth

            sourceComponent: GridLayout {
                columns: root.isVertical ? 1 : 100
                rows: root.isVertical ? 100 : 1
                flow: root.isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                columnSpacing: Tokens.spacing.medium / 2
                rowSpacing: Tokens.spacing.medium / 2

                // Bluetooth icon
                MaterialIcon {
                    animate: true
                    text: {
                        if (!Bluetooth.defaultAdapter?.enabled) // qmllint disable unresolved-type
                            return "bluetooth_disabled";
                        if (Bluetooth.devices.values.some(d => d.connected)) // qmllint disable unresolved-type
                            return "bluetooth_connected";
                        return "bluetooth";
                    }
                    color: root.colour
                }

                // Connected bluetooth devices
                Repeater {
                    model: ScriptModel {
                        values: Bluetooth.devices.values.filter(d => d.state !== BluetoothDeviceState.Disconnected) // qmllint disable unresolved-type
                    }

                    MaterialIcon {
                        id: device

                        required property BluetoothDevice modelData

                        animate: true
                        text: Icons.getBluetoothIcon(modelData?.icon)
                        color: root.colour
                        fill: 1

                        SequentialAnimation on opacity {
                            running: device.modelData?.state !== BluetoothDeviceState.Connected // qmllint disable unresolved-type
                            alwaysRunToEnd: true
                            loops: Animation.Infinite

                            Anim {
                                from: 1
                                to: 0
                                duration: Tokens.anim.durations.large
                                easing: Tokens.anim.standardAccel
                            }
                            Anim {
                                from: 0
                                to: 1
                                duration: Tokens.anim.durations.large
                                easing: Tokens.anim.standardDecel
                            }
                        }
                    }
                }
            }

            Behavior on Layout.preferredWidth {
                Anim {}
            }

            Behavior on Layout.preferredHeight {
                Anim {}
            }
        }

        // Battery icon
        WrappedLoader {
            name: "battery"
            active: Config.bar.status.showBattery

            sourceComponent: MaterialIcon {
                animate: true
                text: {
                    if (!UPower.displayDevice.isLaptopBattery) {
                        if (PowerProfiles.profile === PowerProfile.PowerSaver)
                            return "energy_savings_leaf";
                        if (PowerProfiles.profile === PowerProfile.Performance)
                            return "rocket_launch";
                        return "balance";
                    }
                    return Icons.getBatteryIcon(UPower.displayDevice.percentage, [UPowerDeviceState.Charging, UPowerDeviceState.FullyCharged, UPowerDeviceState.PendingCharge].includes(UPower.displayDevice.state));
                }
                color: !UPower.onBattery || UPower.displayDevice.percentage > 0.2 ? root.colour : Colours.palette.m3error
                fill: 1
            }
        }
    }

    component WrappedLoader: Loader {
        required property string name

        asynchronous: true
        Layout.alignment: Qt.AlignHCenter
        visible: active
    }
}
