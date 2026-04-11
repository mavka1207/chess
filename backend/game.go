package main

import (
	"fmt"
	"log"
	"math/rand"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/notnil/chess"
)

// ── Types ─────────────────────────────────────────────────────────────────────

// Player represents a connected client — either in the lobby or inside a game room.
type Player struct {
	Conn      *websocket.Conn
	Color     string
	Name      string
	Avatar    string
	ID        string
	Searching bool // true = player is actively looking for a match in the lobby
}

// Room holds a single game session — either a 1v1 match or a bot practice game.
type Room struct {
	ID               string
	Game             *chess.Game
	Players          map[*websocket.Conn]*Player // Conn -> Player info
	writeMu          map[*websocket.Conn]*sync.Mutex // per-connection write lock to prevent interleaved messages
	mu               sync.Mutex
	started          bool
	IsBotGame        bool
	BotColor         string
	RematchRequested map[*websocket.Conn]bool
}

// ── Constructor ───────────────────────────────────────────────────────────────

// NewRoom creates a fresh room with an empty chess game.
func NewRoom(id string, isBot bool) *Room {
	return &Room{
		ID:               id,
		Game:             chess.NewGame(),
		Players:          make(map[*websocket.Conn]*Player),
		writeMu:          make(map[*websocket.Conn]*sync.Mutex),
		IsBotGame:        isBot,
		started:          false,
		RematchRequested: make(map[*websocket.Conn]bool),
	}
}

// ── Join ──────────────────────────────────────────────────────────────────────

// Join registers a new player connection, assigns a color, and starts the game
// once both players (or one player in a bot game) have connected.
func (r *Room) Join(conn *websocket.Conn, requestedColor, name, avatar, id string) {
	r.mu.Lock()

	// ── Color Assignment ──────────────────────────────────────────────────────

	color := ""

	// Honor the requested color if it is not already taken
	if requestedColor == "white" || requestedColor == "black" {
		taken := false
		for _, p := range r.Players {
			if p.Color == requestedColor {
				taken = true
				break
			}
		}
		if !taken {
			color = requestedColor
		}
	}

	// Fall back: first player gets white, second gets the remaining color
	if color == "" {
		if len(r.Players) == 0 {
			color = "white"
		} else {
			for _, p := range r.Players {
				if p.Color == "white" {
					color = "black"
				} else {
					color = "white"
				}
				break 
			}
		}
	}

	r.Players[conn] = &Player{
		Conn:   conn,
		Color:  color,
		Name:   name,
		Avatar: avatar,
		ID:     id,
	}
	r.writeMu[conn] = &sync.Mutex{} 
	log.Printf("[ROOM] %s joined room %s as %s", name, r.ID, color)

	// Start when both human players are present, or one player in a bot game
	shouldStart := len(r.Players) == 2 || (r.IsBotGame && len(r.Players) == 1)

	// Mark as started inside the lock — modifies shared state
	if shouldStart {
		r.started = true   
	}	
	
	go r.handlePlayer(conn)

	r.mu.Unlock()

	// Network calls go outside the lock to avoid holding it during I/O
	if shouldStart {
		r.broadcastColors()  
		r.broadcastBoard("")
		r.notifyTurn()
	}
}

// ── Messaging ─────────────────────────────────────────────────────────────────

// sendMessage sends a text message to a single connection, using a per-connection
// mutex to prevent concurrent writes from corrupting the WebSocket frame.
func (r *Room) sendMessage(conn *websocket.Conn, msg string) {
    r.mu.Lock()
    mu, ok := r.writeMu[conn]
    r.mu.Unlock()
    if !ok {
        return
    }
    mu.Lock()
    defer mu.Unlock()
    conn.WriteMessage(websocket.TextMessage, []byte(msg))
}

