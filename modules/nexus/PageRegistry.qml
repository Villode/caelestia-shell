pragma Singleton

import QtQuick

QtObject {
    id: root

    // NOTE: index-aligned with PageCompRegistry.pageComps — always add/remove entries in both.
    // Each entry has a stable `pageId` for deep-links (bar popouts, shortcuts); do not use raw indices.
    readonly property list<var> pages: [
        // Appearance
        {
            pageId: "appearance",
            label: qsTr("Wallpaper & style"),
            icon: "palette",
            description: qsTr("Wallpaper, fonts, colours"),
            category: "appearance"
        },

        // Connectivity
        {
            pageId: "display",
            label: qsTr("Display"),
            icon: "monitor",
            description: qsTr("Resolution, UI scale, display scaling"),
            category: "connectivity"
        },
        {
            pageId: "input",
            label: qsTr("Mouse & touchpad"),
            icon: "touchpad_mouse",
            description: qsTr("Touchpad and pointer controls"),
            category: "connectivity"
        },
        {
            pageId: "network",
            label: qsTr("Network"),
            icon: "wifi",
            description: qsTr("Wi-Fi, ethernet"),
            category: "connectivity"
        },
        {
            pageId: "bluetooth",
            label: qsTr("Connected devices"),
            icon: "devices_other",
            description: qsTr("Bluetooth, pairing"),
            category: "connectivity",
            noFill: true
        },
        {
            pageId: "audio",
            label: qsTr("Audio"),
            icon: "volume_up",
            description: qsTr("App volumes, sound devices"),
            category: "connectivity"
        },

        // System
        {
            pageId: "updates",
            label: qsTr("Villode updates"),
            icon: "update",
            description: qsTr("Sync Shell, translations and desktop components"),
            category: "system"
        },
        {
            pageId: "power",
            label: qsTr("Lock screen & power"),
            icon: "power_settings_new",
            description: qsTr("Lock, display off, sleep and idle timeouts"),
            category: "system"
        },
        {
            pageId: "shortcuts",
            label: qsTr("Keyboard shortcuts"),
            icon: "keyboard_command_key",
            description: qsTr("Record keys for apps, Shell and windows"),
            category: "system"
        },
        // Plugins entry hidden until a real plugin system exists.
        // {
        //     pageId: "plugins",
        //     label: qsTr("Plugins"),
        //     icon: "extension",
        //     description: qsTr("Manage plugins"),
        //     category: "system"
        // },

        // Shell
        {
            pageId: "panels",
            label: qsTr("Panels"),
            icon: "dock_to_bottom",
            description: qsTr("Dashboard, taskbar, launcher, sidebar"),
            category: "shell"
        },
        {
            pageId: "apps",
            label: qsTr("Apps"),
            icon: "apps",
            description: qsTr("Default apps, favourites, hidden apps"),
            category: "shell"
        },
        {
            pageId: "services",
            label: qsTr("Services"),
            icon: "build",
            description: qsTr("Poll intervals, lyrics backend"),
            category: "shell"
        },
        {
            pageId: "language",
            label: qsTr("Language & region"),
            icon: "globe",
            description: qsTr("Language, time zone, date and time, weather"),
            category: "shell"
        },

        // About
        {
            pageId: "about",
            label: qsTr("About"),
            icon: "info",
            description: qsTr("System information, credits"),
            category: "about"
        },
    ]

    function indexOf(pageId: string): int {
        for (let i = 0; i < pages.length; i++) {
            if (pages[i].pageId === pageId)
                return i;
        }
        return -1;
    }
}
