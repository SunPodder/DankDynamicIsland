package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
)

// ClientHandler callback for actions requested by clients
type ClientActionHandler func(msg ClientMessage)

// Server manages WebSocket and Unix Domain Socket multi-client connections
type Server struct {
	mu           sync.RWMutex
	wsClients    map[*websocket.Conn]struct{}
	unixClients  map[net.Conn]struct{}
	onAction     ClientActionHandler
	onClientJoin func()
	wsPort       int
	socketPath   string
	unixListener net.Listener
	httpServer   *http.Server
}

// NewServer initializes Server
func NewServer(wsPort int, onAction ClientActionHandler, onClientJoin func()) *Server {
	runtimeDir := os.Getenv("XDG_RUNTIME_DIR")
	if runtimeDir == "" {
		runtimeDir = "/tmp"
	}
	sockPath := filepath.Join(runtimeDir, fmt.Sprintf("dank-dynamic-island-%d.sock", os.Getuid()))

	return &Server{
		wsClients:    make(map[*websocket.Conn]struct{}),
		unixClients:  make(map[net.Conn]struct{}),
		onAction:     onAction,
		onClientJoin: onClientJoin,
		wsPort:       wsPort,
		socketPath:   sockPath,
	}
}

// Start launches both WebSocket and Unix Socket listeners
func (s *Server) Start() error {
	// 1. Start Unix Domain Socket
	_ = os.Remove(s.socketPath)
	ul, err := net.Listen("unix", s.socketPath)
	if err != nil {
		log.Printf("[Server] Unix socket listen error: %v", err)
	} else {
		s.unixListener = ul
		_ = os.Chmod(s.socketPath, 0600)
		log.Printf("[Server] Listening on Unix socket: %s", s.socketPath)
		go s.acceptUnix()
	}

	// 2. Start WebSocket HTTP Server
	mux := http.NewServeMux()
	mux.HandleFunc("/ws", s.handleWebSocket)
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	s.httpServer = &http.Server{
		Addr:    fmt.Sprintf("127.0.0.1:%d", s.wsPort),
		Handler: mux,
	}

	go func() {
		log.Printf("[Server] WebSocket server listening on ws://127.0.0.1:%d/ws", s.wsPort)
		if err := s.httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Printf("[Server] HTTP server error: %v", err)
		}
	}()

	return nil
}

// Stop cleans up listeners and disconnects clients
func (s *Server) Stop() {
	if s.httpServer != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		_ = s.httpServer.Shutdown(ctx)
	}

	if s.unixListener != nil {
		_ = s.unixListener.Close()
		_ = os.Remove(s.socketPath)
	}

	s.mu.Lock()
	for c := range s.wsClients {
		_ = c.Close(websocket.StatusNormalClosure, "server shutting down")
	}
	for c := range s.unixClients {
		_ = c.Close()
	}
	s.wsClients = make(map[*websocket.Conn]struct{})
	s.unixClients = make(map[net.Conn]struct{})
	s.mu.Unlock()
}

func (s *Server) handleWebSocket(w http.ResponseWriter, r *http.Request) {
	opts := &websocket.AcceptOptions{
		InsecureSkipVerify: true, // Allow local connections from QML / web
	}
	conn, err := websocket.Accept(w, r, opts)
	if err != nil {
		log.Printf("[Server] WebSocket accept error: %v", err)
		return
	}
	defer conn.Close(websocket.StatusInternalError, "closing")

	s.mu.Lock()
	s.wsClients[conn] = struct{}{}
	s.mu.Unlock()

	log.Printf("[Server] New WebSocket client connected (%d active)", s.clientCount())

	if s.onClientJoin != nil {
		s.onClientJoin()
	}

	for {
		var msg ClientMessage
		err := wsjson.Read(r.Context(), conn, &msg)
		if err != nil {
			break
		}
		if s.onAction != nil {
			s.onAction(msg)
		}
	}

	s.mu.Lock()
	delete(s.wsClients, conn)
	s.mu.Unlock()
	log.Printf("[Server] WebSocket client disconnected (%d remaining)", s.clientCount())
}

func (s *Server) acceptUnix() {
	for {
		conn, err := s.unixListener.Accept()
		if err != nil {
			return
		}

		s.mu.Lock()
		s.unixClients[conn] = struct{}{}
		s.mu.Unlock()

		log.Printf("[Server] New Unix socket client connected (%d active)", s.clientCount())

		if s.onClientJoin != nil {
			s.onClientJoin()
		}

		go s.handleUnixClient(conn)
	}
}

func (s *Server) handleUnixClient(conn net.Conn) {
	defer func() {
		_ = conn.Close()
		s.mu.Lock()
		delete(s.unixClients, conn)
		s.mu.Unlock()
		log.Printf("[Server] Unix socket client disconnected (%d remaining)", s.clientCount())
	}()

	scanner := bufio.NewScanner(conn)
	for scanner.Scan() {
		line := scanner.Bytes()
		if len(line) == 0 {
			continue
		}
		var msg ClientMessage
		if err := json.Unmarshal(line, &msg); err == nil {
			if s.onAction != nil {
				s.onAction(msg)
			}
		}
	}
}

func (s *Server) clientCount() int {
	return len(s.wsClients) + len(s.unixClients)
}

// BroadcastState sends updated state to all connected WebSocket and Unix socket clients
func (s *Server) BroadcastState(state MediaState) {
	s.mu.RLock()
	if len(s.wsClients) == 0 && len(s.unixClients) == 0 {
		s.mu.RUnlock()
		return
	}

	data, err := json.Marshal(state)
	if err != nil {
		s.mu.RUnlock()
		return
	}

	wsList := make([]*websocket.Conn, 0, len(s.wsClients))
	for c := range s.wsClients {
		wsList = append(wsList, c)
	}

	unixList := make([]net.Conn, 0, len(s.unixClients))
	for c := range s.unixClients {
		unixList = append(unixList, c)
	}
	s.mu.RUnlock()

	// Broadcast to WebSockets
	for _, c := range wsList {
		go func(conn *websocket.Conn) {
			writeCtx, writeCancel := context.WithTimeout(context.Background(), 2*time.Second)
			defer writeCancel()
			_ = wsjson.Write(writeCtx, conn, state)
		}(c)
	}

	// Broadcast to Unix sockets (newline-delimited JSON)
	line := append(data, '\n')
	for _, c := range unixList {
		go func(conn net.Conn) {
			_ = conn.SetWriteDeadline(time.Now().Add(2 * time.Second))
			_, _ = conn.Write(line)
		}(c)
	}
}