// Broadcast sends a message to every player in the room.
func (r *Room) Broadcast(msg string) {
	r.mu.Lock()
	conns := make([]*websocket.Conn, 0, len(r.Players))
	for conn := range r.Players {
        conns = append(conns, conn)
    }
    r.mu.Unlock()

	for _, conn := range conns {
		r.sendMessage(conn, msg)
	}
}

// broadcastToOthers sends a message to every player except the excluded connection.
func (r *Room) broadcastToOthers(exclude *websocket.Conn, msg string) {
	r.mu.Lock()
	var targets []*websocket.Conn
	for conn := range r.Players {
		if conn != exclude {
			targets = append(targets, conn)
		}
	}
	r.mu.Unlock()

	for _, conn := range targets {
		r.sendMessage(conn, msg)
	}
}

// ── Board State ───────────────────────────────────────────────────────────────

// broadcastColors sends each player their assigned color and the full player
// roster so clients can display opponent info.
func (r *Room) broadcastColors() {
	for conn, p := range r.Players {
		// Tell this player their own color
		r.sendMessage(conn, p.Color)
		
		// Send profile info for every player in the room (including themselves)
		for _, other := range r.Players {
			infoMsg := fmt.Sprintf("PLAYER_INFO:%s:%s:%s:%s", 
				other.Color, other.Name, other.Avatar, other.ID)
			r.sendMessage(conn, infoMsg)
		}
	}
}

// broadcastBoard sends the current FEN position and full move history to all players.
// lastMove is the UCI string of the move that was just played e.g. "e2e4"; pass "" on reset.
func (r *Room) broadcastBoard(lastMove string) {
	fen := r.Game.Position().String()
	msg := "BOARD:" + fen
	if lastMove != "" {
		msg += ":" + lastMove
	}

	// Build algebraic move history string e.g. "1. e4 e5 2. Nf3 Nc6 "
	moves := r.Game.Moves()
	history := ""
	for i := 0; i < len(moves); i++ {
		if i%2 == 0 {
			history += fmt.Sprintf("%d. ", (i/2)+1)
		}
		history += chess.AlgebraicNotation{}.Encode(r.Game.Positions()[i], moves[i]) + " "
	}

    r.mu.Lock()
    var conns []*websocket.Conn
    for c := range r.Players {
        conns = append(conns, c)
    }
    r.mu.Unlock()

	for _, conn := range conns {
		r.sendMessage(conn, msg)
		if history != "" {
			r.sendMessage(conn, "MOVES:"+history)
		}
	}
}

// notifyTurn tells all players whose turn it is, and triggers the bot if needed.
func (r *Room) notifyTurn() {
	turn := "white"
	if r.Game.Position().Turn() == chess.Black {
		turn = "black"
	}

    r.mu.Lock()
    var conns []*websocket.Conn
    for c := range r.Players {
        conns = append(conns, c)
    }
    r.mu.Unlock()

	for _, conn := range conns {
		r.sendMessage(conn, "TURN:"+turn)
	}

	// Trigger bot move if it is the bot's turn and the game is still in progress
	if r.IsBotGame && turn == r.BotColor && r.Game.Outcome() == chess.NoOutcome {
		go r.makeBotMove()
	}
}

// finalizeMove broadcasts the updated board and either the game-over result
// or the next turn notification.
func (r *Room) finalizeMove(moveStr string, gameOver bool) {
	// Move successful, broadcast new state
	r.broadcastBoard(moveStr)

	// Check if game ended
	if gameOver {
		r.broadcastGameOver()
	} else {
		// Notify whose turn it is
		r.notifyTurn()
	}
}

// ── Player Handler ────────────────────────────────────────────────────────────

