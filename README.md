# Flutter Go Chess Application

A real-time multiplayer chess application built with a **Flutter** frontend and a **Go (Golang)** backend communicating over WebSockets.

## 🌟 Features

*   **Public Matchmaking**: Automatically pairs you with another online player.
*   **Private Rooms** — Use **CREATE PRIVATE** to generate a 6-character room code, share it externally (e.g. via text or chat), and your friend joins anytime using **JOIN PRIVATE**.
*   **Practice Bot**: Play against a server-side bot to explore openings or test the app.
*   **Real-time Sync**: Board state synchronized instantly via WebSockets.
*   **ngrok Tunnel**: Backend exposed over the internet to bypass local network restrictions on mobile via `ngrok`.

## 🏗️ Architecture

1.  **Frontend (`/frontend`)**: Developed in Flutter. It connects to the Go server using the `web_socket_channel` package and visualizes the board using SVG assets.
2.  **Backend (`/backend`)**: Developed in Golang. It acts as the WebSocket server, managing concurrent game rooms, matchmaking queues, and dispatching PGN/FEN states between players.

## 🚀 Prerequisites

To run this project locally, you will need:
*   [Flutter SDK](https://docs.flutter.dev/get-started/install) installed.
*   [Go](https://go.dev/doc/install) installed.
*   [ngrok](https://ngrok.com/download) installed and authenticated (`ngrok config add-authtoken <your-token>`).

##  📁 Project Structure
```bash
chess-app/
    ├── backend/
    │   ├── main.go
    │   ├── game.go
    │   └── room.go
    └── frontend/
        ├── assets/
        ├── lib/
            ├── screens/
            │   ├── main_menu.dart    
            │   ├── profile_setup.dart 
            │   ├── lobby.dart 
            │   ├── game_board.dart    
            │   ├── game_board_board.dart 
            │   ├── game_board_dialogs.dart 
            │   └── analysis_screen.dart   
            ├── services/
            │   ├── chess_pieces_svg.dart 
            │   ├── profile_service.dart 
            │   └── websocket_service.dart          
            └── main.dart               
```


## 🛠️ How to Run the Project

### 1. Start the Backend & Tunnel

Run the following command from the root directory:

```bash
./start_server.sh
```

This starts the Go server on port `8080` and opens the ngrok tunnel simultaneously.

*Note: The script is pre-configured to use the static ngrok domain `colory-kaci-dreadingly.ngrok-free.dev`.*

### 2. Start the Frontend (Mobile App)

The mobile app has already been configured to communicate with the `ngrok` URL defined in the backend script. It is recommended to run the app on a physical device in `--release` mode for maximum performance and stability.

1. Connect your device (e.g., iPhone or Android).
2. Open a new terminal instance and run:

```bash
cd frontend
flutter pub get
flutter run --release
```

## 🔐 Troubleshooting Local Network Issues on Mobile

Modern mobile OSes (like iOS 14+) often block apps from communicating with local network servers directly (e.g., `192.168.x.x`). 
This project overcomes this by routing all game traffic securely through the `ngrok` public tunnel, circumventing internal router firewalls entirely.

## 🔧 Development Tips

### Restarting the backend manually

If you make changes to the Go code and need to restart the server:

```bash
cd backend

# Find the process using port 8080
lsof -i :8080

# Kill it using the PID from the output above
kill -9 <PID>

# Start the server again
go run .
```

> **Note:** `lsof -i :8080` shows a table — look for the value in the `PID` column, not the port number.

## Authors:
[Kateryna Ovsiienko](https://github.com/kateryna256)

[Mayuree reunsati](https://github.com/mareerray)