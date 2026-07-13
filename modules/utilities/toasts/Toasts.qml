pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    readonly property int spacing: Tokens.spacing.extraSmall
    property bool flag

    function shouldShowToast(toast: Toast): bool {
        if (!Notifs.hasFullscreen())
            return true;
        if (Config.utilities.toasts.fullscreen === "all")
            return true;
        if (Config.utilities.toasts.fullscreen === "important")
            return toast.type === Toast.Warning || toast.type === Toast.Error;
        return false;
    }

    // Content-sized stack (capsules hug text); keep a modest max width.
    implicitWidth: {
        let w = 0;
        for (let i = 0; i < repeater.count; i++) {
            const item = repeater.itemAt(i) as ToastWrapper;
            if (item && !item.modelData.closed && !item.previewHidden)
                w = Math.max(w, item.implicitWidth);
        }
        return Math.max(w, 1);
    }
    implicitHeight: {
        let h = -spacing;
        for (let i = 0; i < repeater.count; i++) {
            const item = repeater.itemAt(i) as ToastWrapper;
            if (!item.modelData.closed && !item.previewHidden)
                h += item.implicitHeight + spacing;
        }
        return Math.max(h, 0);
    }

    Repeater {
        id: repeater

        model: ScriptModel {
            values: {
                const toasts = [];
                let count = 0;
                for (const toast of Toaster.toasts) {
                    if (!root.shouldShowToast(toast))
                        continue;
                    toasts.push(toast);
                    if (!toast.closed) {
                        count++;
                        if (count > root.Config.utilities.maxToasts)
                            break;
                    }
                }
                return toasts;
            }
            onValuesChanged: root.flagChanged()
        }

        ToastWrapper {}
    }

    component ToastWrapper: MouseArea {
        id: toast

        required property int index
        required property Toast modelData

        readonly property bool previewHidden: {
            let extraHidden = 0;
            for (let i = 0; i < index; i++)
                if (Toaster.toasts[i].closed)
                    extraHidden++;
            return index >= Config.utilities.maxToasts + extraHidden;
        }

        onPreviewHiddenChanged: {
            if (initAnim.running && previewHidden)
                initAnim.stop();
        }

        opacity: modelData.closed || previewHidden ? 0 : 1
        scale: modelData.closed || previewHidden ? 0.85 : 1

        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: {
            root.flag; // Force update
            let y = 0;
            for (let i = 0; i < index; i++) {
                const item = repeater.itemAt(i) as ToastWrapper;
                if (item && !item.modelData.closed && !item.previewHidden)
                    y += item.implicitHeight + root.spacing;
            }
            return y;
        }

        implicitWidth: toastInner.implicitWidth
        implicitHeight: toastInner.implicitHeight

        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onClicked: modelData.close()

        Component.onCompleted: modelData.lock(this)

        Anim {
            id: initAnim

            Component.onCompleted: running = !toast.previewHidden

            target: toast
            properties: "opacity,scale"
            from: 0
            to: 1
        }

        ParallelAnimation {
            running: toast.modelData.closed
            onStarted: toast.anchors.bottomMargin = toast.anchors.bottomMargin
            onFinished: toast.modelData.unlock(toast)

            Anim {
                type: Anim.DefaultEffects
                target: toast
                property: "opacity"
                to: 0
            }
            Anim {
                target: toast
                property: "scale"
                to: 0.85
            }
        }

        ToastItem {
            id: toastInner

            modelData: toast.modelData
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Behavior on scale {
            Anim {}
        }

        Behavior on anchors.bottomMargin {
            Anim {}
        }
    }
}
