package main

import (
	"fmt"
	// "image/color"
	"log"
	"math/rand"
	"os"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/notnil/chess"
)

type Room struct {
	ID        string
	Game      *chess.Game
	Players   map[*websocket.Conn]string // Conn -> Color (white or black)
	writeMu   map[*websocket.Conn]*sync.Mutex // To serialize writes per connection
	mu        sync.Mutex
	started   bool
	IsBotGame bool
	BotColor  string
}

func NewRoom(id string) *Room {
	return &Room{
		ID:      id,
		Game:    chess.NewGame(),
		Players: make(map[*websocket.Conn]string),
		writeMu: make(map[*websocket.Conn]*sync.Mutex),
	}
}

func (r *Room) Join(conn *websocket.Conn, requestedColor string) {
	r.mu.Lock()

	// Determine color
	color := ""
	if requestedColor == "white" || requestedColor == "black" {
		// Check if requested color is already taken
		taken := false
		for _, c := range r.Players {
			if c == requestedColor {
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
		} else if len(r.Players) == 1 {
			// Take what's left
			for _, takenColor := range r.Players {
				if takenColor == "white" {
					color = "black"
				} else {
					color = "white"
				}
			}
		} else {
			conn.WriteMessage(websocket.TextMessage, []byte("Room full"))
			conn.Close()
			return
		}
	}

	r.Players[conn] = color
	r.writeMu[conn] = &sync.Mutex{} 
	log.Printf("Player joined room %s as %s", r.ID, color)


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

func (r *Room) broadcastColors() {
	for conn, color := range r.Players {
		r.sendMessage(conn, color)
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
		// Use SAN notation for history
		history += chess.AlgebraicNotation{}.Encode(r.Game.Positions()[i], moves[i]) + " "
	}

	for conn := range r.Players {
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
		color := r.Players[conn]
		log.Printf("[DEBUG] defer: conn color = '%s', players = %v", color, r.Players)
		delete(r.Players, conn)
		delete(r.writeMu, conn) 
		remaining := len(r.Players)
		r.mu.Unlock()
		log.Printf("[DEBUG] IsBotGame = %v, remaining = %d", r.IsBotGame, remaining)
		
		conn.Close()
		log.Printf("[-] DISCONNECTED: %s left room %s. (Remaining: %d)", color, r.ID, remaining)

		// Notify remaining player if this was a multiplayer game
		if !r.IsBotGame && remaining == 1 {				// Game never started
			r.Broadcast("OPPONENT_LEFT")
			
		}
		// if !r.IsBotGame && remaining == 1 {
		// 	log.Printf("[DEBUG] Broadcasting OPPONENT_LEFT, remaining: %d", remaining)
		// 	r.Broadcast("OPPONENT_LEFT")

		// 	log.Printf("[DEBUG] r.started = %v", started)
		// 	// Only declare winner if game had actually started
		// 	if r.started {
		// 		winResult := "1-0 by resignation"
		// 		if color == "white" {
		// 			winResult = "0-1 by resignation"
		// 		}
		// 		r.Broadcast(fmt.Sprintf("GAMEOVER:%s", winResult))
		// 	}
		// }
	}()

	for {
		_, msg, err := conn.ReadMessage()
		if err != nil {
			return
		}

		// Only process moves if the game has started
		if !r.started && string(msg) != "RESTART" {
			continue
		}

		r.processMove(conn, string(msg))
	}
}

func (r *Room) processMove(conn *websocket.Conn, moveStr string) {
	if moveStr == "RESTART" {
		r.Restart()
		return
	}

	r.mu.Lock()

	color := r.Players[conn]
	if (color == "white" && r.Game.Position().Turn() != chess.White) ||
		(color == "black" && r.Game.Position().Turn() != chess.Black) {
		r.mu.Unlock() // Unlock before sending message to avoid deadlock
		r.sendMessage(conn, "ERROR:Not your turn")
		return
	}

	// Expecting move in UCI notation (e.g. e2e4)
	move, err := chess.UCINotation{}.Decode(r.Game.Position(), moveStr)
	if err != nil {
		r.mu.Unlock()
		r.sendMessage(conn, "ERROR:Invalid move: "+err.Error())
		return
	}

	err = r.Game.Move(move)
	if err != nil {
		r.mu.Unlock()
		r.sendMessage(conn, "ERROR:Move execution failed: "+err.Error())
		return
	}

	gameOver := r.Game.Outcome() != chess.NoOutcome
    r.mu.Unlock()  // ← unlock before broadcasting

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
	for conn := range r.Players {
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
	r.mu.Unlock()

	log.Printf("Game restarted in room %s", r.ID)
	r.broadcastBoard("") // Reset board (no last move)
	r.notifyTurn()

	// Notify clients that game was reset
	r.Broadcast("RESTARTED")
}
