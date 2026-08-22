pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import "../core/IslandLayout.js" as Layout

/**
 * Media mode: compact pill (visualizer + scrolling track label) that morphs
 * into an expanded card (identity header, track info, live lyric, transport).
 *
 * Pure composition: playback state comes from core.MediaState, geometry math
 * from core.IslandLayout.js, morphing/hover from ui.IslandSurface.
 */
Item {
    id: root

    // ---- injected context (see DynamicIsland.qml injection contract) ----
    property var media: null
    property var config: ({})
    property color backgroundColor: Theme.surfaceContainerHigh
    property color foregroundColor: Theme.surfaceText
    property color accentColor: Theme.primary
    property color onAccentColor: Theme.onPrimary
    property real availableWidth: 380
    property real availableHeight: 180
    property var requestResize: null
    property var clearResize: null

    // ---- layout constants ----
    readonly property int iconBoxSize: 20
    readonly property real horizontalPadding: Theme.spacingL * 2
    readonly property int fontPixelSize: Theme.barTextSize(Layout.ISLAND_HEIGHT, 1.15)

    /// Shell-wide "media size" setting caps the compact label width.
    readonly property int maxTextWidth: SettingsData.mediaSize === 2 ? 220 : SettingsData.mediaSize === 3 ? 300 : 160

    readonly property real maxAllowedTextWidth: Math.max(40, availableWidth - (iconBoxSize + Theme.spacingS + horizontalPadding))

    readonly property bool showLyric: media ? media.showLyric : false

    readonly property real desiredTextWidth: showLyric ? Math.min(pillMetrics.width, maxAllowedTextWidth) : Math.min(pillMetrics.width, Math.min(maxTextWidth, maxAllowedTextWidth))

    readonly property real desiredRowWidth: iconBoxSize + Theme.spacingS + desiredTextWidth

    /// Unclamped compact width: what the pill measures with unlimited room.
    /// Independent of availableWidth, so wrapper fitting resolves in one step.
    readonly property real naturalTextWidth: showLyric ? pillMetrics.width : Math.min(pillMetrics.width, maxTextWidth)
    readonly property real naturalCompactWidth: Math.max(Layout.COMPACT_MIN_WIDTH, iconBoxSize + Theme.spacingS + naturalTextWidth + horizontalPadding)

    readonly property real compactWidth: Math.max(Layout.COMPACT_MIN_WIDTH, Math.min(availableWidth, desiredRowWidth + horizontalPadding))

    readonly property var expandedDims: Layout.expandedDimensions(availableWidth, availableHeight)

    readonly property real expandedWidth: expandedDims.width

    /// Content-driven: long lyrics grow the card beyond the default height.
    readonly property real expandedHeight: Math.max(expandedDims.height, ((surface.expandedContentItem as Item)?.implicitHeight ?? 0) + Theme.spacingM * 2)

    implicitWidth: surface.width
    implicitHeight: surface.height

    TextMetrics {
        id: pillMetrics
        font.pixelSize: root.fontPixelSize
        font.weight: root.showLyric ? Font.Medium : Font.Normal
        text: root.media ? root.media.displayText : ""
    }

    Connections {
        target: root.media

        function onPlayingChanged() {
            if (!root.media || !root.media.playing)
                surface.forceCollapse();
        }
    }

    IslandSurface {
        id: surface
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        backgroundColor: root.backgroundColor
        outlineColor: Theme.withAlpha(root.foregroundColor, 0.12 * surface.progress)
        interactive: true
        requestResize: root.requestResize
        clearResize: root.clearResize
        surfacePaddingH: Theme.spacingM
        surfacePaddingV: Theme.spacingXS

        compactWidth: root.compactWidth
        expandedWidth: root.expandedWidth
        expandedHeight: root.expandedHeight
        fitCompact: root.media ? root.media.playing : false
        compactFitWidth: root.naturalCompactWidth

        compactContent: Component {
            Row {
                width: root.desiredRowWidth
                height: Layout.ISLAND_HEIGHT
                spacing: Theme.spacingS

                Item {
                    width: root.iconBoxSize
                    height: root.iconBoxSize
                    anchors.verticalCenter: parent.verticalCenter

                    AudioVisualization {
                        anchors.fill: parent
                        barCount: root.config.compactBarCount ?? 15
                        barColor: root.foregroundColor
                        playing: root.media ? root.media.playing : false
                        visible: root.media ? root.media.playing : false
                    }

                    DankIcon {
                        anchors.centerIn: parent
                        name: "music_note"
                        size: 20
                        color: root.foregroundColor
                        visible: !(root.media && root.media.playing)
                    }
                }

                MarqueeLabel {
                    width: root.desiredTextWidth
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.media ? root.media.displayText : ""
                    fontPixelSize: root.fontPixelSize
                    fontWeight: root.showLyric ? Font.Medium : Font.Normal
                    textColor: root.foregroundColor
                    scrollEnabled: !root.showLyric && (root.media ? root.media.playing : false) && !surface.expanded && SettingsData.scrollTitleEnabled
                }
            }
        }

        expandedContent: Component {
            Column {
                id: expandedCard
                spacing: Theme.spacingS

                // Header: source badge + player identity + extended visualizer
                Row {
                    width: parent.width
                    height: 24
                    spacing: Theme.spacingS

                    Rectangle {
                        width: 24
                        height: 24
                        radius: 8
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.withAlpha(root.foregroundColor, 0.10)

                        DankIcon {
                            anchors.centerIn: parent
                            name: root.media && root.media.webSource ? "public" : "music_note"
                            size: 16
                            color: root.foregroundColor
                        }
                    }

                    StyledText {
                        width: parent.width - 24 - expandedViz.width - Theme.spacingS * 2
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.media && root.media.identity.length > 0 ? root.media.identity : "Now Playing"
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.DemiBold
                        color: Theme.withAlpha(root.foregroundColor, 0.6)
                        elide: Text.ElideRight
                    }

                    AudioVisualization {
                        id: expandedViz
                        width: 64
                        height: 18
                        anchors.verticalCenter: parent.verticalCenter
                        barCount: root.config.extendedBarCount ?? 16
                        barColor: root.foregroundColor
                        playing: root.media ? root.media.playing : false
                    }
                }

                // Track information + live lyric
                Column {
                    width: parent.width
                    spacing: Theme.spacingXXS

                    StyledText {
                        width: parent.width
                        text: root.media ? root.media.title : ""
                        font.pixelSize: Theme.fontSizeLarge
                        font.bold: true
                        color: root.foregroundColor
                        elide: Text.ElideRight
                    }

                    StyledText {
                        width: parent.width
                        text: root.media ? root.media.artist : ""
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.withAlpha(root.foregroundColor, 0.7)
                        elide: Text.ElideRight
                        visible: text.length > 0
                    }

                    StyledText {
                        width: parent.width
                        text: root.media ? root.media.lyric : ""
                        font.pixelSize: Theme.fontSizeSmall
                        font.italic: true
                        color: root.accentColor
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        visible: root.showLyric
                    }
                }

                TransportBar {
                    anchors.horizontalCenter: parent.horizontalCenter
                    iconColor: root.foregroundColor
                    accent: root.accentColor
                    onAccent: root.onAccentColor
                    playing: root.media ? root.media.playing : false
                    canPrevious: root.media ? root.media.canGoPrevious : false
                    canNext: root.media ? root.media.canGoNext : false

                    onPrevious: root.media.previous()
                    onTogglePlayback: root.media.togglePlay()
                    onNext: root.media.next()
                }
            }
        }
    }
}
