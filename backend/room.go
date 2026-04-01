package main

import (
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
	waitingRoom []*websocket.Conn
	mu          sync.Mutex
}

func NewGameManager() *GameManager {
	gm := &GameManager{
		rooms:       make(map[string]*Room),
		waitingRoom: make([]*websocket.Conn, 0),
	}
	go gm.matchmaking()
	return gm
}

func (gm *GameManager) matchmaking() {
	for {
		time.Sleep(1 * time.Second)
		gm.mu.Lock()

		if len(gm.waitingRoom) < 2 {
			gm.mu.Unlock()
			continue
		}

		// Take first two players
		player1 := gm.waitingRoom[0]
		player2 := gm.waitingRoom[1]

		// Check if player1 is still connected
		if err := player1.WriteControl(websocket.PingMessage, []byte{}, time.Now().Add(time.Second)); err != nil {
			log.Println("Skipping disconnected player1 in matchmaking")
			gm.waitingRoom = gm.waitingRoom[1:]
			player1.Close()
			gm.mu.Unlock()
			continue
		}

		// Check if player2 is still connected
		if err := player2.WriteControl(websocket.PingMessage, []byte{}, time.Now().Add(time.Second)); err != nil {
			log.Println("Skipping disconnected player2 in matchmaking")
			gm.waitingRoom = append(gm.waitingRoom[:1], gm.waitingRoom[2:]...)
			player2.Close()
			gm.mu.Unlock()
			continue
		}

		// Both are good! Remove them from waiting room
		gm.waitingRoom = gm.waitingRoom[2:]
		gm.mu.Unlock()

		roomID := strings.ToUpper(uuid.New().String())
		room := NewRoom(roomID)

		gm.mu.Lock()
		gm.rooms[roomID] = room
		gm.mu.Unlock()

		log.Printf("Match found! Creating room %s\n", roomID)

		// Notify both players of the room ID and their colors
		err1 := player1.WriteMessage(websocket.TextMessage, []byte("JOIN:"+roomID+":white"))
		err2 := player2.WriteMessage(websocket.TextMessage, []byte("JOIN:"+roomID+":black"))

		if err1 != nil || err2 != nil {
			if err1 != nil {
				log.Printf("Failed to notify player 1: %v\n", err1)
			} else {
				// Player 1 successfully notified but Player 2 failed. Put P1 back.
				gm.mu.Lock()
				gm.waitingRoom = append([]*websocket.Conn{player1}, gm.waitingRoom...)
				gm.mu.Unlock()
			}
			
			if err2 != nil {
				log.Printf("Failed to notify player 2: %v\n", err2)
			} else {
				// Player 2 successfully notified but Player 1 failed. Put P2 back.
				gm.mu.Lock()
				gm.waitingRoom = append([]*websocket.Conn{player2}, gm.waitingRoom...)
				gm.mu.Unlock()
			}
			// Cancel this match
			gm.mu.Lock()
			delete(gm.rooms, roomID)
			gm.mu.Unlock()
			continue
		}
	}
}

func (gm *GameManager) HandleLobby(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("Upgrade error:", err)
		return
	}
	
	gm.mu.Lock()
	gm.waitingRoom = append(gm.waitingRoom, conn)
	gm.mu.Unlock()
	log.Println("Player entered lobby")
	
	defer func() {
		gm.mu.Lock()
		log.Println("Player left lobby (cleaning queue)")
		for i, c := range gm.waitingRoom {
			if c == conn {
				gm.waitingRoom = append(gm.waitingRoom[:i], gm.waitingRoom[i+1:]...)
				break
			}
		}
		gm.mu.Unlock()
		conn.Close()
	}()

	// Wait for disconnection/joining game
	for {
		_, _, err := conn.ReadMessage()
		if err != nil {
			break
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

	room.Join(conn, requestedColor)
}
