pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

FocusScope {
    id: root

    property real value
    property real max: Infinity
    property real min: -Infinity
    property real step: 1
    property alias repeatRate: timer.interval

    signal valueModified(value: real)

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    function decimalsForStep(): int {
        return root.step < 1 ? Math.max(1, Math.ceil(-Math.log10(root.step))) : 0;
    }

    function roundToStep(v: real): real {
        const d = root.decimalsForStep();
        const f = Math.pow(10, d);
        return Math.round(v * f) / f;
    }

    function clamp(v: real): real {
        return Math.max(root.min, Math.min(root.max, v));
    }

    function formatValue(v: real): string {
        const d = root.decimalsForStep();
        if (d <= 0)
            return String(Math.round(v));
        // Trim trailing zeros for fractional steps (e.g. 1.50 → 1.5)
        let s = Number(v).toFixed(d);
        if (s.indexOf(".") >= 0)
            s = s.replace(/\.?0+$/, "");
        return s;
    }

    function syncFieldFromValue(): void {
        const t = root.formatValue(root.value);
        if (textField.text !== t)
            textField.text = t;
    }

    function applyFieldText(emitSignal: bool): bool {
        const numValue = parseFloat(textField.text);
        if (isNaN(numValue)) {
            root.syncFieldFromValue();
            return false;
        }
        const clamped = root.roundToStep(root.clamp(numValue));
        const changed = Math.abs(clamped - root.value) > 1e-9;
        root.value = clamped;
        root.syncFieldFromValue();
        if (emitSignal && changed)
            root.valueModified(clamped);
        else if (emitSignal && !changed)
            root.valueModified(clamped); // still notify so parent can re-apply
        return true;
    }

    function stepBy(delta: real): void {
        // Leave edit mode so the field always shows the stepped value.
        if (textField.activeFocus)
            root.forceActiveFocus();
        const next = root.roundToStep(root.clamp(root.value + delta));
        if (Math.abs(next - root.value) < 1e-9 && delta !== 0) {
            root.syncFieldFromValue();
            return;
        }
        root.value = next;
        root.syncFieldFromValue();
        root.valueModified(next);
    }

    onValueChanged: {
        // External / binding updates — don't clobber while typing.
        if (!textField.activeFocus)
            root.syncFieldFromValue();
    }

    Component.onCompleted: root.syncFieldFromValue()

    RowLayout {
        id: row

        anchors.fill: parent
        spacing: Tokens.spacing.small

        StyledTextField {
            id: textField

            Layout.preferredWidth: 72
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            horizontalAlignment: TextInput.AlignHCenter
            validator: DoubleValidator {
                bottom: root.min
                top: root.max
                decimals: root.decimalsForStep()
            }

            onActiveFocusChanged: {
                if (activeFocus) {
                    selectAll();
                } else {
                    root.applyFieldText(true);
                }
            }
            onAccepted: {
                root.applyFieldText(true);
                root.forceActiveFocus();
            }
            Keys.onEscapePressed: {
                root.syncFieldFromValue();
                root.forceActiveFocus();
            }

            padding: Tokens.padding.extraSmall
            leftPadding: Tokens.padding.medium
            rightPadding: Tokens.padding.medium

            background: StyledRect {
                implicitWidth: 72
                radius: Tokens.rounding.medium
                color: Colours.tPalette.m3surfaceContainerHigh
            }
        }

        StyledRect {
            radius: Tokens.rounding.medium
            color: Colours.palette.m3primary

            implicitWidth: implicitHeight
            implicitHeight: upIcon.implicitHeight + Tokens.padding.small

            StateLayer {
                id: upState

                color: Colours.palette.m3onPrimary
                // Take focus off the text field before handling the click.
                onPressed: root.forceActiveFocus()
                onPressAndHold: timer.start()
                onReleased: timer.stop()
                onCanceled: timer.stop()
                onClicked: root.stepBy(root.step)
            }

            MaterialIcon {
                id: upIcon
                anchors.centerIn: parent
                text: "keyboard_arrow_up"
                color: Colours.palette.m3onPrimary
            }
        }

        StyledRect {
            radius: Tokens.rounding.medium
            color: Colours.palette.m3primary

            implicitWidth: implicitHeight
            implicitHeight: downIcon.implicitHeight + Tokens.padding.small

            StateLayer {
                id: downState

                color: Colours.palette.m3onPrimary
                onPressed: root.forceActiveFocus()
                onPressAndHold: timer.start()
                onReleased: timer.stop()
                onCanceled: timer.stop()
                onClicked: root.stepBy(-root.step)
            }

            MaterialIcon {
                id: downIcon
                anchors.centerIn: parent
                text: "keyboard_arrow_down"
                color: Colours.palette.m3onPrimary
            }
        }
    }

    Timer {
        id: timer

        interval: 100
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (upState.pressed)
                root.stepBy(root.step);
            else if (downState.pressed)
                root.stepBy(-root.step);
        }
    }
}
