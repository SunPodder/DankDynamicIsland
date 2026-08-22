pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Widgets

/**
 * Expanded-card seekbar: elapsed time, flat progress bar, duration.
 *
 * Binds exclusively to core.MediaState normalized playback values, so both
 * backends (helper daemon stream, direct MPRIS fallback) behave identically.
 * Interaction mirrors the shell-wide DankSeekbar: press previews, drag
 * updates the preview, release commits one seek, and the committed ratio
 * stays pinned until the reported position catches up (or the settle window
 * ends) so the bar never snaps backwards mid-seek.
 */
Item {
    id: root

    property var media: null
    property color accentColor: Theme.primary
    property color foregroundColor: Theme.surfaceText

    readonly property bool seekable: !!media && media.canSeek && media.length > 0
    readonly property real playerRatio: {
        if (!media || media.length <= 0)
            return 0;
        const pos = (media.position || 0) % Math.max(1, media.length);
        return Math.max(0, Math.min(1, pos / media.length));
    }

    property real previewRatio: -1
    property real committedRatio: -1
    property int settleChecksRemaining: 0

    readonly property bool dragging: dragArea.pressed && seekable
    readonly property real shownRatio: previewRatio >= 0 ? previewRatio : (committedRatio >= 0 ? committedRatio : playerRatio)

    implicitHeight: 20

    function clampRatio(ratio) {
        return Math.max(0, Math.min(1, ratio));
    }

    function formatTime(seconds) {
        const s = Math.max(0, Math.floor(seconds));
        const minutes = Math.floor(s / 60);
        const secs = s % 60;
        return minutes + ":" + (secs < 10 ? "0" : "") + secs;
    }

    // Pin the committed ratio until the backend reports the new position.
    Timer {
        id: settleTimer

        interval: 80
        repeat: true
        running: root.committedRatio >= 0
        onTriggered: {
            if (root.dragging)
                return;
            const settled = Math.abs(root.playerRatio - root.committedRatio) <= 0.002;
            if (settled || root.settleChecksRemaining <= 0) {
                root.committedRatio = -1;
                root.settleChecksRemaining = 0;
                stop();
                return;
            }
            root.settleChecksRemaining -= 1;
        }
    }

    StyledText {
        id: elapsedLabel

        readonly property real seconds: root.seekable ? root.shownRatio * root.media.length : 0

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 38
        text: root.formatTime(seconds)
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.withAlpha(root.foregroundColor, 0.55)
    }

    Item {
        id: barHit

        anchors.left: elapsedLabel.right
        anchors.leftMargin: Theme.spacingS
        anchors.right: totalLabel.left
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height

        Rectangle {
            id: track

            width: parent.width
            height: 4
            radius: height / 2
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.withAlpha(root.foregroundColor, 0.14)
            visible: root.seekable
        }

        Rectangle {
            id: fill

            width: Math.max(0, Math.min(parent.width, parent.width * root.shownRatio))
            height: track.height
            radius: height / 2
            anchors.verticalCenter: parent.verticalCenter
            color: root.accentColor
            visible: root.seekable

            Behavior on width {
                NumberAnimation {
                    duration: 80
                }
            }
        }

        Rectangle {
            id: knob

            width: 10
            height: width
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(0, Math.min(parent.width, parent.width * root.shownRatio)) - width / 2
            color: root.accentColor
            visible: root.seekable
            opacity: (dragArea.containsMouse || root.dragging) ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.shorterDuration
                }
            }
        }

        MouseArea {
            id: dragArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: root.seekable

            onPressed: mouse => {
                root.media.seeking = true;
                root.previewRatio = root.clampRatio(mouse.x / width);
            }

            onPositionChanged: mouse => {
                if (pressed)
                    root.previewRatio = root.clampRatio(mouse.x / width);
            }

            onReleased: {
                root.media.seeking = false;
                if (root.previewRatio < 0)
                    return;
                root.committedRatio = root.previewRatio;
                root.settleChecksRemaining = 15;
                root.media.seek(root.committedRatio * root.media.length);
                root.previewRatio = -1;
            }

            onCanceled: {
                root.media.seeking = false;
                root.previewRatio = -1;
            }
        }
    }

    StyledText {
        id: totalLabel

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 38
        text: root.media && root.media.length > 0 ? root.formatTime(root.media.length) : "--:--"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.withAlpha(root.foregroundColor, 0.55)
    }
}
