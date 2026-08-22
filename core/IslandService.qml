pragma ComponentBehavior: Bound

import QtQuick
import QtWebSockets

/**
 * WebSocket client for the island helper daemon (daemon/).
 *
 * Exposes the daemon's media/lyrics state as a single reactive `media` object
 * and owns reconnect logic. Outgoing commands are plain functions. The lyrics
 * preference is pushed to the daemon on every (re)connect and on change, so
 * clients never depend on daemon-internal defaults.
 */
Item {
    id: root

    property string serverUrl: "ws://127.0.0.1:48123/ws"

    /// Pushed to the daemon on connect and whenever it changes.
    property bool lyricsEnabled: true

    readonly property bool connected: socket.status === WebSocket.Open

    /// Normalized mirror of the daemon MediaState payload.
    property var media: _emptyState()

    function _emptyState() {
        return {
            playerName: "",
            playerIdentity: "",
            playbackStatus: "Stopped",
            isPlaying: false,
            title: "",
            artist: "",
            album: "",
            artUrl: "",
            positionMs: 0,
            durationMs: 0,
            canGoNext: false,
            canGoPrevious: false,
            canPlay: false,
            canPause: false,
            hasLyrics: false,
            lyricsEnabled: true,
            canSeek: false,
            currentLyric: "",
            nextLyric: "",
            lyricIndex: -1,
            totalLyrics: 0
        };
    }

    WebSocket {
        id: socket
        url: root.serverUrl
        active: true

        onStatusChanged: {
            if (socket.status === WebSocket.Open) {
                reconnectTimer.stop();
                root.send({
                    action: "get_state"
                });
                root._syncLyricsPreference();
            } else if (socket.status === WebSocket.Closed || socket.status === WebSocket.Error) {
                reconnectTimer.restart();
            }
        }

        onTextMessageReceived: message => {
            try {
                root._applyMessage(JSON.parse(message));
            } catch (e) {
                console.warn("[IslandService] Failed to parse message:", message, e);
            }
        }
    }

    Timer {
        id: reconnectTimer
        interval: 1500
        repeat: true
        running: socket.status !== WebSocket.Open && socket.status !== WebSocket.Connecting
        onTriggered: {
            if (socket.status !== WebSocket.Open && socket.status !== WebSocket.Connecting) {
                socket.active = false;
                socket.active = true;
            }
        }
    }

    onLyricsEnabledChanged: _syncLyricsPreference()

    function send(data) {
        if (socket.status === WebSocket.Open)
            socket.sendTextMessage(typeof data === "string" ? data : JSON.stringify(data));
    }

    function togglePlay() {
        send({
            action: "toggle"
        });
    }

    function next() {
        send({
            action: "next"
        });
    }

    function previous() {
        send({
            action: "previous"
        });
    }

    function seek(positionMs) {
        send({
            action: "seek",
            position_ms: Math.round(positionMs)
        });
    }

    function _syncLyricsPreference() {
        send({
            action: "set_lyrics_enabled",
            enabled: root.lyricsEnabled
        });
    }

    function _applyMessage(msg) {
        if (!msg || typeof msg !== "object")
            return;
        if (msg.type !== "media_update" && msg.type !== "state")
            return;

        root.media = {
            playerName: msg.player_name || "",
            playerIdentity: msg.player_identity || "",
            playbackStatus: msg.playback_status || "Stopped",
            isPlaying: !!msg.is_playing,
            title: msg.title || "",
            artist: msg.artist || "",
            album: msg.album || "",
            artUrl: msg.art_url || "",
            positionMs: msg.position_ms || 0,
            durationMs: msg.duration_ms || 0,
            canGoNext: !!msg.can_go_next,
            canGoPrevious: !!msg.can_go_previous,
            canPlay: !!msg.can_play,
            canPause: !!msg.can_pause,
            canSeek: !!msg.can_seek,
            hasLyrics: !!msg.has_lyrics,
            lyricsEnabled: msg.lyrics_enabled !== false,
            currentLyric: msg.current_lyric || "",
            nextLyric: msg.next_lyric || "",
            lyricIndex: typeof msg.lyric_index === "number" ? msg.lyric_index : -1,
            totalLyrics: typeof msg.total_lyrics === "number" ? msg.total_lyrics : 0
        };
    }
}
