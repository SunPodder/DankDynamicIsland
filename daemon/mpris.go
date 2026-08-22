package main

import (
	"context"
	"fmt"
	"log"
	"strings"
	"sync"
	"time"

	"github.com/godbus/dbus/v5"
)

// dbusCallTimeout bounds every player property round trip. godbus's default
// timeout is 25s; a throttled or hung player (e.g. a backgrounded Firefox
// tab) must never stall the daemon for that long.
const dbusCallTimeout = 500 * time.Millisecond

// property fetches one D-Bus property with a bounded timeout.
func property(obj dbus.BusObject, iface, name string) (dbus.Variant, error) {
	ctx, cancel := context.WithTimeout(context.Background(), dbusCallTimeout)
	defer cancel()
	call := obj.CallWithContext(ctx, "org.freedesktop.DBus.Properties.Get", 0, iface, name)
	if call.Err != nil {
		return dbus.Variant{}, call.Err
	}
	if len(call.Body) != 1 {
		return dbus.Variant{}, fmt.Errorf("unexpected reply body for %s", name)
	}
	v, ok := call.Body[0].(dbus.Variant)
	if !ok {
		return dbus.Variant{}, fmt.Errorf("unexpected reply type for %s", name)
	}
	return v, nil
}

// playerProperty fetches one org.mpris.MediaPlayer2.Player property.
func playerProperty(obj dbus.BusObject, name string) (dbus.Variant, error) {
	return property(obj, "org.mpris.MediaPlayer2.Player", name)
}

// MPRISManager monitors Linux media players via D-Bus
type MPRISManager struct {
	conn       *dbus.Conn
	mu         sync.RWMutex
	activeBus  string
	identity   string
	status     string
	title      string
	artist     string
	album      string
	artURL     string
	trackID    string
	durationUs int64
	basePosUs  int64
	baseTime   time.Time
	rate       float64
	reconciler positionReconciler
	lastSyncAt time.Time
	canNext    bool
	canPrev    bool
	canPlay    bool
	canPause   bool
	canSeek    bool

	onStateChanged func()
}

// NewMPRISManager creates and initializes MPRISManager
func NewMPRISManager(onStateChanged func()) (*MPRISManager, error) {
	conn, err := dbus.SessionBus()
	if err != nil {
		return nil, fmt.Errorf("failed to connect to session bus: %w", err)
	}

	m := &MPRISManager{
		conn:           conn,
		rate:           1.0,
		onStateChanged: onStateChanged,
	}

	// Add D-Bus match rules for MPRIS signals
	ruleProperties := "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path='/org/mpris/MediaPlayer2'"
	if err := conn.BusObject().Call("org.freedesktop.DBus.AddMatch", 0, ruleProperties).Err; err != nil {
		log.Printf("[MPRIS] Warning: failed to add match for PropertiesChanged: %v", err)
	}

	ruleSeeked := "type='signal',interface='org.mpris.MediaPlayer2.Player',member='Seeked',path='/org/mpris/MediaPlayer2'"
	if err := conn.BusObject().Call("org.freedesktop.DBus.AddMatch", 0, ruleSeeked).Err; err != nil {
		log.Printf("[MPRIS] Warning: failed to add match for Seeked: %v", err)
	}

	ruleOwner := "type='signal',interface='org.freedesktop.DBus',member='NameOwnerChanged'"
	if err := conn.BusObject().Call("org.freedesktop.DBus.AddMatch", 0, ruleOwner).Err; err != nil {
		log.Printf("[MPRIS] Warning: failed to add match for NameOwnerChanged: %v", err)
	}

	go m.listenSignals()

	// Initial scan for active players
	m.ScanPlayers()

	return m, nil
}

// Close closes the D-Bus connection
func (m *MPRISManager) Close() {
	if m.conn != nil {
		m.conn.Close()
	}
}