// handlePlayer runs in a goroutine for each connected player.
// It reads incoming messages until the connection closes, then cleans up.
func (r *Room) handlePlayer(conn *websocket.Conn) {
	defer func() {
		r.mu.Lock()
		player := r.Players[conn]
		color := ""
		name := ""
		if player != nil {
			color = player.Color
			name = player.Name
		}
		log.Printf("[DEBUG] defer: conn color = '%s', players = %v", color, r.Players)
		delete(r.Players, conn)
		delete(r.writeMu, conn) 
		remaining := len(r.Players)
		r.mu.Unlock()
		log.Printf("[DEBUG] IsBotGame = %v, remaining = %d", r.IsBotGame, remaining)
		
		conn.Close()
		log.Printf("[-] DISCONNECTED: %s (%s) left room %s. (Remaining: %d)", name, color, r.ID, remaining)

		// Notify the remaining player that their opponent disconnected
		if !r.IsBotGame && remaining == 1 {		
			r.Broadcast("OPPONENT_LEFT")
		}
	}()

	for {
		_, msg, err := conn.ReadMessage()
		if err != nil {
			return
		}

        msgStr := string(msg)

		// Allow management commands before the game starts; drop regular moves
        isMgmt := strings.Contains(msgStr, "RESTART") || 
				strings.Contains(msgStr, "REMATCH") || 
				strings.Contains(msgStr, "RESIGN")

		if !r.started && !isMgmt {
			continue
		}

		r.processMove(conn, string(msg))
	}
}

// ── Move Processing ───────────────────────────────────────────────────────────

// processMove routes a raw message to the correct handler —
// management commands (RESTART, REMATCH, RESIGN) or a regular chess move.
func (r *Room) processMove(conn *websocket.Conn, message string) {
	moveStr := strings.TrimPrefix(message, "MOVE:")

	// ── RESTART ───────────────────────────────────────────────────────────────
	if moveStr == "RESTART" {
		r.mu.Lock()
		player := r.Players[conn]
		color := "unknown"
		if player != nil {
			color = player.Color
		}
		log.Printf("[RESTART] Immediate restart triggered by %s in room %s", color, r.ID)
		r.mu.Unlock()

		r.Restart()
		return
	}

	// ── REMATCH ───────────────────────────────────────────────────────────────
	if moveStr == "REMATCH" {
		r.mu.Lock()
		player := r.Players[conn]
		color := "unknown"
		if player != nil {
			color = player.Color
		}
		log.Printf("[REMATCH] Request from %s in room %s", color, r.ID)
		
		r.RematchRequested[conn] = true
		numRequested := len(r.RematchRequested)
		numPlayers := len(r.Players)
		isBot := r.IsBotGame
		r.mu.Unlock()

		if isBot || numPlayers <= 1 || numRequested >= 2 {
			r.Restart()
		} else {
			// Bot game or both players agreed — restart immediately
			r.broadcastToOthers(conn, "REMATCH_REQUESTED")
			// Waiting for the other player — notify both sides
			r.sendMessage(conn, "REMATCH_SENT")
		}
		return
	}
	
	// ── RESIGN ────────────────────────────────────────────────────────────────
	if moveStr == "RESIGN" {
		r.mu.Lock()
		player := r.Players[conn]
		if player == nil {
			r.mu.Unlock()
			return
		}
		
		// The resigning player loses — flip the score accordingly
		score := "1-0"
		outcome := "WhiteWon"
		if player.Color == "white" {
			score = "0-1"
			outcome = "BlackWon"
		}
		r.mu.Unlock()
		
		msg := fmt.Sprintf("GAMEOVER:%s (%s) by Resignation", outcome, score)
		r.Broadcast(msg)
		return
	}

	// ── Chess Move ────────────────────────────────────────────────────────────

	r.mu.Lock()
    log.Printf("[MOVE] Processing move: %s | Turn: %s | MyColor: %s", 
		moveStr, r.Game.Position().Turn(), r.Players[conn].Color)

	player := r.Players[conn]
	if player == nil {
        log.Printf("[MOVE] Error: Player not found for connection")
		r.mu.Unlock()
		return
	}

	// Reject move if it is not this player's turn
	color := player.Color
	if (color == "white" && r.Game.Position().Turn() != chess.White) ||
		(color == "black" && r.Game.Position().Turn() != chess.Black) {
		r.mu.Unlock() 
		r.sendMessage(conn, "ERROR:Not your turn")
        log.Printf("[MOVE] Wrong turn (Color: %s, Turn: %s)", color, r.Game.Position().Turn())
		return
	}

	// Decode UCI notation e.g. "e2e4" or "e7e8q" for promotion
	move, err := chess.UCINotation{}.Decode(r.Game.Position(), moveStr)
	if err != nil {
		r.mu.Unlock()
		r.sendMessage(conn, "ERROR:Invalid move: "+err.Error())
        log.Printf("[MOVE] UCI Decode Failed: %v (msg: %s)", err, moveStr)
		return
	}

	err = r.Game.Move(move)
	if err != nil {
		r.mu.Unlock()
		r.sendMessage(conn, "ERROR:Move execution failed: "+err.Error())
        log.Printf("[MOVE] Execution Failed: %v", err)
		return
	}

    log.Printf("[MOVE] Move successful: %s", moveStr)
	gameOver := r.Game.Outcome() != chess.NoOutcome
    r.mu.Unlock()

	r.finalizeMove(moveStr, gameOver)
}

