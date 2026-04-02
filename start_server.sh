#!/bin/bash

# Navigate to the directory where the script is located
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "========================================="
echo "♟️  Starting Chess Backend..."
echo "========================================="

# Change to backend directory and start Go server in background
cd backend
go run . &
BACKEND_PID=$!

sleep 2 # wait a moment for the server to start

echo ""
echo "========================================="
echo "🌍 Starting Ngrok Tunnel..."
echo "Domain: colory-kaci-dreadingly.ngrok-free.dev"
echo "========================================="

# Start ngrok tunnel in foreground
ngrok http --domain=colory-kaci-dreadingly.ngrok-free.dev 8080

# When the user stops ngrok (Ctrl+C), kill the backend automatically
echo "Shutting down backend..."
kill $BACKEND_PID
