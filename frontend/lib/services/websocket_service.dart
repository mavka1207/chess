import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

class WebSocketService {
  WebSocketChannel? _lobbyChannel;
  WebSocketChannel? _gameChannel;
  String? _currentLobbyUrl;
  String? _currentGameUrl;
  
  final StreamController<String> _roomController = StreamController<String>.broadcast();
  final StreamController<String> _gameController = StreamController<String>.broadcast();

  Stream<String> get roomStream => _roomController.stream;
  Stream<String> get gameStream => _gameController.stream;

  void connectToLobby(String url) {
    if (_currentLobbyUrl == url && _lobbyChannel != null) return;
    disconnectLobby();
    _currentLobbyUrl = url;
    _lobbyChannel = WebSocketChannel.connect(Uri.parse(url));
    _lobbyChannel!.stream.listen((message) {
      _roomController.add(message.toString());
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
    if (_currentGameUrl == url && _gameChannel != null) return;
    disconnectGame();
    _currentGameUrl = url;
    _gameChannel = WebSocketChannel.connect(Uri.parse(url));
    _gameChannel!.stream.listen((message) {
      _gameController.add(message.toString());
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

  void dispose() {
    disconnectLobby();
    disconnectGame();
    _roomController.close();
    _gameController.close();
  }
}
