package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
)

// ── Types ─────────────────────────────────────────────────────────────────────

// GameManager holds all active rooms and lobby players.
// All map access must go through the mutex.
type GameManager struct {
	rooms       map[string]*Room
	waitingRoom map[*websocket.Conn]*Player // Conn -> Player info in lobby
	mu          sync.Mutex
}

// playerInfo is used exclusively for JSON serialization in broadcastOnlinePlayers.
type PlayerInfo struct {
		Name   string `json:"name"`
		Avatar string `json:"avatar"`
		ID     string `json:"id"`
		Search bool   `json:"search"` // true = in matchmaking queue; clients use this to show availability
}

// ── Constructor ───────────────────────────────────────────────────────────────

// NewGameManager initializes the manager and starts the matchmaking loop.
func NewGameManager() *GameManager {
	gm := &GameManager{
		rooms:       make(map[string]*Room),
		waitingRoom: make(map[*websocket.Conn]*Player),
	}
	go gm.matchmaking()
	return gm
}

// ── Matchmaking ───────────────────────────────────────────────────────────────

// matchmaking runs in the background, pairing two searching players every 2s.
func (gm *GameManager) matchmaking() {
	for {
		time.Sleep(2 * time.Second)

		// Collect players who are actively searching for a match
		var candidates []*Player
		gm.mu.Lock()
		for _, p := range gm.waitingRoom {
			if p.Searching {
				candidates = append(candidates, p)
			}
		}

		if len(candidates) < 2 {
			gm.mu.Unlock()
			continue
		}

		// Pick first two
		p1 := candidates[0]
		p2 := candidates[1]
		c1, c2 := p1.Conn, p2.Conn

		// Ping both players to confirm they are still connected
		if err := c1.WriteControl(websocket.PingMessage, []byte{}, time.Now().Add(time.Second)); err != nil {
			delete(gm.waitingRoom, c1)
			c1.Close()
			gm.mu.Unlock()
			continue
		}
		if err := c2.WriteControl(websocket.PingMessage, []byte{}, time.Now().Add(time.Second)); err != nil {
			delete(gm.waitingRoom, c2)
			c2.Close()
			gm.mu.Unlock()
			continue
		}

		// Remove both from the queue before releasing the lock 
		p1.Searching = false
		p2.Searching = false
		gm.mu.Unlock()

		// Notify remaining lobby players that these two are no longer available
		gm.broadcastOnlinePlayers() 

		// Create the matched room and notify both players
		roomID := strings.ToUpper(uuid.New().String()[:6])
		room := NewRoom(roomID, false)

		gm.mu.Lock()
		gm.rooms[roomID] = room
		gm.mu.Unlock()

		log.Printf("Match found! %s vs %s in room %s\n", p1.Name, p2.Name, roomID)

		c1.WriteMessage(websocket.TextMessage, []byte("JOIN:"+roomID+":white"))
		c2.WriteMessage(websocket.TextMessage, []byte("JOIN:"+roomID+":black"))
	}
}

// ── Lobby Broadcast ───────────────────────────────────────────────────────────

// broadcastOnlinePlayers sends the current lobby player list to every connected client.
func (gm *GameManager) broadcastOnlinePlayers() {
	gm.mu.Lock()
	defer gm.mu.Unlock()

	var players []PlayerInfo
	for _, p := range gm.waitingRoom {
		players = append(players, PlayerInfo{
			Name:   p.Name,
			Avatar: p.Avatar,
			ID:     p.ID,
			Search: p.Searching,
		})
	}

	data, _ := json.Marshal(players)
	msg := "ONLINE_PLAYERS:" + string(data)

	for conn := range gm.waitingRoom {
		conn.WriteMessage(websocket.TextMessage, []byte(msg))
	}
}

// ── HTTP Handlers ─────────────────────────────────────────────────────────────

// HandleLobby upgrades the connection and registers the player in the waiting room
func (gm *GameManager) HandleLobby(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("[LOBBY] Upgrade error:", err)
		return
	}

	// Read player identity from query params
	name := r.URL.Query().Get("name")
	avatar := r.URL.Query().Get("avatar")
	playerID := r.URL.Query().Get("id")
	if name == "" {
		name = "Guest"
	}

	player := &Player{
		Conn:      conn,
		Name:      name,
		Avatar:    avatar,
		ID:        playerID,
		Searching: false, // Explicitly false on start
	}

	gm.mu.Lock()
	gm.waitingRoom[conn] = player
	gm.mu.Unlock()

	log.Printf("[LOBBY] Player %s (%s) connected. Searching: %v", name, playerID, player.Searching)
	gm.broadcastOnlinePlayers()

	// Clean up when the player disconnects
	defer func() {
		gm.mu.Lock()
		delete(gm.waitingRoom, conn)
		gm.mu.Unlock()
		conn.Close()
		log.Printf("[LOBBY] Player %s left lobby", name)
		gm.broadcastOnlinePlayers()
	}()

	// Read loop — process lobby commands until the connection closes
	for {
		_, msg, err := conn.ReadMessage()
		if err != nil {
			break
		}
		gm.handleLobbyMessage(player, string(msg))
	}
}

