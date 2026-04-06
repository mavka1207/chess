import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'profile_service.dart';

class WebSocketService {
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

  void connectToLobby(String url) {
    final fullUrl = _appendProfileParams(url);
    if (_currentLobbyUrl == fullUrl && _lobbyChannel != null) return;
    disconnectLobby();
    _currentLobbyUrl = fullUrl;
    _lobbyConnectionId++;
    final thisId = _lobbyConnectionId;
    
    _lobbyChannel = WebSocketChannel.connect(Uri.parse(fullUrl));
    _lobbyChannel!.stream.listen((message) {
      if (thisId == _lobbyConnectionId) {
        _roomController.add(message.toString());
      }
    }, onDone: () {
      // Lobby connection closed
    }, onError: (error) {
      // Lobby error
    });
  }

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
  void joinLobby() {}

  void invitePlayer() {}

  void acceptInvite() {}

  void declineInvite() {}

  void joinPublicQueue() {}


  // ------------- Clean Up -------------
  void dispose() {
    disconnectLobby();
    disconnectGame();
    _roomController.close();
    _gameController.close();
  }
}
