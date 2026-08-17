import QtQuick
import Quickshell
import Quickshell.Wayland
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

    property bool shouldBeOpen: false
    property real expandProgress: 0.0

    onIsPlayingChanged: {
        if (!isPlaying && popupOverlay.visible) {
            closePopup();
        }
    }

    function openPopup() {
        if (!isPlaying)
            return;
        const win = root.Window.window;
        if (!win)
            return;
        const globalPos = compactContainer.mapToItem(null, 0, 0);
        popupOverlay.targetScreen = win.screen;
        popupOverlay.targetX = (win.x || 0) + globalPos.x;
        popupOverlay.targetY = (win.y || 0) + globalPos.y;
        popupOverlay.compactWidth = compactContainer.width;
        popupOverlay.compactHeight = root.barThickness;
        popupOverlay.visible = true;
        shouldBeOpen = true;
        collapseAnim.stop();
        expandAnim.restart();
    }

    function closePopup() {
        shouldBeOpen = false;
        expandAnim.stop();
        collapseAnim.restart();
    }

    Timer {
        id: collapseTimer
        interval: 150
        repeat: false
        onTriggered: {
            if (!compactHover.containsMouse && !popupHover.containsMouse && !prevBtnMouse.containsMouse && !playBtnMouse.containsMouse && !nextBtnMouse.containsMouse) {
                root.closePopup();
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
        onFinished: {
            if (!root.shouldBeOpen && root.expandProgress === 0.0) {
                popupOverlay.visible = false;
            }
        }
    }

    implicitWidth: compactContainer.implicitWidth
    implicitHeight: compactContainer.implicitHeight

    // In-bar Compact Container
    Item {
        id: compactContainer
        implicitWidth: mediaRow.implicitWidth + Theme.spacingL * 2
        implicitHeight: Math.max(mediaRow.implicitHeight, root.fontSize) + Theme.spacingS * 2
        anchors.centerIn: parent

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: root.islandBackgroundColor
        }

        MouseArea {
            id: compactHover
            anchors.fill: parent
            hoverEnabled: true
            onEntered: {
                if (root.isPlaying) {
                    collapseTimer.stop();
                    root.openPopup();
                }
            }
            onExited: {
                collapseTimer.restart();
            }
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
                    barCount: 15
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

                    readonly property bool scrollActive: root.isPlaying && visible && root.displayText.length > 0 && Window.window?.visible !== false && implicitWidth > textContainer.width && SettingsData.scrollTitleEnabled && !popupOverlay.visible
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

    // Wayland Overlay Layer Shell Popup Window (Smooth integrated extension)
    PanelWindow {
        id: popupOverlay

        property var targetScreen: null
        property real targetX: 0
        property real targetY: 0
        property real compactWidth: 160
        property real compactHeight: 48

        readonly property real expandedWidth: Math.max(340, compactWidth + 60)
        readonly property real expandedHeight: 170

        readonly property real currentWidth: compactWidth + (expandedWidth - compactWidth) * root.expandProgress
        readonly property real currentHeight: compactHeight + (expandedHeight - compactHeight) * root.expandProgress

        WlrLayershell.layer: WlrLayershell.Overlay
        WlrLayershell.namespace: "dms:dynamic-island-popup"
        color: "transparent"
        visible: false
        screen: targetScreen

        anchors {
            top: true
            left: true
        }

        margins {
            left: Math.round(targetX + (compactWidth / 2) - (currentWidth / 2))
            top: Math.round(targetY)
        }

        implicitWidth: Math.ceil(currentWidth)
        implicitHeight: Math.ceil(currentHeight)

        MouseArea {
            id: popupHover
            anchors.fill: parent
            hoverEnabled: true
            onEntered: {
                collapseTimer.stop();
            }
            onExited: {
                collapseTimer.restart();
            }
        }

        // Animated Island Card Background
        Rectangle {
            anchors.fill: parent
            radius: (popupOverlay.compactHeight / 2) * (1.0 - root.expandProgress) + 24 * root.expandProgress
            color: root.islandBackgroundColor
            border.color: Theme.withAlpha(root.islandTextColor, 0.12 * root.expandProgress)
            border.width: root.expandProgress > 0.05 ? 1 : 0
        }

        // Expanded Island Content Card (Only rendered content in popout)
        Column {
            id: popupExpandedLayout
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingXS
            opacity: Math.max(0, (root.expandProgress - 0.15) / 0.85)
            visible: opacity > 0

            // Header Row
            Row {
                width: parent.width
                height: 24

                // App / Player Icon Badge
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

                // Player Identity Name
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

                // Equalizer Bars
                Item {
                    id: expandedVizContainer
                    width: 64
                    height: 18
                    anchors.verticalCenter: parent.verticalCenter

                    AudioVisualization {
                        anchors.fill: parent
                        barCount: 16
                        color: root.islandTextColor
                        visible: root.isPlaying
                    }
                }
            }

            Item {
                width: 1
                height: 2
            }

            // Track Info Section
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

            // Media Controls Row
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
                        onEntered: {
                            collapseTimer.stop();
                        }
                        onExited: {
                            collapseTimer.restart();
                        }
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
                        onEntered: {
                            collapseTimer.stop();
                        }
                        onExited: {
                            collapseTimer.restart();
                        }
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
                        onEntered: {
                            collapseTimer.stop();
                        }
                        onExited: {
                            collapseTimer.restart();
                        }
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