package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

var (
	lrcTimestampRegex = regexp.MustCompile(`\[(\d{2}):(\d{2})\.(\d{2,3})\]`)
	cleanTitleRegex   = regexp.MustCompile(`(?i)\s*[\(\[\{](?:official\s+(?:video|audio|music\s+video)|feat\.?|ft\.?|lyrics|remaster(?:ed)?|hd|4k)[^\)\]\}]*[\)\]\}]`)
)

type fetchResult struct {
	lines []LyricLine
	err   error
}

// LyricsManager handles fetching, caching, and synchronizing lyrics from LRCLIB
type LyricsManager struct {
	client      *http.Client
	cacheMu     sync.RWMutex
	cache       map[string][]LyricLine
	negative    map[string]bool
	inFlightMu  sync.Mutex
	inFlight    map[string][]chan fetchResult
	rateLimitMu sync.Mutex
	lastReqTime time.Time
}

// NewLyricsManager creates a new LyricsManager
func NewLyricsManager() *LyricsManager {
	return &LyricsManager{
		client: &http.Client{
			Timeout: 8 * time.Second,
		},
		cache:    make(map[string][]LyricLine),
		negative: make(map[string]bool),
		inFlight: make(map[string][]chan fetchResult),
	}
}

func cacheKey(title, artist string) string {
	return strings.ToLower(strings.TrimSpace(title)) + "||" + strings.ToLower(strings.TrimSpace(artist))
}

// CleanTitle removes common video/audio suffixes from title to improve LRCLIB lookup
func CleanTitle(title string) string {
	cleaned := cleanTitleRegex.ReplaceAllString(title, "")
	cleaned = strings.TrimSpace(cleaned)
	if cleaned == "" {
		return title
	}
	return cleaned
}

func (lm *LyricsManager) enforceRateLimit() {
	lm.rateLimitMu.Lock()
	defer lm.rateLimitMu.Unlock()

	elapsed := time.Since(lm.lastReqTime)
	if elapsed < 350*time.Millisecond {
		time.Sleep(350*time.Millisecond - elapsed)
	}
	lm.lastReqTime = time.Now()
}

// FetchLyrics fetches synced lyrics for the given track from LRCLIB once, then caches
func (lm *LyricsManager) FetchLyrics(title, artist, album string, durationSec float64) ([]LyricLine, error) {
	if strings.TrimSpace(title) == "" {
		return nil, fmt.Errorf("empty title")
	}

	key := cacheKey(title, artist)

	lm.cacheMu.RLock()
	if lm.negative[key] {
		lm.cacheMu.RUnlock()
		return nil, fmt.Errorf("no synced lyrics found (cached)")
	}
	if lines, found := lm.cache[key]; found {
		lm.cacheMu.RUnlock()
		return lines, nil
	}
	lm.cacheMu.RUnlock()

	// Singleflight: coalesce concurrent requests for the same track
	resCh := make(chan fetchResult, 1)
	lm.inFlightMu.Lock()
	if waiters, ok := lm.inFlight[key]; ok {
		lm.inFlight[key] = append(waiters, resCh)
		lm.inFlightMu.Unlock()
		res := <-resCh
		return res.lines, res.err
	}
	lm.inFlight[key] = []chan fetchResult{resCh}
	lm.inFlightMu.Unlock()

	var lines []LyricLine
	var err error

	defer func() {
		lm.inFlightMu.Lock()
		waiters := lm.inFlight[key]
		delete(lm.inFlight, key)
		lm.inFlightMu.Unlock()

		for _, w := range waiters {
			w <- fetchResult{lines: lines, err: err}
		}
	}()

	// 1. Try exact get endpoint
	lm.enforceRateLimit()
	lines, err = lm.fetchExact(title, artist, album, durationSec)
	if err == nil && len(lines) > 0 {
		lm.cacheMu.Lock()
		lm.cache[key] = lines
		lm.cacheMu.Unlock()
		return lines, nil
	}

	// 2. If cleaned title differs, try cleaned title
	cleanT := CleanTitle(title)
	if cleanT != title {
		lm.enforceRateLimit()
		lines, err = lm.fetchExact(cleanT, artist, album, durationSec)
		if err == nil && len(lines) > 0 {
			lm.cacheMu.Lock()
			lm.cache[key] = lines
			lm.cacheMu.Unlock()
			return lines, nil
		}
	}

	// 3. Fallback to search endpoint
	lm.enforceRateLimit()
	lines, err = lm.fetchSearch(cleanT, artist)
	if err == nil && len(lines) > 0 {
		lm.cacheMu.Lock()
		lm.cache[key] = lines
		lm.cacheMu.Unlock()
		return lines, nil
	}

	// Mark as negative lookup so we never query LRCLIB again for this track
	lm.cacheMu.Lock()
	lm.negative[key] = true
	lm.cacheMu.Unlock()

	err = fmt.Errorf("no synced lyrics found for %s - %s", title, artist)
	return nil, err
}

