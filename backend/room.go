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

type GameManager struct {
	rooms       map[string]*Room
	waitingRoom map[*websocket.Conn]*Player // Conn -> Player info in lobby
	mu          sync.Mutex
}

func NewGameManager() *GameManager {
	gm := &GameManager{
		rooms:       make(map[string]*Room),
		waitingRoom: make(map[*websocket.Conn]*Player),
	}
	go gm.matchmaking()
	return gm
}

func (gm *GameManager) matchmaking() {
	for {
		time.Sleep(2 * time.Second)
		// Collect players who are explicitly searching
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

		// Check connectivity
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

		// Match found! 
		p1.Searching = false
		p2.Searching = false
		delete(gm.waitingRoom, c1)
		delete(gm.waitingRoom, c2)
		gm.mu.Unlock()

		gm.broadcastOnlinePlayers() // Notify others that these two left

		roomID := strings.ToUpper(uuid.New().String()[:6])
		room := NewRoom(roomID)

		gm.mu.Lock()
		gm.rooms[roomID] = room
		gm.mu.Unlock()

		log.Printf("Match found! %s vs %s in room %s\n", p1.Name, p2.Name, roomID)

		c1.WriteMessage(websocket.TextMessage, []byte("JOIN:"+roomID+":white"))
		c2.WriteMessage(websocket.TextMessage, []byte("JOIN:"+roomID+":black"))
	}
}

func (gm *GameManager) broadcastOnlinePlayers() {
	gm.mu.Lock()
	defer gm.mu.Unlock()

	type PlayerInfo struct {
		Name   string `json:"name"`
		Avatar string `json:"avatar"`
		ID     string `json:"id"`
		Search bool   `json:"search"` // Let clients know if they can invite or if someone is busy searching
	}

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

func (gm *GameManager) HandleLobby(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("Upgrade error:", err)
		return
	}

	name := r.URL.Query().Get("name")
	avatar := r.URL.Query().Get("avatar")
	playerID := r.URL.Query().Get("id")

	if name == "" {
		name = "Anonymous"
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

	defer func() {
		gm.mu.Lock()
		delete(gm.waitingRoom, conn)
		gm.mu.Unlock()
		conn.Close()
		log.Printf("Player %s left lobby", name)
		gm.broadcastOnlinePlayers()
	}()

	// Handle lobby messages (like invites)
	for {
		_, msg, err := conn.ReadMessage()
		if err != nil {
			break
		}
		gm.handleLobbyMessage(player, string(msg))
	}
}

func (gm *GameManager) handleLobbyMessage(sender *Player, msg string) {
	parts := strings.Split(msg, ":")
	if len(parts) < 1 {
		return
	}

	command := parts[0]

	switch command {
	case "MATCHME":
		log.Printf("Player %s joined matchmaking queue", sender.Name)
		sender.Searching = true
		gm.broadcastOnlinePlayers()

	case "CANCEL_MATCHME":
		log.Printf("Player %s left matchmaking queue", sender.Name)
		sender.Searching = false
		gm.broadcastOnlinePlayers()

	case "INVITE":
		if len(parts) < 2 { return }
		targetID := parts[1]
		gm.mu.Lock()
		var targetPlayer *Player
		for _, p := range gm.waitingRoom {
			if p.ID == targetID {
				targetPlayer = p
				break
			}
		}
		gm.mu.Unlock()

		if targetPlayer != nil {
			log.Printf("Relaying invite from %s to %s", sender.Name, targetPlayer.Name)
			inviteMsg := fmt.Sprintf("INVITE_FROM:%s:%s:%s", sender.ID, sender.Name, sender.Avatar)
			targetPlayer.Conn.WriteMessage(websocket.TextMessage, []byte(inviteMsg))
		}

	case "INVITE_RESPONSE":
		if len(parts) < 3 {
			return
		}
		challengerID := parts[1]
		response := parts[2] // "ACCEPTED" or "DECLINED"

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
			log.Printf("Invite accepted! %s vs %s", challenger.Name, sender.Name)
			
			// Create room
			roomID := strings.ToUpper(uuid.New().String()[:6]) + "_INV"
			room := NewRoom(roomID)
			
			gm.mu.Lock()
			gm.rooms[roomID] = room
			// Remove both from lobby and stop searching
			sender.Searching = false
			challenger.Searching = false
			delete(gm.waitingRoom, challenger.Conn)
			delete(gm.waitingRoom, sender.Conn)
			gm.mu.Unlock()

			gm.broadcastOnlinePlayers()

			challenger.Conn.WriteMessage(websocket.TextMessage, []byte("JOIN:"+roomID+":white"))
			sender.Conn.WriteMessage(websocket.TextMessage, []byte("JOIN:"+roomID+":black"))
		} else {
			log.Printf("Invite declined by %s", sender.Name)
			challenger.Conn.WriteMessage(websocket.TextMessage, []byte("INVITE_DECLINED:"+sender.Name))
		}
	}
}

func (gm *GameManager) HandleCreate(w http.ResponseWriter, r *http.Request) {
	roomID := strings.ToUpper(uuid.New().String()[:6]) // Short code for easier sharing
	room := NewRoom(roomID)

	gm.mu.Lock()
	gm.rooms[roomID] = room
	gm.mu.Unlock()

	log.Printf("Private room created: %s\n", roomID)
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"roomID": "%s"}`, roomID)
}

func (gm *GameManager) HandlePractice(w http.ResponseWriter, r *http.Request) {
	roomID := strings.ToUpper(uuid.New().String()[:6]) + "_BOT"
	room := NewRoom(roomID)
	room.IsBotGame = true
	room.BotColor = "black"

	gm.mu.Lock()
	gm.rooms[roomID] = room
	gm.mu.Unlock()

	log.Printf("Practice room created: %s", roomID)
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"roomID": "%s"}`, roomID)
}

func (gm *GameManager) HandleGame(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Path
	roomID := strings.ToUpper(strings.TrimPrefix(path, "/rooms/"))
	if roomID == "" {
		http.Error(w, "Room ID required", http.StatusBadRequest)
		return
	}

	requestedColor := r.URL.Query().Get("color")
	name := r.URL.Query().Get("name")
	avatar := r.URL.Query().Get("avatar")
	playerID := r.URL.Query().Get("id")

	if name == "" {
		name = "Anonymous"
	}

	gm.mu.Lock()
	room, exists := gm.rooms[roomID]
	gm.mu.Unlock()

	if !exists {
		log.Printf("Join failed: Room %s not found\n", roomID)
		http.Error(w, "Room not found", http.StatusNotFound)
		return
	}

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("Upgrade error:", err)
		return
	}

	room.Join(conn, requestedColor, name, avatar, playerID)
}

