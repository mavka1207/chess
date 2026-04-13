// Config → Channels → Services → Streams → Helpers
// → Lobby Connection → Lobby Actions → Game Connection → Game Actions → Cleanup

import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'profile_service.dart';

class WebSocketService {

  // ── Config ────────────────────────────────────────────────────────────────────

  static const String serverUrl = 'colory-kaci-dreadingly.ngrok-free.dev';

  // ── Channels ──────────────────────────────────────────────────────────────────
  WebSocketChannel? _lobbyChannel;
  WebSocketChannel? _gameChannel;

  // Track active URLs to avoid reconnecting to the same endpoint
  String? _currentLobbyUrl;
  String? _currentGameUrl;
  
  // Connection IDs prevent stale listeners from acting after reconnection
  int _lobbyConnectionId = 0;
  int _gameConnectionId = 0;
  
   // ── Services ──────────────────────────────────────────────────────────────────
  final ProfileService _profileService = ProfileService();

  // ── Streams ───────────────────────────────────────────────────────────────────
  final StreamController<String> _roomController = StreamController<String>.broadcast();
  final StreamController<String> _gameController = StreamController<String>.broadcast();

  Stream<String> get roomStream => _roomController.stream;
  Stream<String> get gameStream => _gameController.stream;

  // ── Helpers ───────────────────────────────────────────────────────────────────

  // Appends the player's profile info to any WebSocket URL as query parameters
  String _appendProfileParams(String url) {
    final uri         = Uri.parse(url);
    final queryParams = Map<String, String>.from(uri.queryParameters);
    
    queryParams['name']   = _profileService.nickname;
    queryParams['avatar'] = _profileService.avatarIndex.toString();
    queryParams['id']     = _profileService.deviceId;
    
    return uri.replace(queryParameters: queryParams).toString();
  }

  // ── Lobby Connection ──────────────────────────────────────────────────────────

  // Opens the lobby WebSocket; auto-reconnects after 5s if the connection drops
  void connectLobby() {
    final url = 'wss://$serverUrl/rooms';
    final fullUrl = _appendProfileParams(url);

    // Already connected to this URL — nothing to do
    if (_currentLobbyUrl == fullUrl && _lobbyChannel != null) return;
    
    disconnectLobby();
    _currentLobbyUrl = fullUrl;
    _lobbyConnectionId++;
    final thisId = _lobbyConnectionId;
    
    try {
      _lobbyChannel = WebSocketChannel.connect(Uri.parse(fullUrl));
      _lobbyChannel!.stream.listen(
        (message) {
          // Discard messages from a previous connection
          if (thisId == _lobbyConnectionId) {
            _roomController.add(message.toString());
          }
        }, 
        onDone: () {
        _currentLobbyUrl = null;
          if (thisId == _lobbyConnectionId) {
            Future.delayed(const Duration(seconds: 5), () => connectLobby());
          }
        }, 
        onError: (error) {
        _currentLobbyUrl = null;
        _roomController.add('[WS_ERROR]$error');
        }
      );
    } catch (e) {
      _roomController.add('[WS_ERROR]$e');
    }
  }

  void disconnectLobby() {
    _lobbyChannel?.sink.close(status.normalClosure);
    _lobbyChannel = null;
    _currentLobbyUrl = null;
  }

  // ── Lobby Actions ─────────────────────────────────────────────────────────────

  // Sends a match request — player enters the public matchmaking queue
  void joinPublicQueue() {
    if (_lobbyChannel != null) {
      _lobbyChannel!.sink.add("MATCHME");
    } 
  }

  // Removes the player from the public matchmaking queue
  void leavePublicQueue() {
    if (_lobbyChannel != null) {
      _lobbyChannel!.sink.add("CANCEL_MATCHME");
    }
  }

  // Sends a private game invite to another player by their device ID
  void sendInvite(String targetId) {
    if (_lobbyChannel != null) {
      _lobbyChannel!.sink.add("INVITE:$targetId");
    }
  }

  // Responds to an incoming invite — accepted or declined
  void respondToInvite(String challengerId, bool accepted) {
    if (_lobbyChannel != null) {
      final action = accepted ? "ACCEPTED" : "DECLINED";
      _lobbyChannel!.sink.add("INVITE_RESPONSE:$challengerId:$action");
    }
  }

  // ── Game Connection ───────────────────────────────────────────────────────────

  // Connects to a specific game room WebSocket
  void connectToGame(String url) {
    final fullUrl = _appendProfileParams(url);

    // Already connected to this exact room — do nothing
    if (_currentGameUrl == fullUrl && _gameChannel != null) return;

    // Different room — disconnect old one first
    disconnectGame();
    _currentGameUrl = fullUrl;
    _gameConnectionId++;
    final thisId = _gameConnectionId;
    
    _gameChannel = WebSocketChannel.connect(Uri.parse(fullUrl));
    _gameChannel!.stream.listen(
      (message) {
        // Discard messages from a previous connection
        if (thisId == _gameConnectionId) {
          _gameController.add(message.toString());
        }
      }, 
      onDone: () {
        if (thisId == _gameConnectionId) {
          _currentGameUrl = null;
        }
      }, 
      onError: (error) {
        _gameController.add('[WS_ERROR]$error');
      }
    );
  }

  void disconnectGame() {
    _gameChannel?.sink.close(status.normalClosure);
    _gameChannel = null;
    _currentGameUrl = null;
  }

  // ── Game Actions ──────────────────────────────────────────────────────────────

  // Sends a move string to the game server e.g. "e2e4" or "e7e8q"
  void sendMove(String move) {
    if (_gameChannel != null) {
      _gameChannel!.sink.add("MOVE:$move");
    }
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────────

  // Closes both connections and stream controllers — call when the app exits
  void dispose() {
    disconnectLobby();
    disconnectGame();
    _roomController.close();
    _gameController.close();
  }
  
  // Drops both connections without closing streams — use before navigating away
  void prepareNewSession() {
    disconnectLobby();
    disconnectGame();
  }
}
