package main

import (
	"fmt"
	// "image/color"
	"log"
	"math/rand"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/notnil/chess"
)

type Player struct {
	Conn      *websocket.Conn
	Color     string
	Name      string
	Avatar    string
	ID        string
	Searching bool // Whether the player is explicitly looking for a match
}

type Room struct {
	ID               string
	Game             *chess.Game
	Players          map[*websocket.Conn]*Player // Conn -> Player info
	writeMu          map[*websocket.Conn]*sync.Mutex // To serialize writes per connection
	mu               sync.Mutex
	started          bool
	IsBotGame        bool
	BotColor         string
	RematchRequested map[*websocket.Conn]bool
}

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

func (r *Room) Join(conn *websocket.Conn, requestedColor, name, avatar, id string) {
	r.mu.Lock()

	// Determine color
	color := ""
	if requestedColor == "white" || requestedColor == "black" {
		// Check if requested color is already taken
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

	if color == "" {
		if len(r.Players) == 0 {
			color = "white"
		} else {
			// Second player: MUST take the other color
			for _, p := range r.Players {
				if p.Color == "white" {
					color = "black"
				} else {
					color = "white"
				}
				break // only one existing player
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
	log.Printf("Player %s joined room %s as %s", name, r.ID, color)


	shouldStart := len(r.Players) == 2 || (r.IsBotGame && len(r.Players) == 1)

	// First shouldStart — inside the lock
	if shouldStart {
		r.started = true   // ← modifies shared state → must be inside lock
	}	
	
	go r.handlePlayer(conn)

	r.mu.Unlock()

	// Second shouldStart — outside the lock
	if shouldStart {
		r.broadcastColors()  // ← network calls → must be outside lock
		r.broadcastBoard("")
		r.notifyTurn()
	}
}

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

// Internal version that assumes room lock IS NOT held, but handles its own connection-level locking
func (r *Room) broadcastSafe(msg string) {
	r.mu.Lock()
	var conns []*websocket.Conn
	for conn := range r.Players {
		conns = append(conns, conn)
	}
	r.mu.Unlock()

	for _, conn := range conns {
		r.sendMessage(conn, msg)
	}
}

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

func (r *Room) broadcastColors() {
	for conn, p := range r.Players {
		// Send own color
		r.sendMessage(conn, p.Color)
		
		// Send profile info of everyone in the room
		for _, other := range r.Players {
			infoMsg := fmt.Sprintf("PLAYER_INFO:%s:%s:%s:%s", other.Color, other.Name, other.Avatar, other.ID)
			r.sendMessage(conn, infoMsg)
		}
	}
}

func (r *Room) broadcastBoard(lastMove string) {
	fen := r.Game.Position().String()
	msg := "BOARD:" + fen
	if lastMove != "" {
		msg += ":" + lastMove
	}

	// Format move history
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

		// Notify remaining player if this was a multiplayer game
		if !r.IsBotGame && remaining == 1 {				// Game never started
			r.Broadcast("OPPONENT_LEFT")
		}
	}()

	for {
		_, msg, err := conn.ReadMessage()
		if err != nil {
			return
		}

		// Only process moves if the game has started or it's a management command
        msgStr := string(msg)
        isMgmt := strings.Contains(msgStr, "RESTART") || 
                  strings.Contains(msgStr, "REMATCH") || 
                  strings.Contains(msgStr, "RESIGN")

		if !r.started && !isMgmt {
			continue
		}

		r.processMove(conn, string(msg))
	}
}

func (r *Room) processMove(conn *websocket.Conn, message string) {
	moveStr := strings.TrimPrefix(message, "MOVE:")

	if moveStr == "RESTART" || moveStr == "REMATCH" {
		r.mu.Lock()
		player := r.Players[conn]
		color := "unknown"
		if player != nil {
			color = player.Color
		}
		log.Printf("[REMATCH] Immediate restart triggered by %s in room %s", color, r.ID)
		r.mu.Unlock()

		r.Restart()
		return
	}

	if moveStr == "RESIGN" {
		r.mu.Lock()
		player := r.Players[conn]
		if player == nil {
			r.mu.Unlock()
			return
		}
		
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

	r.mu.Lock()
    log.Printf("[SERVER] Processing move: %s (Turn: %s, MyColor: %s)", moveStr, r.Game.Position().Turn(), r.Players[conn].Color)

	player := r.Players[conn]
	if player == nil {
        log.Printf("[SERVER] Error: Player not found for connection")
		r.mu.Unlock()
		return
	}
	color := player.Color
	if (color == "white" && r.Game.Position().Turn() != chess.White) ||
		(color == "black" && r.Game.Position().Turn() != chess.Black) {
		r.mu.Unlock() 
		r.sendMessage(conn, "ERROR:Not your turn")
        log.Printf("[SERVER] Error: Not your turn (Color: %s, Turn: %s)", color, r.Game.Position().Turn())
		return
	}

	// Expecting move in UCI notation (e.g. e2e4)
	move, err := chess.UCINotation{}.Decode(r.Game.Position(), moveStr)
	if err != nil {
		r.mu.Unlock()
		r.sendMessage(conn, "ERROR:Invalid move: "+err.Error())
        log.Printf("[SERVER] Error: UCI Decode Failed: %v (msg: %s)", err, moveStr)
		return
	}

	err = r.Game.Move(move)
	if err != nil {
		r.mu.Unlock()
		r.sendMessage(conn, "ERROR:Move execution failed: "+err.Error())
        log.Printf("[SERVER] Error: Move Execution Failed: %v", err)
		return
	}

    log.Printf("[SERVER] Move successful: %s", moveStr)
	gameOver := r.Game.Outcome() != chess.NoOutcome
    r.mu.Unlock()

	// Move successful, broadcast new state
	r.broadcastBoard(moveStr)

	// Check if game ended
	if gameOver{
		r.broadcastGameOver()
	} else {
		// Notify whose turn it is
		r.notifyTurn()
	}
}

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

	// If it's the bot's turn, trigger it
	if r.IsBotGame && turn == r.BotColor && r.Game.Outcome() == chess.NoOutcome {
		go r.makeBotMove()
	}
}

func (r *Room) makeBotMove() {
	// Add a delay for realism
	time.Sleep(1500 * time.Millisecond)

	r.mu.Lock()
	moves := r.Game.ValidMoves()
	if len(moves) == 0 {
		r.mu.Unlock()
		return
	}

	// Pick a random move
	move := moves[rand.Intn(len(moves))]
	moveStr := move.String()
	r.mu.Unlock()

	// We call processMove but we need a way to pass "nil" connection or bypass the check
	r.applyBotMove(moveStr)
}

func (r *Room) applyBotMove(moveStr string) {
	r.mu.Lock()
	move, _ := chess.UCINotation{}.Decode(r.Game.Position(), moveStr)
	r.Game.Move(move)
	gameOver := r.Game.Outcome() != chess.NoOutcome
    r.mu.Unlock()  
	// Move successful, broadcast new state
	r.broadcastBoard(moveStr)

	// Check if game ended
	if gameOver {
		r.broadcastGameOver()
	} else {
		r.notifyTurn()
	}
}

func (r *Room) broadcastGameOver() {
	outcome := r.Game.Outcome()
	method := r.Game.Method()
	msg := fmt.Sprintf("GAMEOVER:%s by %s", outcome, method)
	r.Broadcast(msg)

	// Log game for persistence
	r.logGame()
}

func (r *Room) logGame() {
	log.Printf("Saving game %s: %s by %s", r.ID, r.Game.Outcome(), r.Game.Method())
	// In a real app, this would go to a DB. For now, we use a log file.
	f, err := os.OpenFile("games.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		log.Println("Error opening log file:", err)
		return
	}
	defer f.Close()

	entry := fmt.Sprintf("ID: %s | Outcome: %s | Method: %s | FEN: %s\n", 
		r.ID, r.Game.Outcome(), r.Game.Method(), r.Game.Position().String())
	if _, err := f.WriteString(entry); err != nil {
		log.Println("Error writing to log file:", err)
	}
}

func (r *Room) Restart() {
	r.mu.Lock()
	r.Game = chess.NewGame()
	r.RematchRequested = make(map[*websocket.Conn]bool)
	r.mu.Unlock()

	log.Printf("Game restarted in room %s", r.ID)
	r.broadcastBoard("") // Reset board (no last move)
	r.notifyTurn()

	// Notify clients that game was reset
	r.Broadcast("RESTARTED")
}
