import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'profile_service.dart';

class WebSocketService {
  static const String serverUrl = 'colory-kaci-dreadingly.ngrok-free.dev';

  WebSocketChannel? _lobbyChannel;
  WebSocketChannel? _gameChannel;
  String? _currentLobbyUrl;
  String? _currentGameUrl;
  
  int _lobbyConnectionId = 0;
  int _gameConnectionId = 0;
  
  final ProfileService _profileService = ProfileService();
  
  final StreamController<String> _roomController = StreamController<String>.broadcast();
  final StreamController<String> _gameController = StreamController<String>.broadcast();

  Stream<String> get roomStream => _roomController.stream;
  Stream<String> get gameStream => _gameController.stream;

  String _appendProfileParams(String url) {
    final uri = Uri.parse(url);
    final queryParams = Map<String, String>.from(uri.queryParameters);
    
    queryParams['name'] = _profileService.nickname;
    queryParams['avatar'] = _profileService.avatarIndex.toString();
    queryParams['id'] = _profileService.deviceId;
    
    return uri.replace(queryParameters: queryParams).toString();
  }

  void connectLobby() {
    final url = 'wss://$serverUrl/rooms';
    final fullUrl = _appendProfileParams(url);
    if (_currentLobbyUrl == fullUrl && _lobbyChannel != null) return;
    
    disconnectLobby();
    _currentLobbyUrl = fullUrl;
    _lobbyConnectionId++;
    final thisId = _lobbyConnectionId;
    
    print('[WS] Connecting to Lobby: $fullUrl');
    
    try {
      _lobbyChannel = WebSocketChannel.connect(Uri.parse(fullUrl));
      _lobbyChannel!.stream.listen((message) {
        if (thisId == _lobbyConnectionId) {
          if (message.toString().startsWith('ONLINE_PLAYERS:')) {
             // Only log this once or rarely to avoid spam
             // print('[WS] Received online players update'); 
          }
          _roomController.add(message.toString());
        }
      }, onDone: () {
        print('[WS] Lobby Connection Closed (ID: $thisId)');
        _currentLobbyUrl = null;
        if (thisId == _lobbyConnectionId) {
          Future.delayed(const Duration(seconds: 5), () => connectLobby());
        }
      }, onError: (error) {
        print('[WS] Lobby Connection Error (ID: $thisId): $error');
        _currentLobbyUrl = null;
      });
    } catch (e) {
      print('[WS] Failed to initiate lobby connection: $e');
    }
  }

  // Deprecated: use connectLobby()
  void connectToLobby(String url) => connectLobby();

  void disconnectLobby() {
    _lobbyChannel?.sink.close(status.normalClosure);
    _lobbyChannel = null;
    _currentLobbyUrl = null;
  }

  void connectToGame(String url) {
    final fullUrl = _appendProfileParams(url);
    if (_currentGameUrl == fullUrl && _gameChannel != null) return;
    disconnectGame();
    _currentGameUrl = fullUrl;
    _gameConnectionId++;
    final thisId = _gameConnectionId;
    
    _gameChannel = WebSocketChannel.connect(Uri.parse(fullUrl));
    _gameChannel!.stream.listen((message) {
      if (thisId == _gameConnectionId) {
        _gameController.add(message.toString());
      }
    }, onDone: () {
      // Game connection closed
    }, onError: (error) {
      // Game error
    });
  }

  void disconnectGame() {
    _gameChannel?.sink.close(status.normalClosure);
    _gameChannel = null;
    _currentGameUrl = null;
  }

  void sendMove(String move) {
    if (_gameChannel != null) {
      _gameChannel!.sink.add(move);
    }
  }

  void prepareNewSession() {
    disconnectLobby();
    disconnectGame();
  }

  // ------------- Lobby Actions -------------
  void sendInvite(String targetId) {
    if (_lobbyChannel != null) {
      _lobbyChannel!.sink.add("INVITE:$targetId");
    }
  }

  void respondToInvite(String challengerId, bool accepted) {
    if (_lobbyChannel != null) {
      final action = accepted ? "ACCEPTED" : "DECLINED";
      _lobbyChannel!.sink.add("INVITE_RESPONSE:$challengerId:$action");
    }
  }

  void joinPublicQueue() {
    if (_lobbyChannel != null) {
      _lobbyChannel!.sink.add("MATCHME");
    }
  }

  void leavePublicQueue() {
    if (_lobbyChannel != null) {
      _lobbyChannel!.sink.add("CANCEL_MATCHME");
    }
  }


  // ------------- Clean Up -------------
  void dispose() {
    disconnectLobby();
    disconnectGame();
    _roomController.close();
    _gameController.close();
  }
}
