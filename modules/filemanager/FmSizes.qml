pragma ComponentBehavior: Bound

import QtQuick

// Shared layout constants (not a Quickshell singleton — avoid registration issues).
QtObject {
    readonly property int minItemWidth: 103
    readonly property int sidebarWidth: 230
}