// HandleCreate creates a new private room and returns its ID as JSON.
func (gm *GameManager) HandleCreate(w http.ResponseWriter, r *http.Request) {
	roomID := strings.ToUpper(uuid.New().String()[:6]) // Short code for easier sharing
	room := NewRoom(roomID, false)

	gm.mu.Lock()
	gm.rooms[roomID] = room
	gm.mu.Unlock()

	log.Printf("[LOBBY] Private room created: %s", roomID)
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"roomID": "%s"}`, roomID)
}

// HandlePractice creates a bot room and returns its ID as JSON.
func (gm *GameManager) HandlePractice(w http.ResponseWriter, r *http.Request) {
	roomID := strings.ToUpper(uuid.New().String()[:6]) + "_BOT"
	room := NewRoom(roomID, true)
	room.BotColor = "black"

	gm.mu.Lock()
	gm.rooms[roomID] = room
	gm.mu.Unlock()

	log.Printf("[LOBBY] Practice room created: %s", roomID)
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"roomID": "%s"}`, roomID)
}

// HandleGame upgrades the connection and joins the player to an existing room.
func (gm *GameManager) HandleGame(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Path
	roomID := strings.ToUpper(strings.TrimPrefix(path, "/rooms/"))
	if roomID == "" {
		http.Error(w, "Room ID required", http.StatusBadRequest)
		return
	}

	// Read player identity from query params
	name := r.URL.Query().Get("name")
	avatar := r.URL.Query().Get("avatar")
	playerID := r.URL.Query().Get("id")
	requestedColor := r.URL.Query().Get("color")
	if name == "" {
		name = "Guest"
	}

	gm.mu.Lock()
	room, exists := gm.rooms[roomID]
	gm.mu.Unlock()

	if !exists {
		log.Printf("[ROOM] Join failed: Room %s not found", roomID)
		http.Error(w, "Room not found", http.StatusNotFound)
		return
	}

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("[GAME] Upgrade error:", err)
		return
	}

	room.Join(conn, requestedColor, name, avatar, playerID)
}

// ── Lobby Message Handler ─────────────────────────────────────────────────────

// handleLobbyMessage routes incoming lobby commands to the correct action.
func (gm *GameManager) handleLobbyMessage(sender *Player, msg string) {
	parts := strings.Split(msg, ":")
	if len(parts) < 1 {
		return
	}

	switch parts[0] {

	case "MATCHME":
		// Player entered the public matchmaking queue
		log.Printf("[LOBBY] %s joined matchmaking", sender.Name)
		sender.Searching = true
		gm.broadcastOnlinePlayers()

	case "CANCEL_MATCHME":
		// Player left the public matchmaking queue
		log.Printf("[LOBBY] %s left matchmaking", sender.Name)
		sender.Searching = false
		gm.broadcastOnlinePlayers()

	case "INVITE":
		// Player sent a private invite to another lobby player
		if len(parts) < 2 {
			return
		}
		gm.relayInvite(sender, parts[1])

	case "INVITE_RESPONSE":
		// Player accepted or declined an incoming invite
		if len(parts) < 3 {
			return
		}
		gm.handleInviteResponse(sender, parts[1], parts[2])
	}
}

// ── Invite Helpers ────────────────────────────────────────────────────────────

// relayInvite forwards a private game invite to the target player.
func (gm *GameManager) relayInvite(sender *Player, targetID string) {
	gm.mu.Lock()
	var target *Player
	for _, p := range gm.waitingRoom {
		if p.ID == targetID {
			target = p
			break
		}
	}
	gm.mu.Unlock()

	if target == nil {
		log.Printf("[LOBBY] Invite failed — target %s not found", targetID)
		return
	}

	log.Printf("[LOBBY] Invite: %s → %s", sender.Name, target.Name)
	msg := fmt.Sprintf("INVITE_FROM:%s:%s:%s", sender.ID, sender.Name, sender.Avatar)
	target.Conn.WriteMessage(websocket.TextMessage, []byte(msg))
}

