pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Widgets

/**
 * Single-line label that elides when tight and marquees when allowed.
 *
 * The parent sizes the item; `contentWidth` exposes the measured text width so
 * callers can compute natural (unclipped) sizes.
 */
Item {
    id: root

    property string text: ""
    property int fontPixelSize: Theme.fontSizeMedium
    property int fontWeight: Font.Normal
    property color textColor: Theme.surfaceText
    /// Caller gate: marquee only while playing, collapsed and user-enabled.
    property bool scrollEnabled: false

    readonly property real contentWidth: metrics.width
    readonly property real contentHeight: metrics.height
    readonly property bool overflowing: metrics.width > width

    implicitWidth: Math.ceil(metrics.width)
    implicitHeight: Math.ceil(metrics.height)

    /// Hard-confine content to this slot: while marqueeing, the label is
    /// full-width inside fixed bounds and must never bleed into neighbouring
    /// content (visualizer, pill padding).
    clip: true

    TextMetrics {
        id: metrics
        font.pixelSize: root.fontPixelSize
        font.weight: root.fontWeight
        text: root.text
    }

    StyledText {
        id: label

        readonly property bool scrolling: root.scrollEnabled && root.overflowing && label.visible && root.text.length > 0 && Window.window?.visible !== false
        readonly property real scrollDistance: Math.max(0, root.contentWidth - root.width + Theme.spacingS)

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: scrolling ? undefined : parent.left
        anchors.right: scrolling ? undefined : parent.right
        width: scrolling ? implicitWidth : undefined
        text: root.text
        font.pixelSize: root.fontPixelSize
        font.weight: root.fontWeight
        color: root.textColor
        horizontalAlignment: Text.AlignLeft
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.NoWrap
        elide: scrolling ? Text.ElideNone : (root.overflowing ? Text.ElideRight : Text.ElideNone)
        x: 0

        onTextChanged: {
            x = 0;
            if (scrolling)
                scrollAnimation.restart();
        }

        onScrollingChanged: {
            if (!scrolling)
                x = 0;
        }

        SequentialAnimation {
            id: scrollAnimation
            running: label.scrolling
            loops: Animation.Infinite

            PauseAnimation {
                duration: 1200
            }

            NumberAnimation {
                target: label
                property: "x"
                to: -label.scrollDistance
                duration: Math.max(1200, Math.min(5000, label.scrollDistance * 18))
                easing.type: Easing.InOutQuad
            }

            PauseAnimation {
                duration: 1200
            }

            NumberAnimation {
                target: label
                property: "x"
                to: 0
                duration: Math.max(1200, Math.min(5000, label.scrollDistance * 18))
                easing.type: Easing.InOutQuad
            }
        }
    }
}
