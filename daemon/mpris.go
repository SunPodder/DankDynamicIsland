package main

import (
	"fmt"
	"log"
	"strings"
	"sync"
	"time"

	"github.com/godbus/dbus/v5"
)

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
	durationUs int64
	basePosUs  int64
	baseTime   time.Time
	rate       float64
	canNext    bool
	canPrev    bool
	canPlay    bool
	canPause   bool

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
			statusVariant, err := obj.GetProperty("org.mpris.MediaPlayer2.Player.PlaybackStatus")
			if err == nil {
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
	identityVariant, err := obj.GetProperty("org.mpris.MediaPlayer2.Identity")
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
	m.mu.Lock()
	defer m.mu.Unlock()

	// PlaybackStatus
	if val, err := obj.GetProperty("org.mpris.MediaPlayer2.Player.PlaybackStatus"); err == nil {
		if status, ok := val.Value().(string); ok {
			m.status = status
		}
	}

	// Rate
	if val, err := obj.GetProperty("org.mpris.MediaPlayer2.Player.Rate"); err == nil {
		if rate, ok := val.Value().(float64); ok && rate > 0 {
			m.rate = rate
		}
	}

	// CanGoNext / CanGoPrevious / CanPlay / CanPause
	if val, err := obj.GetProperty("org.mpris.MediaPlayer2.Player.CanGoNext"); err == nil {
		m.canNext, _ = val.Value().(bool)
	}
	if val, err := obj.GetProperty("org.mpris.MediaPlayer2.Player.CanGoPrevious"); err == nil {
		m.canPrev, _ = val.Value().(bool)
	}
	if val, err := obj.GetProperty("org.mpris.MediaPlayer2.Player.CanPlay"); err == nil {
		m.canPlay, _ = val.Value().(bool)
	}
	if val, err := obj.GetProperty("org.mpris.MediaPlayer2.Player.CanPause"); err == nil {
		m.canPause, _ = val.Value().(bool)
	}

	// Metadata
	if val, err := obj.GetProperty("org.mpris.MediaPlayer2.Player.Metadata"); err == nil {
		m.parseMetadata(val.Value())
	}

	// Position
	if val, err := obj.GetProperty("org.mpris.MediaPlayer2.Player.Position"); err == nil {
		if pos, ok := val.Value().(int64); ok {
			m.basePosUs = pos
			m.baseTime = time.Now()
		}
	} else {
		m.basePosUs = 0
		m.baseTime = time.Now()
	}

	if m.onStateChanged != nil {
		go m.onStateChanged()
	}
}

func (m *MPRISManager) parseMetadata(metaVal interface{}) {
	metaMap, ok := metaVal.(map[string]dbus.Variant)
	if !ok {
		return
	}

	if val, found := metaMap["xesam:title"]; found {
		m.title, _ = val.Value().(string)
	} else {
		m.title = ""
	}

	if val, found := metaMap["xesam:artist"]; found {
		switch v := val.Value().(type) {
		case []string:
			m.artist = strings.Join(v, ", ")
		case string:
			m.artist = v
		default:
			m.artist = ""
		}
	} else {
		m.artist = ""
	}

	if val, found := metaMap["xesam:album"]; found {
		m.album, _ = val.Value().(string)
	} else {
		m.album = ""
	}

	if val, found := metaMap["mpris:artUrl"]; found {
		m.artURL, _ = val.Value().(string)
	} else {
		m.artURL = ""
	}

	if val, found := metaMap["mpris:length"]; found {
		if l, ok := val.Value().(int64); ok {
			m.durationUs = l
		} else if l, ok := val.Value().(uint64); ok {
			m.durationUs = int64(l)
		} else {
			m.durationUs = 0
		}
	} else {
		m.durationUs = 0
	}
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
				var posUs int64
				switch v := sig.Body[0].(type) {
				case int64:
					posUs = v
				case uint64:
					posUs = int64(v)
				case int32:
					posUs = int64(v)
				case int:
					posUs = int64(v)
				case float64:
					posUs = int64(v)
				}

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
		m.parseMetadata(metaVal.Value())
		// Resync position on track change
		m.basePosUs = 0
		m.baseTime = time.Now()
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

	m.mu.Unlock()

	// Also re-query Position on status change if playing
	if stateModified {
		m.mu.RLock()
		active := m.activeBus
		m.mu.RUnlock()
		if active != "" {
			obj := m.conn.Object(active, "/org/mpris/MediaPlayer2")
			if posVal, err := obj.GetProperty("org.mpris.MediaPlayer2.Player.Position"); err == nil {
				if pos, ok := posVal.Value().(int64); ok {
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

// SyncPosition queries the actual current playback position from the active MPRIS player via D-Bus
func (m *MPRISManager) SyncPosition() int64 {
	m.mu.RLock()
	active := m.activeBus
	m.mu.RUnlock()

	if active == "" {
		return 0
	}

	obj := m.conn.Object(active, "/org/mpris/MediaPlayer2")
	val, err := obj.GetProperty("org.mpris.MediaPlayer2.Player.Position")
	if err == nil {
		var posUs int64
		switch v := val.Value().(type) {
		case int64:
			posUs = v
		case uint64:
			posUs = int64(v)
		case int32:
			posUs = int64(v)
		case int:
			posUs = int64(v)
		case float64:
			posUs = int64(v)
		}

		m.mu.Lock()
		m.basePosUs = posUs
		m.baseTime = time.Now()
		m.mu.Unlock()
		return posUs / 1000
	}

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