// ── Bot ───────────────────────────────────────────────────────────────────────

// makeBotMove waits briefly for realism, then picks and applies a random valid move.
func (r *Room) makeBotMove() {
	time.Sleep(1500 * time.Millisecond)

	r.mu.Lock()
	moves := r.Game.ValidMoves()
	if len(moves) == 0 {
		r.mu.Unlock()
		return
	}

	// Pick a random legal move
	move := moves[rand.Intn(len(moves))]
	moveStr := move.String()
	r.mu.Unlock()

	r.applyBotMove(moveStr)
}

// applyBotMove applies the bot's chosen move directly, bypassing the turn check.
func (r *Room) applyBotMove(moveStr string) {
	r.mu.Lock()
	move, _ := chess.UCINotation{}.Decode(r.Game.Position(), moveStr)
	r.Game.Move(move)
	gameOver := r.Game.Outcome() != chess.NoOutcome
	r.mu.Unlock()

	r.finalizeMove(moveStr, gameOver)
}

// ── Game Over ─────────────────────────────────────────────────────────────────

// broadcastGameOver sends the final result to all players and logs the game.
func (r *Room) broadcastGameOver() {
	outcome := r.Game.Outcome()
	method := r.Game.Method()
	msg := fmt.Sprintf("GAMEOVER:%s by %s", outcome, method)
	r.Broadcast(msg)

	r.logGame()
}

// logGame appends a one-line game record to games.log for persistence.
// In a production app this would write to a database instead.
func (r *Room) logGame() {
	log.Printf("[LOG] Game %s: %s by %s", r.ID, r.Game.Outcome(), r.Game.Method())

	f, err := os.OpenFile("games.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		log.Println("[LOG] Error opening log file:", err)
		return
	}
	defer f.Close()

	entry := fmt.Sprintf("ID: %s | Outcome: %s | Method: %s | FEN: %s\n", 
		r.ID, r.Game.Outcome(), r.Game.Method(), r.Game.Position().String())

	if _, err := f.WriteString(entry); err != nil {
		log.Println("[LOG] Error writing to log file:", err)
	}
}

// ── Restart ───────────────────────────────────────────────────────────────────

// Restart resets the game state and notifies all players to clear their boards.
func (r *Room) Restart() {
	r.mu.Lock()
	r.Game = chess.NewGame()
	r.RematchRequested = make(map[*websocket.Conn]bool)
	r.mu.Unlock()

	log.Printf("[RESTART] Room %s restarted", r.ID)

	r.broadcastBoard("") // Empty lastMove resets the last-move highlight on clients
	r.notifyTurn()

	// Notify clients that game was reset
	r.Broadcast("RESTARTED")
}
