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
    readonly property string trackTitle: String(MprisController.stableTitle || (activePlayer ? activePlayer.trackTitle : "") || "Playing")
    readonly property string trackArtist: String(MprisController.stableArtist || (activePlayer ? activePlayer.trackArtist : "") || (isWebMedia ? cachedIdentity : ""))

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

    property bool isExpanded: false
    property real expandProgress: 0.0

    readonly property real compactWidth: IslandLayout.calculateCompactWidth(mediaRow.implicitWidth, Theme.spacingL * 2, 160, 320)
    readonly property real compactHeight: root.barThickness
    readonly property var expandedDims: IslandLayout.calculateExpandedDimensions(root.parentWidgetWidth, root.parentWidgetHeight, 360, 170)
    readonly property real expandedWidth: Math.max(expandedDims.width, compactWidth + 60)
    readonly property real expandedHeight: expandedDims.height

    readonly property real currentWidth: IslandLayout.lerp(compactWidth, expandedWidth, expandProgress)
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
            width: root.compactWidth
            height: root.compactHeight
            opacity: IslandLayout.calcCompactOpacity(root.expandProgress)
            visible: opacity > 0

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

                        readonly property bool scrollActive: root.isPlaying && visible && root.displayText.length > 0 && Window.window?.visible !== false && implicitWidth > textContainer.width && SettingsData.scrollTitleEnabled && !root.isExpanded
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
            anchors.fill: parent
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

            // Track Information
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
                    opacity: (root.activePlayer && root.activePlayer.canGoPrevious) ? 1.0 : 0.4

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
                            if (root.activePlayer) {
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
                            if (root.activePlayer) {
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
                    opacity: (root.activePlayer && root.activePlayer.canGoNext) ? 1.0 : 0.4

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
                            if (root.activePlayer) {
                                MprisController.next();
                            }
                        }
                    }
                }
            }
        }
    }
}