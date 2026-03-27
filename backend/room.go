package main

import (
	"fmt"
	"log"
	"net/http"
	"strings"
	"sync"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
)

type GameManager struct {
	rooms      map[string]*Room
	waitingRoom chan *websocket.Conn
	mu         sync.Mutex
}

func NewGameManager() *GameManager {
	gm := &GameManager{
		rooms:      make(map[string]*Room),
		waitingRoom: make(chan *websocket.Conn, 10),
	}
	go gm.matchmaking()
	return gm
}

func (gm *GameManager) matchmaking() {
	for {
		player1 := <-gm.waitingRoom
		player2 := <-gm.waitingRoom

		roomID := strings.ToUpper(uuid.New().String())
		room := NewRoom(roomID)

		gm.mu.Lock()
		gm.rooms[roomID] = room
		gm.mu.Unlock()

		log.Printf("Match found! Creating room %s\n", roomID)
		
		// Notify both players of the room ID and their colors
		player1.WriteMessage(websocket.TextMessage, []byte("JOIN:"+roomID+":white"))
		player2.WriteMessage(websocket.TextMessage, []byte("JOIN:"+roomID+":black"))
		
		// Note: Don't close immediately, let the client's navigation trigger closure
	}
}

func (gm *GameManager) HandleLobby(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("Upgrade error:", err)
		return
	}
	log.Println("Player entered lobby")
	gm.waitingRoom <- conn
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

	room.Join(conn)
}
