pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Widgets

/**
 * Material 3 media transport: two tonal icon buttons around one filled button.
 *
 * Colors are semantic inputs resolved by the parent (theme or custom palette);
 * hover states are derived here. Hovering never leaks to the island surface -
 * the surface tracks hover with an ancestor HoverHandler.
 */
Row {
    id: root

    /// Foreground color for the tonal side buttons.
    property color iconColor: Theme.surfaceText
    /// Filled play/pause button background.
    property color accent: Theme.primary
    /// Filled play/pause button foreground.
    property color onAccent: Theme.onPrimary
    property bool playing: false
    property bool canPrevious: false
    property bool canNext: false

    signal previous()
    signal togglePlayback()
    signal next()

    spacing: Theme.spacingM

    component TransportButton: Rectangle {
        id: btn

        property string icon
        property bool available: true
        property bool primary: false

        signal activated()

        width: primary ? 48 : 40
        height: width
        radius: width / 2
        opacity: available ? 1.0 : 0.4
        color: {
            if (primary)
                return area.containsMouse ? Theme.blendAlpha(root.accent, 0.85) : root.accent;
            return area.containsMouse ? Theme.withAlpha(root.iconColor, 0.18) : Theme.withAlpha(root.iconColor, 0.10);
        }

        Behavior on color {
            ColorAnimation {
                duration: Theme.shorterDuration
            }
        }

        DankIcon {
            anchors.centerIn: parent
            name: parent.icon
            size: parent.primary ? 26 : 22
            color: parent.primary ? root.onAccent : root.iconColor
        }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.activated()
        }
    }

    TransportButton {
        icon: "skip_previous"
        available: root.canPrevious
        onActivated: root.previous()
    }

    TransportButton {
        primary: true
        icon: root.playing ? "pause" : "play_arrow"
        onActivated: root.togglePlayback()
    }

    TransportButton {
        icon: "skip_next"
        available: root.canNext
        onActivated: root.next()
    }
}
