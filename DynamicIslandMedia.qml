import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.Common
import qs.Services
import qs.Widgets
import "IslandLayout.js" as IslandLayout

Item {
    id: root

    property color islandBackgroundColor: "#0b0b0b"
    property color islandTextColor: "#f5f5f5"
    property real barThickness: 48
    property int compactBarCount: 15
    property int extendedBarCount: 16
    property real parentWidgetWidth: 380
    property real parentWidgetHeight: 180
    property var islandService: null

    // Fallback to MprisController if islandService is not yet injected
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property bool hoverPreview: MprisController.isFirefoxYoutubeHoverPreview(activePlayer)
    readonly property bool isPlaying: islandService ? islandService.isPlaying : (!!activePlayer && activePlayer.playbackState === 1 && !hoverPreview)

    readonly property string cachedIdentity: (islandService && islandService.playerIdentity) ? islandService.playerIdentity : (activePlayer ? (activePlayer.identity || "") : "")
    readonly property string lowerIdentity: cachedIdentity.toLowerCase()
    readonly property bool isWebMedia: lowerIdentity.includes("firefox") || lowerIdentity.includes("chrome") || lowerIdentity.includes("chromium") || lowerIdentity.includes("edge") || lowerIdentity.includes("safari")

    readonly property string trackTitle: (islandService && islandService.title) ? islandService.title : String(MprisController.stableTitle || (activePlayer ? activePlayer.trackTitle : "") || "Playing")
    readonly property string trackArtist: (islandService && islandService.artist) ? islandService.artist : String(MprisController.stableArtist || (activePlayer ? activePlayer.trackArtist : "") || (isWebMedia ? cachedIdentity : ""))

    readonly property bool hasLyrics: (islandService && islandService.hasLyrics && islandService.lyricsEnabled) ?? false
    readonly property string currentLyric: (islandService && islandService.currentLyric) ? islandService.currentLyric : ""
    readonly property bool showLyrics: hasLyrics && currentLyric.length > 0 && root.isPlaying

    readonly property string defaultDisplayText: {
        const title = root.trackTitle;
        const subtitle = isWebMedia ? (root.trackArtist || cachedIdentity) : root.trackArtist;
        const combined = (subtitle.length > 0 && subtitle !== title) ? `${title} • ${subtitle}` : title;
        return combined.length > 0 ? combined : "Playing";
    }

    readonly property string compactDisplayText: root.showLyrics ? root.currentLyric : root.defaultDisplayText

    readonly property int fontSize: Theme.barTextSize(root.barThickness, 1.15, undefined)
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

    property bool isExpanded: false
    property real expandProgress: 0.0

    readonly property real iconWidth: 20
    readonly property real rowSpacing: Theme.spacingS
    readonly property real horizontalPadding: Theme.spacingL * 2

    // Maximum text width permitted by the actual outer parent widget bounds
    readonly property real maxAllowedTextWidth: Math.max(40, root.parentWidgetWidth - (iconWidth + rowSpacing + horizontalPadding))

    TextMetrics {
        id: lyricMetrics
        font.pixelSize: root.fontSize
        font.weight: root.showLyrics ? Font.Medium : Font.Normal
        text: root.compactDisplayText
    }

    readonly property real measuredTextWidth: Math.ceil(lyricMetrics.width)

    function getDesiredTextWidth() {
        if (root.showLyrics) {
            return Math.min(measuredTextWidth, maxAllowedTextWidth);
        } else {
            return Math.min(measuredTextWidth, Math.min(root.maxTextWidth, maxAllowedTextWidth));
        }
    }

    readonly property real desiredRowWidth: iconWidth + rowSpacing + getDesiredTextWidth()
    readonly property real compactWidth: Math.max(160, Math.min(root.parentWidgetWidth, desiredRowWidth + horizontalPadding))

    readonly property real compactHeight: root.barThickness
    readonly property var expandedDims: IslandLayout.calculateExpandedDimensions(root.parentWidgetWidth, root.parentWidgetHeight, 360, 176)
    readonly property real expandedWidth: Math.max(expandedDims.width, 360)
    readonly property real expandedHeight: Math.max(expandedDims.height, expandedContent.implicitHeight + Theme.spacingM * 2)

    property real animatedCompactWidth: compactWidth
    Behavior on animatedCompactWidth {
        NumberAnimation {
            duration: 220
            easing.type: Easing.OutCubic
        }
    }

    readonly property real currentWidth: IslandLayout.lerp(root.animatedCompactWidth, expandedWidth, expandProgress)
    readonly property real currentHeight: IslandLayout.lerp(compactHeight, expandedHeight, expandProgress)
    readonly property real currentRadius: IslandLayout.interpolateRadius(compactHeight / 2, 24, expandProgress)

    implicitWidth: Math.round(currentWidth)
    implicitHeight: Math.round(currentHeight)

    onIsPlayingChanged: {
        if (!isPlaying && isExpanded) {
            collapseIsland();
        }
    }

    function expandIsland() {
        if (!isPlaying)
            return;
        isExpanded = true;
        collapseAnim.stop();
        expandAnim.restart();
    }

    function collapseIsland() {
        isExpanded = false;
        expandAnim.stop();
        collapseAnim.restart();
    }

    Timer {
        id: collapseTimer
        interval: 180
        repeat: false
        onTriggered: {
            if (!islandHoverArea.containsMouse && !prevBtnMouse.containsMouse && !playBtnMouse.containsMouse && !nextBtnMouse.containsMouse) {
                root.collapseIsland();
            }
        }
    }

    NumberAnimation {
        id: expandAnim
        target: root
        property: "expandProgress"
        to: 1.0
        duration: 320
        easing.type: Easing.OutBack
        easing.overshoot: 1.15
    }

    NumberAnimation {
        id: collapseAnim
        target: root
        property: "expandProgress"
        to: 0.0
        duration: 250
        easing.type: Easing.OutCubic
    }

    // Dynamic Island Surface
    Rectangle {
        id: islandCard
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.round(root.currentWidth)
        height: Math.round(root.currentHeight)
        radius: root.currentRadius
        color: root.islandBackgroundColor
        border.color: Theme.withAlpha(root.islandTextColor, 0.12 * root.expandProgress)
        border.width: root.expandProgress > 0.05 ? 1 : 0
        clip: true

        MouseArea {
            id: islandHoverArea
            anchors.fill: parent
            hoverEnabled: true
            onEntered: {
                if (root.isPlaying) {
                    collapseTimer.stop();
                    root.expandIsland();
                }
            }
            onExited: {
                collapseTimer.restart();
            }
        }

        // Compact Pill Content View
        Item {
            id: compactContent
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: root.animatedCompactWidth
            height: root.compactHeight
            clip: true
            opacity: IslandLayout.calcCompactOpacity(root.expandProgress)
            visible: opacity > 0

            Row {
                id: mediaRow
                width: root.desiredRowWidth
                anchors.centerIn: parent
                spacing: root.rowSpacing

                Item {
                    width: root.iconWidth
                    height: 20
                    anchors.verticalCenter: parent.verticalCenter

                    AudioVisualization {
                        id: audioViz
                        anchors.fill: parent
                        barCount: root.compactBarCount
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
                    width: root.getDesiredTextWidth()
                    height: Math.max(root.fontSize + 4, lyricMetrics.height)
                    clip: !root.showLyrics
                    visible: root.compactDisplayText.length > 0

                    StyledText {
                        id: textLabel
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: scrollActive ? undefined : parent.left
                        anchors.right: scrollActive ? undefined : parent.right
                        width: scrollActive ? implicitWidth : undefined
                        text: root.compactDisplayText
                        font.pixelSize: root.fontSize
                        font.weight: root.showLyrics ? Font.Medium : Font.Normal
                        color: root.islandTextColor
                        horizontalAlignment: Text.AlignLeft
                        verticalAlignment: Text.AlignVCenter
                        wrapMode: Text.NoWrap
                        elide: scrollActive ? Text.ElideNone : ((root.measuredTextWidth > textContainer.width) ? Text.ElideRight : Text.ElideNone)
                        x: 0

                        // Only scroll/morph title if NOT showing lyrics
                        readonly property bool scrollActive: !root.showLyrics && root.isPlaying && visible && text.length > 0 && Window.window?.visible !== false && implicitWidth > textContainer.width && SettingsData.scrollTitleEnabled && !root.isExpanded
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

        // Expanded Card Content View
        Column {
            id: expandedContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingXS
            opacity: IslandLayout.calcExpandedOpacity(root.expandProgress)
            visible: opacity > 0

            // Header Row (App Badge + Identity + Equalizer)
            Row {
                width: parent.width
                height: 24

                Rectangle {
                    width: 24
                    height: 24
                    radius: 6
                    color: Theme.withAlpha(root.islandTextColor, 0.1)
                    anchors.verticalCenter: parent.verticalCenter

                    DankIcon {
                        anchors.centerIn: parent
                        name: root.isWebMedia ? "public" : "music_note"
                        size: 16
                        color: root.islandTextColor
                    }
                }

                Item {
                    width: parent.width - 24 - expandedVizContainer.width - Theme.spacingS * 2
                    height: parent.height
                    anchors.verticalCenter: parent.verticalCenter

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingS
                        text: root.cachedIdentity || "Now Playing"
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: true
                        color: Theme.withAlpha(root.islandTextColor, 0.6)
                        elide: Text.ElideRight
                        width: parent.width - Theme.spacingS
                    }
                }

                Item {
                    id: expandedVizContainer
                    width: 64
                    height: 18
                    anchors.verticalCenter: parent.verticalCenter

                    AudioVisualization {
                        id: expandedAudioViz
                        anchors.fill: parent
                        barCount: root.extendedBarCount
                        color: root.islandTextColor
                        visible: root.isPlaying
                    }
                }
            }

            Item {
                width: 1
                height: 2
            }

            // Track Information & Live Lyric
            Column {
                width: parent.width
                spacing: 2

                StyledText {
                    width: parent.width
                    text: root.trackTitle
                    font.pixelSize: Theme.fontSizeLarge
                    font.bold: true
                    color: root.islandTextColor
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignLeft
                }

                StyledText {
                    width: parent.width
                    text: root.trackArtist
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.withAlpha(root.islandTextColor, 0.7)
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignLeft
                    visible: text.length > 0
                }

                StyledText {
                    width: parent.width
                    text: root.currentLyric
                    font.pixelSize: Theme.fontSizeSmall
                    font.italic: true
                    color: Theme.primary
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignLeft
                    visible: root.showLyrics
                }
            }

            Item {
                width: 1
                height: 4
            }

            // Media Controls (Previous, Play/Pause, Next)
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.spacingL

                // Previous Track Button
                Rectangle {
                    width: 36
                    height: 36
                    radius: 18
                    anchors.verticalCenter: parent.verticalCenter
                    color: prevBtnMouse.containsMouse ? Theme.withAlpha(root.islandTextColor, 0.25) : Theme.withAlpha(root.islandTextColor, 0.12)
                    opacity: (islandService ? islandService.canGoPrevious : (root.activePlayer && root.activePlayer.canGoPrevious)) ? 1.0 : 0.4

                    DankIcon {
                        anchors.centerIn: parent
                        name: "skip_previous"
                        size: 20
                        color: root.islandTextColor
                    }

                    MouseArea {
                        id: prevBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: collapseTimer.stop()
                        onExited: collapseTimer.restart()
                        onClicked: {
                            if (root.islandService) {
                                root.islandService.previous();
                            } else if (root.activePlayer) {
                                MprisController.previousOrRewind();
                            }
                        }
                    }
                }

                // Play / Pause Button
                Rectangle {
                    width: 42
                    height: 42
                    radius: 21
                    anchors.verticalCenter: parent.verticalCenter
                    color: playBtnMouse.containsMouse ? Theme.withAlpha(root.islandTextColor, 0.95) : root.islandTextColor

                    DankIcon {
                        anchors.centerIn: parent
                        name: root.isPlaying ? "pause" : "play_arrow"
                        size: 24
                        color: root.islandBackgroundColor
                    }

                    MouseArea {
                        id: playBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: collapseTimer.stop()
                        onExited: collapseTimer.restart()
                        onClicked: {
                            if (root.islandService) {
                                root.islandService.togglePlay();
                            } else if (root.activePlayer) {
                                root.activePlayer.togglePlaying();
                            }
                        }
                    }
                }

                // Next Track Button
                Rectangle {
                    width: 36
                    height: 36
                    radius: 18
                    anchors.verticalCenter: parent.verticalCenter
                    color: nextBtnMouse.containsMouse ? Theme.withAlpha(root.islandTextColor, 0.25) : Theme.withAlpha(root.islandTextColor, 0.12)
                    opacity: (islandService ? islandService.canGoNext : (root.activePlayer && root.activePlayer.canGoNext)) ? 1.0 : 0.4

                    DankIcon {
                        anchors.centerIn: parent
                        name: "skip_next"
                        size: 20
                        color: root.islandTextColor
                    }

                    MouseArea {
                        id: nextBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: collapseTimer.stop()
                        onExited: collapseTimer.restart()
                        onClicked: {
                            if (root.islandService) {
                                root.islandService.next();
                            } else if (root.activePlayer) {
                                MprisController.next();
                            }
                        }
                    }
                }
            }
        }
    }
}
