pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Mpris
import qs.Services

/**
 * Normalized media model for the island.
 *
 * Prefers the island helper daemon (richer state: synced lyrics, stable
 * metadata) when its service is connected, and falls back to MprisController
 * so the island still works with no daemon running. Views bind to these
 * properties and never talk to either backend directly.
 */
Item {
    id: root

    /// core.IslandService instance, or null.
    property var service: null

    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property bool hoverPreview: MprisController.isFirefoxYoutubeHoverPreview(player)

    /// True when the helper daemon is the authoritative source.
    readonly property bool daemonDriven: service !== null && service.connected

    readonly property bool playing: daemonDriven ? service.media.isPlaying : (!!player && player.playbackState === MprisPlaybackState.Playing && !hoverPreview)

    readonly property string identity: daemonDriven ? service.media.playerIdentity : (player ? (player.identity || "") : "")

    readonly property bool webSource: {
        const lower = identity.toLowerCase();
        return lower.includes("firefox") || lower.includes("chrome") || lower.includes("chromium") || lower.includes("edge") || lower.includes("safari");
    }

    readonly property string title: daemonDriven ? service.media.title : String(MprisController.stableTitle || (player ? player.trackTitle : "") || "")

    readonly property string artist: daemonDriven ? service.media.artist : String(MprisController.stableArtist || (player ? player.trackArtist : "") || "")

    readonly property bool hasLyrics: daemonDriven ? (service.media.hasLyrics && service.media.lyricsEnabled) : false

    readonly property string lyric: daemonDriven ? service.media.currentLyric : ""

    readonly property bool showLyric: hasLyrics && lyric.length > 0 && playing

    readonly property bool canGoNext: daemonDriven ? service.media.canGoNext : (!!player && player.canGoNext)

    readonly property bool canGoPrevious: daemonDriven ? service.media.canGoPrevious : (!!player && player.canGoPrevious)

    /// "title • artist" for the compact pill; web sources fall back to identity.
    readonly property string trackLabel: {
        const subtitle = webSource ? (artist || identity) : artist;
        const combined = (subtitle.length > 0 && subtitle !== title) ? `${title} • ${subtitle}` : title;
        return combined.length > 0 ? combined : "Playing";
    }

    /// What the compact pill shows: live lyric wins over track label.
    readonly property string displayText: showLyric ? lyric : trackLabel

    function togglePlay() {
        if (daemonDriven)
            service.togglePlay();
        else if (player)
            player.togglePlaying();
    }

    function next() {
        if (daemonDriven)
            service.next();
        else
            MprisController.next();
    }

    function previous() {
        if (daemonDriven)
            service.previous();
        else
            MprisController.previousOrRewind();
    }
}
