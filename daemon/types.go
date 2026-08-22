package main

// MediaState represents the full media and lyrics state streamed to clients
type MediaState struct {
	Type           string `json:"type"` // "media_update" or "state"
	Connected      bool   `json:"connected"`
	PlayerName     string `json:"player_name"`
	PlayerIdentity string `json:"player_identity"`
	PlaybackStatus string `json:"playback_status"` // "Playing", "Paused", "Stopped"
	IsPlaying      bool   `json:"is_playing"`
	Title          string `json:"title"`
	Artist         string `json:"artist"`
	Album          string `json:"album"`
	ArtURL         string `json:"art_url"`
	PositionMs     int64  `json:"position_ms"`
	DurationMs     int64  `json:"duration_ms"`
	CanGoNext      bool   `json:"can_go_next"`
	CanGoPrevious  bool   `json:"can_go_previous"`
	CanPlay        bool   `json:"can_play"`
	CanPause       bool   `json:"can_pause"`
	CanSeek        bool   `json:"can_seek"`
	HasLyrics      bool   `json:"has_lyrics"`
	LyricsEnabled  bool   `json:"lyrics_enabled"`
	CurrentLyric   string `json:"current_lyric"`
	NextLyric      string `json:"next_lyric"`
	LyricIndex     int    `json:"lyric_index"`
	TotalLyrics    int    `json:"total_lyrics"`
}

// LyricLine represents a single synchronized lyric entry
type LyricLine struct {
	TimeMs int64  `json:"time_ms"`
	Text   string `json:"text"`
}

// LRCLIBResponse models the JSON returned by lrclib.net API
type LRCLIBResponse struct {
	ID           int     `json:"id"`
	Name         string  `json:"name"`
	TrackName    string  `json:"trackName"`
	ArtistName   string  `json:"artistName"`
	AlbumName    string  `json:"albumName"`
	Duration     float64 `json:"duration"`
	Instrumental bool    `json:"instrumental"`
	PlainLyrics  string  `json:"plainLyrics"`
	SyncedLyrics string  `json:"syncedLyrics"`
}

// ClientMessage represents incoming command from WebSocket / IPC client
type ClientMessage struct {
	Action     string `json:"action"` // "play", "pause", "toggle", "next", "previous", "seek", "set_lyrics_enabled", "get_state"
	PositionMs int64  `json:"position_ms,omitempty"`
	Enabled    *bool  `json:"enabled,omitempty"`
}
