package main

import (
	"log"
	"net/http"
	"os"

	"github.com/gorilla/websocket"
)

// ── WebSocket Upgrader ────────────────────────────────────────────────────────

// upgrader promotes HTTP connections to WebSocket connections.
// CheckOrigin allows all origins — restrict this in production.
var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true 
	},
}

// ── Entry Point ───────────────────────────────────────────────────────────────

func main() {
	// Default to port 8080 if PORT environment variable is not set
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	gameManager := NewGameManager()

	// ── Routes ────────────────────────────────────────────────────────────────
	http.HandleFunc("/create", gameManager.HandleCreate) // creates a new private game room
	http.HandleFunc("/practice", gameManager.HandlePractice) // starts a solo practice session against the bot
	http.HandleFunc("/rooms", gameManager.HandleLobby) // lobby WebSocket for matchmaking and invites
	http.HandleFunc("/rooms/", gameManager.HandleGame) // /rooms/{id} game WebSocket for an active match

	log.Printf("Server starting on port %s", port)
	
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal("ListenAndServe: ", err)
	}
}
