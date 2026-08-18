pragma ComponentBehavior: Bound

import QtQuick
import QtWebSockets

Item {
    id: root

    property string serverUrl: "ws://127.0.0.1:48123/ws"
    property bool isConnected: socket.status === WebSocket.Open

    property string playerName: ""
    property string playerIdentity: ""
    property string playbackStatus: "Stopped"
    property bool isPlaying: false
    property string title: ""
    property string artist: ""
    property string album: ""
    property string artUrl: ""
    property real positionMs: 0
    property real durationMs: 0
    property bool canGoNext: false
    property bool canGoPrevious: false
    property bool canPlay: false
    property bool canPause: false
    property bool hasLyrics: false
    property bool lyricsEnabled: true
    property string currentLyric: ""
    property string nextLyric: ""
    property int lyricIndex: -1
    property int totalLyrics: 0

    WebSocket {
        id: socket
        url: root.serverUrl
        active: true

        onStatusChanged: {
            if (socket.status === WebSocket.Open) {
                root.isConnected = true;
                reconnectTimer.stop();
                root.send({ action: "get_state" });
            } else if (socket.status === WebSocket.Closed || socket.status === WebSocket.Error) {
                root.isConnected = false;
                reconnectTimer.restart();
            }
        }

        onTextMessageReceived: message => {
            try {
                const data = JSON.parse(message);
                root.handleServerMessage(data);
            } catch (e) {
                console.warn("[DynamicIslandService] Failed to parse WebSocket message:", message, e);
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

    function send(data) {
        if (socket.status === WebSocket.Open) {
            const json = typeof data === "string" ? data : JSON.stringify(data);
            socket.sendTextMessage(json);
        }
    }

    function handleServerMessage(msg) {
        if (!msg || typeof msg !== "object")
            return;

        if (msg.type === "media_update" || msg.type === "state") {
            root.playerName = msg.player_name || "";
            root.playerIdentity = msg.player_identity || "";
            root.playbackStatus = msg.playback_status || "Stopped";
            root.isPlaying = !!msg.is_playing;
            root.title = msg.title || "";
            root.artist = msg.artist || "";
            root.album = msg.album || "";
            root.artUrl = msg.art_url || "";
            root.positionMs = msg.position_ms || 0;
            root.durationMs = msg.duration_ms || 0;
            root.canGoNext = !!msg.can_go_next;
            root.canGoPrevious = !!msg.can_go_previous;
            root.canPlay = !!msg.can_play;
            root.canPause = !!msg.can_pause;
            root.hasLyrics = !!msg.has_lyrics;
            root.lyricsEnabled = msg.lyrics_enabled !== false;
            root.currentLyric = msg.current_lyric || "";
            root.nextLyric = msg.next_lyric || "";
            root.lyricIndex = typeof msg.lyric_index === "number" ? msg.lyric_index : -1;
            root.totalLyrics = typeof msg.total_lyrics === "number" ? msg.total_lyrics : 0;
        }
    }

    function togglePlay() {
        send({ action: "toggle" });
    }

    function next() {
        send({ action: "next" });
    }

    function previous() {
        send({ action: "previous" });
    }

    function setLyricsEnabled(enabled) {
        root.lyricsEnabled = enabled;
        send({ action: "set_lyrics_enabled", enabled: enabled });
    }
}