// ScanPlayers finds available MPRIS media players and selects the best active one
func (m *MPRISManager) ScanPlayers() {
	var names []string
	if err := m.conn.BusObject().Call("org.freedesktop.DBus.ListNames", 0).Store(&names); err != nil {
		log.Printf("[MPRIS] Failed to list bus names: %v", err)
		return
	}

	var bestPlayer string

	for _, name := range names {
		if strings.HasPrefix(name, "org.mpris.MediaPlayer2.") {
			// Check if this player is playing
			obj := m.conn.Object(name, "/org/mpris/MediaPlayer2")
			if statusVariant, err := playerProperty(obj, "PlaybackStatus"); err == nil {
				status, _ := statusVariant.Value().(string)
				if status == "Playing" {
					bestPlayer = name
					break
				}
				if bestPlayer == "" {
					bestPlayer = name
				}
			}
		}
	}

	if bestPlayer != "" {
		m.SwitchToPlayer(bestPlayer)
	} else {
		m.mu.Lock()
		m.activeBus = ""
		m.status = "Stopped"
		m.title = ""
		m.artist = ""
		m.album = ""
		m.basePosUs = 0
		m.durationUs = 0
		m.mu.Unlock()
		if m.onStateChanged != nil {
			m.onStateChanged()
		}
	}
}

// SwitchToPlayer sets the currently tracked MPRIS player
func (m *MPRISManager) SwitchToPlayer(busName string) {
	m.mu.Lock()
	m.activeBus = busName
	m.mu.Unlock()

	obj := m.conn.Object(busName, "/org/mpris/MediaPlayer2")

	// Get player identity
	identityVariant, err := property(obj, "org.mpris.MediaPlayer2", "Identity")
	var identity string
	if err == nil {
		identity, _ = identityVariant.Value().(string)
	}
	if identity == "" {
		parts := strings.Split(busName, ".")
		identity = parts[len(parts)-1]
	}

	m.mu.Lock()
	m.identity = identity
	m.mu.Unlock()

	m.refreshAllProperties(obj)
}

func (m *MPRISManager) refreshAllProperties(obj dbus.BusObject) {
	// Gather everything BEFORE taking the lock: D-Bus round trips must never
	// happen while holding m.mu, or a hung player freezes every reader
	// (broadcasts, ticks, lyric updates) for the length of the call.
	var status string
	rate := 1.0
	var canNext, canPrev, canPlay, canPause, canSeek bool
	var gotNext, gotPrev, gotPlay, gotPause, gotSeek bool
	var meta trackMeta
	haveMeta := false
	var posUs int64
	havePos := false

	if v, err := playerProperty(obj, "PlaybackStatus"); err == nil {
		status, _ = v.Value().(string)
	}
	if v, err := playerProperty(obj, "Rate"); err == nil {
		if r, ok := v.Value().(float64); ok && r > 0 {
			rate = r
		}
	}
	if v, err := playerProperty(obj, "CanGoNext"); err == nil {
		canNext, _ = v.Value().(bool)
		gotNext = true
	}
	if v, err := playerProperty(obj, "CanGoPrevious"); err == nil {
		canPrev, _ = v.Value().(bool)
		gotPrev = true
	}
	if v, err := playerProperty(obj, "CanPlay"); err == nil {
		canPlay, _ = v.Value().(bool)
		gotPlay = true
	}
	if v, err := playerProperty(obj, "CanPause"); err == nil {
		canPause, _ = v.Value().(bool)
		gotPause = true
	}
	if v, err := playerProperty(obj, "CanSeek"); err == nil {
		canSeek, _ = v.Value().(bool)
		gotSeek = true
	}
	if v, err := playerProperty(obj, "Metadata"); err == nil {
		meta = metadataFromVariant(v.Value())
		haveMeta = true
	}
	if v, err := playerProperty(obj, "Position"); err == nil {
		if p, ok := positionUsFromVariant(v.Value()); ok {
			posUs, havePos = p, true
		}
	}

	m.mu.Lock()
	if status != "" {
		m.status = status
	}
	m.rate = rate
	// Apply capability flags only from successful reads: a timed-out or
	// hiccupped property fetch must not flip a working player's flags to
	// false (clients hide seek controls off of canSeek).
	if gotNext {
		m.canNext = canNext
	}
	if gotPrev {
		m.canPrev = canPrev
	}
	if gotPlay {
		m.canPlay = canPlay
	}
	if gotPause {
		m.canPause = canPause
	}
	if gotSeek {
		m.canSeek = canSeek
	}
	if haveMeta {
		// Players sometimes re-emit metadata for the SAME track with optional
		// fields dropped (Firefox loses mpris:length after a seek). Merge only
		// present fields so duration/title never regress to zero; a genuine
		// track change (different track id) applies wholesale.
		if meta.trackID != "" && meta.trackID == m.trackID {
			if meta.title != "" {
				m.title = meta.title
			}
			if meta.artist != "" {
				m.artist = meta.artist
			}
			if meta.album != "" {
				m.album = meta.album
			}
			if meta.artURL != "" {
				m.artURL = meta.artURL
			}
			if meta.durationUs > 0 {
				m.durationUs = meta.durationUs
			}
		} else {
			m.title = meta.title
			m.artist = meta.artist
			m.album = meta.album
			m.artURL = meta.artURL
			m.trackID = meta.trackID
			m.durationUs = meta.durationUs
		}
	}
	if havePos {
		m.basePosUs = posUs
		m.baseTime = time.Now()
	}
	// On a failed Position fetch keep the previous base: with bounded
	// timeouts a transient blip must not restart lyrics from the top.
	m.mu.Unlock()

	if m.onStateChanged != nil {
		go m.onStateChanged()
	}
}

