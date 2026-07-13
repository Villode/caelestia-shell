pragma Singleton

import QtQuick

QtObject {
    id: root

    readonly property list<var> pages: [
        // Appearance
        {
            label: qsTr("壁纸和样式"),
            icon: "palette",
            description: qsTr("壁纸、字体、颜色"),
            category: "appearance"
        },

        // Connectivity
        {
            label: qsTr("显示"),
            icon: "monitor",
            description: qsTr("分辨率、界面缩放、显示缩放"),
            category: "connectivity"
        },
        {
            label: qsTr("鼠标和触摸板"),
            icon: "touchpad_mouse",
            description: qsTr("触摸板开关"),
            category: "connectivity"
        },
        {
            label: qsTr("网络"),
            icon: "wifi",
            description: qsTr("无线网络、有线网络"),
            category: "connectivity"
        },
        {
            label: qsTr("已连接设备"),
            icon: "devices_other",
            description: qsTr("蓝牙、配对"),
            category: "connectivity",
            noFill: true
        },
        {
            label: qsTr("音频"),
            icon: "volume_up",
            description: qsTr("应用音量、声音设备"),
            category: "connectivity"
        },

        // System
        {
            label: qsTr("Villode 更新"),
            icon: "update",
            description: qsTr("同步 Shell、中文化与桌面组件"),
            category: "system"
        },
        {
            label: qsTr("锁屏与电源"),
            icon: "power_settings_new",
            description: qsTr("锁屏、关屏、睡眠与空闲超时"),
            category: "system"
        },
        {
            label: qsTr("插件"),
            icon: "extension",
            description: qsTr("管理插件"),
            category: "system"
        },

        // Shell
        {
            label: qsTr("面板"),
            icon: "dock_to_bottom",
            description: qsTr("仪表盘、任务栏、启动器、侧边栏"),
            category: "shell"
        },
        {
            label: qsTr("应用"),
            icon: "apps",
            description: qsTr("默认应用、收藏、隐藏应用"),
            category: "shell"
        },
        {
            label: qsTr("服务"),
            icon: "build",
            description: qsTr("轮询间隔、歌词后端"),
            category: "shell"
        },
        {
            label: qsTr("语言和地区"),
            icon: "globe",
            description: qsTr("界面语言、天气位置、显示单位"),
            category: "shell"
        },

        // About
        {
            label: qsTr("关于"),
            icon: "info",
            description: qsTr("系统信息、致谢"),
            category: "about"
        },
    ]
}
