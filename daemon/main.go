package main

import (
	"flag"
	"log"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"
)

type DaemonApp struct {
	mu             sync.RWMutex
	mpris          *MPRISManager
	lyrics         *LyricsManager
	server         *Server
	lyricsEnabled  bool
	currentTrack   string
	currentLyrics  []LyricLine
	lastSentLyric  string
	lastSentStatus string
	lastSentTitle  string
	lastSentArtist string
	lastSentPosMs  int64
	tickerStop     chan struct{}
}

func main() {
	port := flag.Int("port", 48123, "WebSocket port to listen on")
	flag.Parse()

	log.Println("[Daemon] Starting DankDynamicIsland Daemon...")

	app := &DaemonApp{
		lyricsEnabled: true,
		lyrics:        NewLyricsManager(),
		tickerStop:    make(chan struct{}),
	}

	server := NewServer(*port, app.handleClientAction, app.handleClientJoin)
	app.server = server

	mpris, err := NewMPRISManager(app.handleMPRISStateChange)
	if err != nil {
		log.Fatalf("[Daemon] Failed to initialize MPRIS manager: %v", err)
	}
	app.mpris = mpris

	if err := server.Start(); err != nil {
		log.Fatalf("[Daemon] Failed to start server: %v", err)
	}

	go app.runLoop()

	// Initial sync
	app.handleMPRISStateChange()

	// Wait for OS signals
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)
	<-sigCh

	log.Println("[Daemon] Shutting down...")
	close(app.tickerStop)
	server.Stop()
	mpris.Close()
	log.Println("[Daemon] Stopped cleanly")
}

func (a *DaemonApp) handleClientAction(msg ClientMessage) {
	log.Printf("[Daemon] Received client action: %s", msg.Action)
	switch msg.Action {
	case "play", "pause", "toggle":
		_ = a.mpris.PlayPause()
	case "next":
		_ = a.mpris.Next()
	case "previous":
		_ = a.mpris.Previous()
	case "seek":
		if err := a.mpris.SeekTo(msg.PositionMs); err != nil {
			log.Printf("[Daemon] Seek to %dms failed: %v", msg.PositionMs, err)
		}
		a.broadcastCurrentState()
	case "set_lyrics_enabled":
		if msg.Enabled != nil {
			a.mu.Lock()
			a.lyricsEnabled = *msg.Enabled
			a.mu.Unlock()
			a.broadcastCurrentState()
		}
	case "get_state":
		a.broadcastCurrentState()
	}
}

func (a *DaemonApp) handleClientJoin() {
	a.broadcastCurrentState()
}

func (a *DaemonApp) handleMPRISStateChange() {
	_, _, _, title, artist, album, _, _, _, _, _ := a.mpris.GetMediaInfo()
	durationMs := a.mpris.GetDurationMs()

	trackKey := title + "||" + artist

	a.mu.Lock()
	trackChanged := trackKey != a.currentTrack
	if trackChanged {
		a.currentTrack = trackKey
		a.currentLyrics = nil
		a.lastSentLyric = ""
	}
	lyricsEnabled := a.lyricsEnabled
	a.mu.Unlock()

	if trackChanged && title != "" && lyricsEnabled {
		go func(t, art, alb string, durMs int64) {
			durSec := float64(durMs) / 1000.0
			lines, err := a.lyrics.FetchLyrics(t, art, alb, durSec)
			if err == nil && len(lines) > 0 {
				a.mu.Lock()
				if a.currentTrack == t+"||"+art {
					a.currentLyrics = lines
					log.Printf("[Daemon] Loaded %d synced lyrics for '%s'", len(lines), t)
				}
				a.mu.Unlock()
				a.broadcastCurrentState()
			} else {
				log.Printf("[Daemon] No lyrics for '%s': %v", t, err)
				a.broadcastCurrentState()
			}
		}(title, artist, album, durationMs)
	}

	// Query fresh position from D-Bus before calculating state
	a.mpris.SyncPosition()
	a.broadcastCurrentState()
}

func (a *DaemonApp) runLoop() {
	ticker := time.NewTicker(60 * time.Millisecond)
	defer ticker.Stop()

	tickCount := 0
	for {
		select {
		case <-a.tickerStop:
			return
		case <-ticker.C:
			tickCount++
			// Sample MPRIS Position every ~120ms (2 ticks). Frequent sampling
			// lets positionReconciler re-anchor second-quantized reporters
			// (Firefox) within one poll interval of each 1s step.
			if tickCount%2 == 0 {
				a.mpris.SyncPosition()
			}
			a.tick()
		}
	}
}

func (a *DaemonApp) tick() {
	_, _, status, title, _, _, _, _, _, _, _ := a.mpris.GetMediaInfo()
	if status != "Playing" || title == "" {
		return
	}

	posMs := a.mpris.GetPositionMs()

	a.mu.RLock()
	lyricsEnabled := a.lyricsEnabled
	lyrics := a.currentLyrics
	lastLyric := a.lastSentLyric
	a.mu.RUnlock()

	if lyricsEnabled && len(lyrics) > 0 {
		currLyric, _, _, _ := a.lyrics.GetCurrentLyric(lyrics, posMs)
		if currLyric != lastLyric {
			a.mu.Lock()
			a.lastSentLyric = currLyric
			a.mu.Unlock()
			a.broadcastCurrentState()
		}
	}
}

func (a *DaemonApp) buildState() MediaState {
	activeBus, identity, status, title, artist, album, artURL, canNext, canPrev, canPlay, canPause := a.mpris.GetMediaInfo()
	posMs := a.mpris.GetPositionMs()
	canSeek := a.mpris.GetCanSeek()
	durMs := a.mpris.GetDurationMs()

	a.mu.RLock()
	lyricsEnabled := a.lyricsEnabled
	lyrics := a.currentLyrics
	a.mu.RUnlock()

	hasLyrics := len(lyrics) > 0
	currLyric := ""
	nextLyric := ""
	lyricIdx := -1
	totalLyrics := len(lyrics)

	if hasLyrics && lyricsEnabled {
		currLyric, nextLyric, lyricIdx, _ = a.lyrics.GetCurrentLyric(lyrics, posMs)
	}

	isPlaying := status == "Playing"

	return MediaState{
		Type:           "media_update",
		Connected:      activeBus != "",
		PlayerName:     activeBus,
		PlayerIdentity: identity,
		PlaybackStatus: status,
		IsPlaying:      isPlaying,
		Title:          title,
		Artist:         artist,
		Album:          album,
		ArtURL:         artURL,
		PositionMs:     posMs,
		DurationMs:     durMs,
		CanGoNext:      canNext,
		CanGoPrevious:  canPrev,
		CanPlay:        canPlay,
		CanPause:       canPause,
		CanSeek:        canSeek,
		HasLyrics:      hasLyrics,
		LyricsEnabled:  lyricsEnabled,
		CurrentLyric:   currLyric,
		NextLyric:      nextLyric,
		LyricIndex:     lyricIdx,
		TotalLyrics:    totalLyrics,
	}
}

func (a *DaemonApp) broadcastCurrentState() {
	state := a.buildState()
	a.server.BroadcastState(state)
}