// trackMeta is the parsed subset of MPRIS Metadata the daemon uses.
type trackMeta struct {
	title      string
	artist     string
	album      string
	artURL     string
	trackID    string
	durationUs int64
}

func metadataFromVariant(metaVal interface{}) trackMeta {
	var tm trackMeta
	metaMap, ok := metaVal.(map[string]dbus.Variant)
	if !ok {
		return tm
	}

	if val, found := metaMap["xesam:title"]; found {
		tm.title, _ = val.Value().(string)
	}

	if val, found := metaMap["xesam:artist"]; found {
		switch v := val.Value().(type) {
		case []string:
			tm.artist = strings.Join(v, ", ")
		case string:
			tm.artist = v
		}
	}

	if val, found := metaMap["xesam:album"]; found {
		tm.album, _ = val.Value().(string)
	}

	if val, found := metaMap["mpris:artUrl"]; found {
		tm.artURL, _ = val.Value().(string)
	}

	if val, found := metaMap["mpris:trackid"]; found {
		switch v := val.Value().(type) {
		case string:
			tm.trackID = v
		case dbus.ObjectPath:
			tm.trackID = string(v)
		}
	}
	if val, found := metaMap["mpris:length"]; found {
		switch l := val.Value().(type) {
		case int64:
			tm.durationUs = l
		case uint64:
			tm.durationUs = int64(l)
		}
	}

	return tm
}

func (m *MPRISManager) listenSignals() {
	ch := make(chan *dbus.Signal, 64)
	m.conn.Signal(ch)

	for sig := range ch {
		if sig == nil {
			continue
		}

		switch sig.Name {
		case "org.freedesktop.DBus.NameOwnerChanged":
			if len(sig.Body) == 3 {
				name, _ := sig.Body[0].(string)
				oldOwner, _ := sig.Body[1].(string)
				newOwner, _ := sig.Body[2].(string)

				if strings.HasPrefix(name, "org.mpris.MediaPlayer2.") {
					if oldOwner != "" && newOwner == "" {
						// Player closed
						m.mu.RLock()
						active := m.activeBus
						m.mu.RUnlock()
						if active == name {
							log.Printf("[MPRIS] Active player %s closed, scanning...", name)
							m.ScanPlayers()
						}
					} else if newOwner != "" {
						// New player opened
						m.ScanPlayers()
					}
				}
			}

		case "org.freedesktop.DBus.Properties.PropertiesChanged":
			if len(sig.Body) >= 2 {
				iface, _ := sig.Body[0].(string)
				if iface == "org.mpris.MediaPlayer2.Player" {
					sender := sig.Sender
					m.mu.RLock()
					active := m.activeBus
					m.mu.RUnlock()

					// If sender is active player or we don't have an active player yet
					if active == "" || active == sender || strings.HasPrefix(active, "org.mpris.MediaPlayer2.") {
						changedMap, _ := sig.Body[1].(map[string]dbus.Variant)
						m.handlePropertiesChanged(sig.Sender, changedMap)
					}
				}
			}

		case "org.mpris.MediaPlayer2.Player.Seeked":
			if len(sig.Body) >= 1 {
				posUs, _ := positionUsFromVariant(sig.Body[0])
				m.mu.Lock()
				m.basePosUs = posUs
				m.baseTime = time.Now()
				m.mu.Unlock()

				// Also query exact position from D-Bus to guarantee alignment
				go func() {
					m.SyncPosition()
					if m.onStateChanged != nil {
						m.onStateChanged()
					}
				}()
			}
		}
	}
}

