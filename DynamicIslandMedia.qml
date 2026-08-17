import QtQuick
import Quickshell.Services.Mpris
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: root

    property color islandBackgroundColor: "#0b0b0b"
    property color islandTextColor: "#f5f5f5"
    property real barThickness: 48

    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property bool hoverPreview: MprisController.isFirefoxYoutubeHoverPreview(activePlayer)
    readonly property bool isPlaying: !!activePlayer && activePlayer.playbackState === 1 && !hoverPreview
    readonly property string cachedIdentity: activePlayer ? (activePlayer.identity || "") : ""
    readonly property string lowerIdentity: cachedIdentity.toLowerCase()
    readonly property bool isWebMedia: lowerIdentity.includes("firefox") || lowerIdentity.includes("chrome") || lowerIdentity.includes("chromium") || lowerIdentity.includes("edge") || lowerIdentity.includes("safari")
    readonly property string displayText: {
        if (!activePlayer)
            return "";
        const title = String(MprisController.stableTitle || activePlayer.trackTitle || "");
        const subtitle = isWebMedia ? String(MprisController.stableArtist || cachedIdentity) : String(MprisController.stableArtist || activePlayer.trackArtist || "");
        const combined = subtitle.length > 0 ? `${title} • ${subtitle}` : title;
        return combined.length > 0 ? combined : "Playing";
    }
    readonly property int fontSize: Theme.barTextSize(root.barThickness, undefined, undefined)
    readonly property int maxTextWidth: {
        switch (SettingsData.mediaSize) {
        case 2:
            return 220;
        case 3:
            return 300;
        default:
            return 160;
        }
    }

    implicitWidth: mediaRow.implicitWidth + Theme.spacingL * 2
    implicitHeight: Math.max(mediaRow.implicitHeight, root.fontSize) + Theme.spacingS * 2

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.islandBackgroundColor
    }

    Row {
        id: mediaRow
        anchors.centerIn: parent
        spacing: Theme.spacingS

        Item {
            width: root.isPlaying ? audioViz.width : 20
            height: 20
            anchors.verticalCenter: parent.verticalCenter

            AudioVisualization {
                id: audioViz
                anchors.fill: parent
                color: root.islandTextColor
                visible: root.isPlaying
            }

            DankIcon {
                anchors.centerIn: parent
                name: "music_note"
                size: 20
                color: root.islandTextColor
                visible: !root.isPlaying
            }
        }

        Item {
            id: textContainer
            anchors.verticalCenter: parent.verticalCenter
            width: textLabel.implicitWidth > root.maxTextWidth ? root.maxTextWidth : textLabel.implicitWidth
            height: root.fontSize
            clip: true
            visible: root.displayText.length > 0

            StyledText {
                id: textLabel
                anchors.verticalCenter: parent.verticalCenter
                text: root.displayText
                font.pixelSize: root.fontSize
                color: root.islandTextColor
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.NoWrap
                x: 0

                readonly property bool scrollActive: root.isPlaying && visible && root.displayText.length > 0 && Window.window?.visible !== false && implicitWidth > textContainer.width && SettingsData.scrollTitleEnabled
                readonly property real scrollDistance: Math.max(0, implicitWidth - textContainer.width + Theme.spacingS)

                onTextChanged: {
                    x = 0;
                    if (scrollActive)
                        scrollAnimation.restart();
                }

                onScrollActiveChanged: {
                    if (!scrollActive)
                        x = 0;
                }

                SequentialAnimation {
                    id: scrollAnimation
                    running: textLabel.scrollActive
                    loops: Animation.Infinite

                    PauseAnimation {
                        duration: 1200
                    }

                    NumberAnimation {
                        target: textLabel
                        property: "x"
                        to: -textLabel.scrollDistance
                        duration: Math.max(1200, Math.min(5000, textLabel.scrollDistance * 18))
                        easing.type: Easing.InOutQuad
                    }

                    PauseAnimation {
                        duration: 1200
                    }

                    NumberAnimation {
                        target: textLabel
                        property: "x"
                        to: 0
                        duration: Math.max(1200, Math.min(5000, textLabel.scrollDistance * 18))
                        easing.type: Easing.InOutQuad
                    }
                }
            }
        }
    }
}