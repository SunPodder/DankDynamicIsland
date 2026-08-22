pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import "../core/IslandLayout.js" as Layout

/**
 * Idle mode: a compact clock pill.
 *
 * Follows the shell's clock format settings (24h/12h, padded hours, custom
 * date format). The SystemClock restart on session resume works around clocks
 * freezing after suspend.
 */
Item {
    id: root

    // ---- palette (injected by DynamicIsland.qml) ----
    property color backgroundColor: Theme.surfaceContainerHigh
    property color foregroundColor: Theme.surfaceText

    implicitWidth: pill.width
    implicitHeight: pill.height

    readonly property int fontPixelSize: Theme.barTextSize(Layout.ISLAND_HEIGHT)

    readonly property string clockText: {
        const date = systemClock.date;
        if (!date)
            return "--:--";
        const hours = date.getHours();
        const minutes = String(date.getMinutes()).padStart(2, "0");
        const hour12 = String(hours === 0 ? 12 : hours > 12 ? hours - 12 : hours);
        const time = SettingsData.use24HourClock ? `${String(hours).padStart(2, "0")}:${minutes}` : `${SettingsData.padHours12Hour ? hour12.padStart(2, "0") : hour12}:${minutes}`;
        const locale = I18n.locale();
        const dateText = SettingsData.clockDateFormat && SettingsData.clockDateFormat.length > 0 ? date.toLocaleDateString(locale, SettingsData.clockDateFormat) : date.toLocaleDateString(locale, "ddd d");
        return `${time} • ${dateText}`;
    }

    Rectangle {
        id: pill
        width: clockLabel.implicitWidth + Theme.spacingL * 2
        height: Layout.ISLAND_HEIGHT
        radius: height / 2
        color: root.backgroundColor

        StyledText {
            id: clockLabel
            anchors.centerIn: parent
            text: root.clockText
            font.pixelSize: root.fontPixelSize
            color: root.foregroundColor
        }
    }

    SystemClock {
        id: systemClock
        precision: SystemClock.Minutes
    }

    Connections {
        target: SessionService

        function onSessionResumed() {
            systemClock.enabled = false;
            systemClock.enabled = true;
        }
    }
}
