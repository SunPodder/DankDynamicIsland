import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: root

    property color islandBackgroundColor: "#0b0b0b"
    property color islandTextColor: "#f5f5f5"
    property real barThickness: 48

    implicitWidth: islandRow.implicitWidth + Theme.spacingL * 2
    implicitHeight: Math.max(islandRow.implicitHeight, Theme.barTextSize(barThickness, undefined, undefined)) + Theme.spacingS * 2

    readonly property real fontSize: Theme.barTextSize(barThickness, undefined, undefined)
    readonly property string clockText: {
        const date = systemClock?.date;
        if (!date)
            return "--:-- • --";

        const hours = date.getHours();
        const minutes = String(date.getMinutes()).padStart(2, "0");
        const time = SettingsData.use24HourClock
            ? `${String(hours).padStart(2, "0")}:${minutes}`
            : `${SettingsData.padHours12Hour ? String(hours === 0 ? 12 : hours > 12 ? hours - 12 : hours).padStart(2, "0") : String(hours === 0 ? 12 : hours > 12 ? hours - 12 : hours)}:${minutes}`;

        const locale = I18n.locale();
        const dateText = SettingsData.clockDateFormat && SettingsData.clockDateFormat.length > 0
            ? date.toLocaleDateString(locale, SettingsData.clockDateFormat)
            : date.toLocaleDateString(locale, "ddd d");

        return `${time} • ${dateText}`;
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.islandBackgroundColor
    }

    Row {
        id: islandRow
        anchors.centerIn: parent
        spacing: Theme.spacingS

        StyledText {
            text: root.clockText
            font.pixelSize: root.fontSize
            color: root.islandTextColor
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
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