# Flutter Go Chess Application

A real-time multiplayer chess application built with a **Flutter** frontend and a **Go (Golang)** backend using WebSockets.

## 🌟 Features

*   **Public Matchmaking**: Automatically pairs you with another player looking for a match.
*   **Private Rooms**: Create a private room with a generated code to play with a friend.
*   **Practice Bot**: Play locally against a chess bot to hone your skills.
*   **Real-time Communication**: Lightning-fast game state synchronization via WebSockets.
*   **Public Tunneling**: Configured to bypass local network restrictions by exposing the backend over the internet via `ngrok`.

## 🏗️ Architecture

1.  **Frontend (`/frontend`)**: Developed in Flutter. It connects to the Go server using the `web_socket_channel` package and visualizes the board using SVG assets.
2.  **Backend (`/backend`)**: Developed in Golang. It acts as the WebSocket server, managing concurrent game rooms, matchmaking queues, and dispatching PGN/FEN states between players.

## 🚀 Prerequisites

To run this project locally, you will need:
*   [Flutter SDK](https://docs.flutter.dev/get-started/install) installed.
*   [Go](https://go.dev/doc/install) installed.
*   [ngrok](https://ngrok.com/download) installed and authenticated (`ngrok config add-authtoken <your-token>`).

## 🛠️ How to Run the Project

### 1. Start the Backend & Tunnel

We use an automated script that simultaneously spins up the backend Go server on port `8080` and exposes it securely over the internet using `ngrok`.

Run the following command from the root directory:

```bash
./start_server.sh
```

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