func (m *MPRISManager) handlePropertiesChanged(sender string, changed map[string]dbus.Variant) {
	m.mu.Lock()
	stateModified := false

	if statusVal, ok := changed["PlaybackStatus"]; ok {
		if s, ok := statusVal.Value().(string); ok {
			// If a different player starts playing, switch to it
			if s == "Playing" && m.activeBus != sender {
				m.mu.Unlock()
				m.SwitchToPlayer(sender)
				return
			}
			m.status = s
			stateModified = true
		}
	}

	if metaVal, ok := changed["Metadata"]; ok {
		meta := metadataFromVariant(metaVal.Value())
		// Same-track re-emission: merge, never regress to empty/zero (see
		// refreshAllProperties). Genuine track change: apply wholesale and
		// resync the position clock.
		if meta.trackID != "" && meta.trackID == m.trackID {
			if meta.title != "" {
				m.title = meta.title
			}
			if meta.artist != "" {
				m.artist = meta.artist
			}
			if meta.album != "" {
				m.album = meta.album
			}
			if meta.artURL != "" {
				m.artURL = meta.artURL
			}
			if meta.durationUs > 0 {
				m.durationUs = meta.durationUs
			}
		} else {
			m.title = meta.title
			m.artist = meta.artist
			m.album = meta.album
			m.artURL = meta.artURL
			m.trackID = meta.trackID
			m.durationUs = meta.durationUs
			m.basePosUs = 0
			m.baseTime = time.Now()
		}
		stateModified = true
	}
	if rateVal, ok := changed["Rate"]; ok {
		if r, ok := rateVal.Value().(float64); ok && r > 0 {
			m.rate = r
		}
	}

	if val, ok := changed["CanGoNext"]; ok {
		m.canNext, _ = val.Value().(bool)
		stateModified = true
	}
	if val, ok := changed["CanGoPrevious"]; ok {
		m.canPrev, _ = val.Value().(bool)
		stateModified = true
	}
	if val, ok := changed["CanPlay"]; ok {
		m.canPlay, _ = val.Value().(bool)
		stateModified = true
	}
	if val, ok := changed["CanPause"]; ok {
		m.canPause, _ = val.Value().(bool)
		stateModified = true
	}
	if val, ok := changed["CanSeek"]; ok {
		m.canSeek, _ = val.Value().(bool)
		stateModified = true
	}

	m.mu.Unlock()

	// Also re-query Position on status change if playing
	if stateModified {
		m.mu.RLock()
		active := m.activeBus
		m.mu.RUnlock()
		if active != "" {
			obj := m.conn.Object(active, "/org/mpris/MediaPlayer2")
			if posVal, err := playerProperty(obj, "Position"); err == nil {
				if pos, ok := positionUsFromVariant(posVal.Value()); ok && pos > 0 {
					// Ignore zero samples: some players (Firefox) report
					// Position=0 while paused or after seeks; anchoring to it
					// would collapse the clock. Real restarts re-anchor via
					// Seeked/metadata change instead.
					m.mu.Lock()
					m.basePosUs = pos
					m.baseTime = time.Now()
					m.mu.Unlock()
				}
			}
		}
		if m.onStateChanged != nil {
			m.onStateChanged()
		}
	}
}

// SyncPosition samples the active player's MPRIS Position and folds it into
// the interpolation clock via positionReconciler, which re-anchors only on
// informative samples (see position.go). Players like Firefox report Position
// quantized to whole seconds; anchoring to every raw sample would drag the
// lyric clock up to a second behind playback.
func (m *MPRISManager) SyncPosition() int64 {
	m.mu.RLock()
	active := m.activeBus
	status := m.status
	m.mu.RUnlock()

	if active == "" || status != "Playing" {
		// Nothing advancing; pause/resume transitions requery Position via
		// handlePropertiesChanged, so there is nothing to reconcile.
		return m.GetPositionMs()
	}

	obj := m.conn.Object(active, "/org/mpris/MediaPlayer2")
	val, err := playerProperty(obj, "Position")
	if err != nil {
		return m.GetPositionMs()
	}
	sampleUs, ok := positionUsFromVariant(val.Value())
	if !ok {
		return m.GetPositionMs()
	}

	now := time.Now()
	m.mu.Lock()
	gapUs := int64(dbusCallTimeout.Microseconds())
	if !m.lastSyncAt.IsZero() {
		gapUs = now.Sub(m.lastSyncAt).Microseconds()
	}
	m.lastSyncAt = now
	estUs := m.basePosUs + int64(float64(now.Sub(m.baseTime).Microseconds())*m.rate)
	// Degraded players (Firefox after a seek-during-playback) report
	// Position=0 continuously while audio actually advances. Folding those
	// samples collapses the clock into a 0..1s sawtooth. A genuinely playing
	// player cannot sit at exactly zero once the estimate is past two
	// seconds, so free-run on interpolation until real samples return.
	if status == "Playing" && sampleUs == 0 && estUs > 2*secondQuantumUs {
		m.mu.Unlock()
		return m.GetPositionMs()
	}
	if newBase, anchor := m.reconciler.reconcile(estUs, sampleUs, gapUs); anchor {
		m.basePosUs = newBase
		m.baseTime = now
	}
	m.mu.Unlock()

	return m.GetPositionMs()
}