func (lm *LyricsManager) fetchExact(title, artist, album string, durationSec float64) ([]LyricLine, error) {
	params := url.Values{}
	params.Set("track_name", title)
	if artist != "" {
		params.Set("artist_name", artist)
	}
	if album != "" {
		params.Set("album_name", album)
	}
	if durationSec > 0 {
		params.Set("duration", fmt.Sprintf("%.0f", durationSec))
	}

	apiURL := "https://lrclib.net/api/get?" + params.Encode()
	req, err := http.NewRequest("GET", apiURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "DankDynamicIsland/1.0 (https://github.com/SunPodder/DankDynamicIsland)")

	resp, err := lm.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("LRCLIB get returned status %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var data LRCLIBResponse
	if err := json.Unmarshal(body, &data); err != nil {
		return nil, err
	}

	if data.SyncedLyrics == "" {
		return nil, fmt.Errorf("no synced lyrics in response")
	}

	lines := ParseLRC(data.SyncedLyrics)
	return lines, nil
}

func (lm *LyricsManager) fetchSearch(title, artist string) ([]LyricLine, error) {
	params := url.Values{}
	params.Set("track_name", title)
	if artist != "" {
		params.Set("artist_name", artist)
	}

	apiURL := "https://lrclib.net/api/search?" + params.Encode()
	req, err := http.NewRequest("GET", apiURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "DankDynamicIsland/1.0 (https://github.com/SunPodder/DankDynamicIsland)")

	resp, err := lm.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("LRCLIB search returned status %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var results []LRCLIBResponse
	if err := json.Unmarshal(body, &results); err != nil {
		return nil, err
	}

	for _, item := range results {
		if item.SyncedLyrics != "" {
			lines := ParseLRC(item.SyncedLyrics)
			if len(lines) > 0 {
				return lines, nil
			}
		}
	}

	return nil, fmt.Errorf("no synced lyrics in search results")
}

// ParseLRC parses standard LRC timestamped text into a slice of LyricLine
func ParseLRC(lrcText string) []LyricLine {
	var lines []LyricLine
	rawLines := strings.Split(lrcText, "\n")

	for _, rawLine := range rawLines {
		rawLine = strings.TrimSpace(rawLine)
		if rawLine == "" {
			continue
		}

		matches := lrcTimestampRegex.FindAllStringSubmatch(rawLine, -1)
		if len(matches) == 0 {
			continue
		}

		textIndex := lrcTimestampRegex.ReplaceAllString(rawLine, "")
		text := strings.TrimSpace(textIndex)

		for _, match := range matches {
			if len(match) < 4 {
				continue
			}
			min, err1 := strconv.ParseInt(match[1], 10, 64)
			sec, err2 := strconv.ParseInt(match[2], 10, 64)
			fracStr := match[3]
			if len(fracStr) == 2 {
				fracStr += "0" // convert 2 digits to 3 digits ms
			}
			ms, err3 := strconv.ParseInt(fracStr, 10, 64)

			if err1 != nil || err2 != nil || err3 != nil {
				continue
			}

			totalMs := min*60*1000 + sec*1000 + ms
			lines = append(lines, LyricLine{
				TimeMs: totalMs,
				Text:   text,
			})
		}
	}

	// Sort lines by TimeMs
	for i := 0; i < len(lines)-1; i++ {
		for j := i + 1; j < len(lines); j++ {
			if lines[j].TimeMs < lines[i].TimeMs {
				lines[i], lines[j] = lines[j], lines[i]
			}
		}
	}

	log.Printf("[LyricsManager] Parsed %d lyric lines", len(lines))
	return lines
}

// GetCurrentLyric finds current lyric line given playback position in milliseconds
func (lm *LyricsManager) GetCurrentLyric(lines []LyricLine, positionMs int64) (current string, next string, index int, total int) {
	total = len(lines)
	if total == 0 {
		return "", "", -1, 0
	}

	bestIdx := -1
	for i, line := range lines {
		if line.TimeMs <= positionMs {
			bestIdx = i
		} else {
			break
		}
	}

	if bestIdx == -1 {
		// Before first line
		return "", lines[0].Text, -1, total
	}

	current = lines[bestIdx].Text
	index = bestIdx
	if bestIdx+1 < total {
		next = lines[bestIdx+1].Text
	}

	return current, next, index, total
}