// handleInviteResponse processes an accepted or declined invite.
// On acceptance, a new private room is created and both players are sent a JOIN message.
func (gm *GameManager) handleInviteResponse(sender *Player, challengerID string, response string) {
	gm.mu.Lock()
	var challenger *Player
	for _, p := range gm.waitingRoom {
		if p.ID == challengerID {
			challenger = p
			break
		}
	}
	gm.mu.Unlock()

	if challenger == nil {
		return
	}

	if response == "ACCEPTED" {
		roomID := strings.ToUpper(uuid.New().String()[:6]) + "_INV"
		room   := NewRoom(roomID, false)

		gm.mu.Lock()
		gm.rooms[roomID] = room
		sender.Searching     = false
		challenger.Searching = false
		gm.mu.Unlock()

		gm.broadcastOnlinePlayers()

		log.Printf("[LOBBY] Invite accepted — %s vs %s → room %s", challenger.Name, sender.Name, roomID)
		challenger.Conn.WriteMessage(websocket.TextMessage, []byte("JOIN:"+roomID+":white"))
		sender.Conn.WriteMessage(websocket.TextMessage, []byte("JOIN:"+roomID+":black"))

	} else {
		log.Printf("[LOBBY] Invite declined by %s", sender.Name)
		challenger.Conn.WriteMessage(websocket.TextMessage, []byte("INVITE_DECLINED:"+sender.Name))
	}
}

// handleLobbyMessage routes incoming lobby commands to the correct action.
// func (gm *GameManager) handleLobbyMessage(sender *Player, msg string) {
// 	parts := strings.Split(msg, ":")
// 	if len(parts) < 1 {
// 		return
// 	}

// 	command := parts[0]

// 	switch command {
// 	case "MATCHME":
// 		log.Printf("[LOBBY] Player %s joined matchmaking queue", sender.Name)
// 		sender.Searching = true
// 		gm.broadcastOnlinePlayers()

// 	case "CANCEL_MATCHME":
// 		log.Printf("[LOBBY] Player %s left matchmaking queue", sender.Name)
// 		sender.Searching = false
// 		gm.broadcastOnlinePlayers()

// 	case "INVITE":
// 		if len(parts) < 2 { return }
// 		targetID := parts[1]
// 		gm.mu.Lock()
// 		var targetPlayer *Player
// 		for _, p := range gm.waitingRoom {
// 			if p.ID == targetID {
// 				targetPlayer = p
// 				break
// 			}
// 		}
// 		gm.mu.Unlock()

// 		if targetPlayer != nil {
// 			log.Printf("[LOBBY] Relaying invite from %s (%s) to %s (%s)", sender.Name, sender.ID, targetPlayer.Name, targetPlayer.ID)
// 			inviteMsg := fmt.Sprintf("INVITE_FROM:%s:%s:%s", sender.ID, sender.Name, sender.Avatar)
// 			targetPlayer.Conn.WriteMessage(websocket.TextMessage, []byte(inviteMsg))
// 		} else {
//             log.Printf("[LOBBY] Target player %s NOT FOUND. Online IDs:", targetID)
//             for _, p := range gm.waitingRoom {
//                 log.Printf(" - %s (%s)", p.Name, p.ID)
//             }
//         }

// 	case "INVITE_RESPONSE":
// 		if len(parts) < 3 {
// 			return
// 		}
// 		challengerID := parts[1]
// 		response := parts[2] // "ACCEPTED" or "DECLINED"

// 		gm.mu.Lock()
// 		var challenger *Player
// 		for _, p := range gm.waitingRoom {
// 			if p.ID == challengerID {
// 				challenger = p
// 				break
// 			}
// 		}
// 		gm.mu.Unlock()

// 		if challenger == nil {
// 			return
// 		}

// 		if response == "ACCEPTED" {
// 			log.Printf("[LOBBY] Invite accepted! %s vs %s", challenger.Name, sender.Name)
			
// 			// Create room
// 			roomID := strings.ToUpper(uuid.New().String()[:6]) + "_INV"
// 			room := NewRoom(roomID, false)
			
// 			gm.mu.Lock()
// 			gm.rooms[roomID] = room
// 			// Remove both from searching queue
// 			sender.Searching = false
// 			challenger.Searching = false
// 			gm.mu.Unlock()

// 			gm.broadcastOnlinePlayers()

// 			challenger.Conn.WriteMessage(websocket.TextMessage, []byte("JOIN:"+roomID+":white"))
// 			sender.Conn.WriteMessage(websocket.TextMessage, []byte("JOIN:"+roomID+":black"))
// 		} else {
// 			log.Printf("[LOBBY] Invite declined by %s", sender.Name)
// 			challenger.Conn.WriteMessage(websocket.TextMessage, []byte("INVITE_DECLINED:"+sender.Name))
// 		}
// 	}
// }