// GetPositionMs calculates current playback position in milliseconds
func (m *MPRISManager) GetPositionMs() int64 {
	m.mu.RLock()
	defer m.mu.RUnlock()

	if m.status != "Playing" {
		return m.basePosUs / 1000
	}

	elapsedUs := time.Since(m.baseTime).Microseconds()
	adjustedElapsed := int64(float64(elapsedUs) * m.rate)
	currentUs := m.basePosUs + adjustedElapsed

	if m.durationUs > 0 && currentUs > m.durationUs {
		currentUs = m.durationUs
	}

	return currentUs / 1000
}

// GetDurationMs returns total duration in milliseconds
func (m *MPRISManager) GetDurationMs() int64 {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.durationUs / 1000
}

// GetMediaInfo returns current metadata & player details
func (m *MPRISManager) GetMediaInfo() (activeBus, identity, status, title, artist, album, artURL string, canNext, canPrev, canPlay, canPause bool) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.activeBus, m.identity, m.status, m.title, m.artist, m.album, m.artURL, m.canNext, m.canPrev, m.canPlay, m.canPause
}

// PlayPause toggles playback on active player
func (m *MPRISManager) PlayPause() error {
	m.mu.RLock()
	active := m.activeBus
	m.mu.RUnlock()
	if active == "" {
		return fmt.Errorf("no active player")
	}
	obj := m.conn.Object(active, "/org/mpris/MediaPlayer2")
	return obj.Call("org.mpris.MediaPlayer2.Player.PlayPause", 0).Err
}

// Next skips to next track
func (m *MPRISManager) Next() error {
	m.mu.RLock()
	active := m.activeBus
	m.mu.RUnlock()
	if active == "" {
		return fmt.Errorf("no active player")
	}
	obj := m.conn.Object(active, "/org/mpris/MediaPlayer2")
	return obj.Call("org.mpris.MediaPlayer2.Player.Next", 0).Err
}

// Previous rewinds or skips to previous track
func (m *MPRISManager) Previous() error {
	m.mu.RLock()
	active := m.activeBus
	m.mu.RUnlock()
	if active == "" {
		return fmt.Errorf("no active player")
	}
	obj := m.conn.Object(active, "/org/mpris/MediaPlayer2")
	return obj.Call("org.mpris.MediaPlayer2.Player.Previous", 0).Err
}

// GetCanSeek reports whether the active player supports seeking
func (m *MPRISManager) GetCanSeek() bool {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.canSeek
}

// SeekTo positions the active player at an absolute offset in milliseconds.
// Prefers SetPosition (needs the player's track id) and falls back to a
// relative Seek for players that don't expose one.
func (m *MPRISManager) SeekTo(positionMs int64) error {
	m.mu.RLock()
	active := m.activeBus
	trackID := m.trackID
	m.mu.RUnlock()
	if active == "" {
		return fmt.Errorf("no active player")
	}
	obj := m.conn.Object(active, "/org/mpris/MediaPlayer2")
	posUs := positionMs * 1000
	if trackID != "" && dbus.ObjectPath(trackID).IsValid() {
		return obj.Call("org.mpris.MediaPlayer2.Player.SetPosition", 0, dbus.ObjectPath(trackID), posUs).Err
	}
	return obj.Call("org.mpris.MediaPlayer2.Player.Seek", 0, posUs-m.GetPositionMs()*1000).Err
}
