import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:chess/chess.dart' as chess_lib;
import 'package:flutter_svg/flutter_svg.dart';
import 'analysis_screen.dart';
import '../services/websocket_service.dart';
import '../services/chess_pieces_svg.dart';
import '../services/profile_service.dart';

part 'game_board_dialogs.dart'; 
part 'game_baord_board.dart';

class GameBoardScreen extends StatefulWidget {
  const GameBoardScreen({super.key});

  @override
  State<GameBoardScreen> createState() => _GameBoardScreenState();
}

class _GameBoardScreenState extends State<GameBoardScreen> {
  late WebSocketService _wsService;
  StreamSubscription? _gameSubscription;
  late chess_lib.Chess _chess;
  String? _roomID;
  String _myColor = "";
  String _turn = "white";
  String? _selectedSquare;
  List<String> _possibleMoves = [];
  String? _lastMoveFrom;
  String? _lastMoveTo;
  List<String> _fenHistory = []; // Track FENs for analysis
  String _moveHistory = "";
  String? _assignedColor;
  bool _opponentLeft = false;
  bool _opponentWantsRematch = false;
  bool _rematchRequestedByMe = false;
  StateSetter? _dialogSetState;  
  bool _connected = false;
  
  // High-fidelity board colors (Modern Wood)
  late ImageProvider _lightSquareImg;
  late ImageProvider _darkSquareImg;

  @override
  void initState() {
    super.initState();
    _lightSquareImg = const AssetImage('assets/board/light_square.png');
    _darkSquareImg = const AssetImage('assets/board/dark_square.png');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_connected) return; // ← only connect once
    _connected = true;
    
    final args = ModalRoute.of(context)!.settings.arguments as String;
    
    // Support "ID:color" or just "ID"
    if (args.contains(':')) {
      final parts = args.split(':');
      _roomID = parts[0];
      _assignedColor = parts[1];
    } else {
      _roomID = args;
      _assignedColor = null;
    }

    _wsService = Provider.of<WebSocketService>(context, listen: false);
    _setupListeners();

    final profile = ProfileService();
    final name = Uri.encodeComponent(profile.nickname);
    final avatar = profile.avatarIndex.toString();
    final id = profile.deviceId;

    String wsUrl = 'wss://${WebSocketService.serverUrl}/rooms/$_roomID?name=$name&avatar=$avatar&id=$id';

    if (_assignedColor != null) {
      wsUrl += '&color=$_assignedColor';
    }
    _wsService.connectToGame(wsUrl);
    _chess = chess_lib.Chess();
    _fenHistory = [_chess.fen]; // Initialize starting FEN
  }

  Map<String, String>? _whitePlayer;
  Map<String, String>? _blackPlayer;

  void _setupListeners() {
    _gameSubscription = _wsService.gameStream.listen((message) {
      // debugPrint('📩 GAME MSG: $message');
      if (mounted) {
        setState(() {
          if (message == "white" || message == "black") {
            _myColor = message;
            // print('[GAME] Assigned Color: $_myColor');
          } else if (message.startsWith("PLAYER_INFO:")) {
            // print('[GAME] Player Info Received: $message');
            final parts = message.split(":");
            if (parts.length >= 5) {
              final info = {
                'color': parts[1],
                'name': parts[2],
                'avatar': parts[3],
                'id': parts[4],
              };
              if (info['color'] == 'white') {
                _whitePlayer = info;
              } else {
                _blackPlayer = info;
              }
            }
          } else if (message.startsWith("BOARD:")) {
            // print('[GAME] Board Received: $message');
            final parts = message.split(":");
            final fen = parts[1];
            _chess.load(fen);
            _fenHistory.add(fen); 
            if (parts.length > 2) {
              final move = parts[2];
              if (move.length >= 4) {
                _lastMoveFrom = move.substring(0, 2);
                _lastMoveTo = move.substring(2, 4);
                HapticFeedback.mediumImpact();
              }
            }
          } else if (message.startsWith("MOVES:")) {
            _moveHistory = message.substring(6);
          } else if (message == "RESTARTED") {
            print('[GAME] Match Restarted');
            // If GameOver dialog or any other dialog is open, pop it using rootNavigator for reliability
            if (_dialogSetState != null) {
              Navigator.of(context, rootNavigator: true).pop();
              _dialogSetState = null;
            }
            // CRITICAL: Re-initialize chess engine to reset the board position
            _chess = chess_lib.Chess(); 
            _moveHistory = "";
            _lastMoveFrom = null;
            _lastMoveTo = null;
            _selectedSquare = null;
            _possibleMoves = [];
            _fenHistory = [_chess.fen]; 
            _opponentLeft = false; 
            _opponentWantsRematch = false;
            _rematchRequestedByMe = false;
            HapticFeedback.vibrate();
            print('[DEBUG] Board Reset Successful and UI Updated');
          } else if (message == "REMATCH_REQUESTED") {
            if (_dialogSetState != null) {
              _opponentWantsRematch = true;
              _dialogSetState!(() {});
            }
          } else if (message == "REMATCH_SENT") {
            if (_dialogSetState != null) {
              _rematchRequestedByMe = true;
              _dialogSetState!(() {});
            }
          } else if (message.startsWith("OPPONENT_LEFT")) {
            print('[GAME] Opponent Left Event Received');
            _opponentLeft = true;
            if (_dialogSetState != null) {
              _dialogSetState!(() {});
            } else {  
              final isGameInProgress = _moveHistory.isNotEmpty;
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => AlertDialog(
                  backgroundColor: const Color(0xFF262421),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28)
                  ),
                  icon: Icon(
                    isGameInProgress ? Icons.emoji_events : Icons.exit_to_app,
                    color: const Color(0xFFE94560),
                    size: 48,
                  ),
                  title: Text(
                    isGameInProgress ? "Victory!" : "Opponent Left",
                    style: const TextStyle(
                      color: Color(0xFFE94560),
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  content: Text(
                    isGameInProgress 
                      ? "Your opponent resigned!" 
                      : "Your opponent left before the game started.",
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, height: 1.4),
                  ),
                  actions: [
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                          foregroundColor: Colors.white70,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)
                          ),
                        ),
                        onPressed: () => Navigator.of(context).popUntil(
                          (route) => route.isFirst
                        ),
                        child: const Text("MAIN MENU"),
                      ),
                    ),
                  ],
                ),
              );
            }
          } else if (message.startsWith("TURN:")) {
            _turn = message.substring(5);
            print('[GAME] Turn Received: $_turn');
          } else if (message.startsWith("GAMEOVER:")) {
            _showGameOverDialog(message.substring(9));
            HapticFeedback.vibrate();
          } else if (message.startsWith("ERROR:")) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message)),
            );
          }
        });
      }
    });
  }

  // void _showResignDialog() {
  // }

  @override
  void dispose() {
    _gameSubscription?.cancel();
    _wsService.disconnectGame();
    super.dispose();
  }

  void _onSquareTap(String square) {
    if (_turn != _myColor) return;

    setState(() {
      if (_selectedSquare == null) {
        // Select piece
        final piece = _chess.get(square);
        if (piece != null && 
            ((_myColor == "white" && piece.color == chess_lib.Color.WHITE) ||
            (_myColor == "black" && piece.color == chess_lib.Color.BLACK))) {
          _selectedSquare = square;
          _possibleMoves = _chess.moves({"square": square, "verbose": true})
              .map((m) => m["to"] as String)
              .toList();
        }
      } else {
        // Try to move
        if (square == _selectedSquare) {
          _selectedSquare = null;
          _possibleMoves = [];
        } else if (_possibleMoves.contains(square)) {
          final piece = _chess.get(_selectedSquare!);
          final fromSquare = _selectedSquare!; // Capture it!
          _handleMove(fromSquare, square, piece);
          _selectedSquare = null;
          _possibleMoves = [];
        } else {
          // Select another piece
          final piece = _chess.get(square);
          if (piece != null && 
              ((_myColor == "white" && piece.color == chess_lib.Color.WHITE) ||
              (_myColor == "black" && piece.color == chess_lib.Color.BLACK))) {
            _selectedSquare = square;
            _possibleMoves = _chess.moves({"square": square, "verbose": true})
                .map((m) => m["to"] as String)
                .toList();
          } else {
            _selectedSquare = null;
            _possibleMoves = [];
          }
        }
      }
    });
  }

  void _handleMove(String from, String to, chess_lib.Piece? piece) async {
    String moveStr = "$from$to";
    
    // Check for promotion
    if (piece?.type == chess_lib.PieceType.PAWN) {
      bool isPromotion = (_myColor == "white" && to.endsWith("8")) ||
                        (_myColor == "black" && to.endsWith("1"));
      
      if (isPromotion) {
        final promotion = await _showPromotionDialog(piece!.color);
        if (promotion != null) {
          moveStr = "$from$to$promotion";
        } else {
          return; // Cancelled
        }
      }
    }
    
    print('[GAME] Sending Move: $moveStr');
    _wsService.sendMove(moveStr);
  }

  // Future<String?> _showPromotionDialog(chess_lib.Color color) async {
  // }

  // Widget _promotionOption(chess_lib.PieceType type, chess_lib.Color color, String code) {
  // }

//   void _showGameOverDialog(String reason) {
// }

  @override
  Widget build(BuildContext context) {
    final bool isWhite = _myColor == "white" || _myColor == "";
    return Scaffold(
      backgroundColor: const Color(0xFF262421),
      appBar: AppBar(
        title: Text(
          _roomID == null || _roomID!.isEmpty
            ? "Chess"
            : _roomID!.endsWith('_INV')
              ? "Room: ${_roomID!.replaceAll('_INV', '')}"
              : _roomID!.endsWith('_BOT')
                ? "Chess"
                : "Room: $_roomID"
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.flag_outlined, color: Colors.white70),
            tooltip: "Resign Game",
            onPressed: _showResignDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            tooltip: "Restart Game",
            onPressed: () {
              _wsService.sendMove("RESTART");
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildPlayerPanel(isWhite ? "black" : "white"),
              const SizedBox(height: 20),
              _buildBoard(),
              const SizedBox(height: 20),
              _buildPlayerPanel(isWhite ? "white" : "black"),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerPanel(String color) {
    final bool isMe = _myColor == color;
    final bool isMyTurn = _turn == color;
    
    final player = (color == 'white') ? _whitePlayer : _blackPlayer;

    final profile = ProfileService();

    // Practice mode: player is white, bot is black
    final bool isBotOpponent =
        _myColor == 'white' &&
        color == 'black' &&
        player == null;

    final String label = isBotOpponent
        ? 'Bot'
        : (player?['name'] ?? (isMe ? profile.nickname : 'Opponent'));

    int? avatarIndex;
    final String? avatarIndexStr = player?['avatar'];
    if (avatarIndexStr != null) {
      avatarIndex = int.tryParse(avatarIndexStr); // tryParse won't crash on bad input
    } else if (isMe) {
      avatarIndex = profile.avatarIndex; // show our own avatar while waiting
    }
    
    // Validate the index is in range
    final avatars = ProfileService.getAvailableAvatars();
    final bool hasValidAvatar = 
        avatarIndex != null 
        && avatarIndex >= 0 
        && avatarIndex < avatars.length;
    
    // Calculate captured pieces
    Map<chess_lib.PieceType, int> captured = _getCapturedPieces(
      color == "white" ? chess_lib.Color.BLACK : chess_lib.Color.WHITE);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isMyTurn ? Colors.white.withValues(alpha: 0.05) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isMe 
                ? const Color(0xFFE94560).withValues(alpha: 0.1) 
                : Colors.white.withValues(alpha: 0.05),
              shape: BoxShape.circle,
              border: Border.all(color: isMe ? const Color(0xFFE94560) : Colors.white10),
            ),
            padding: const EdgeInsets.all(4),
            child: isBotOpponent
              ? const Icon(
                Icons.smart_toy,
                color: Colors.white70,
                )
              : hasValidAvatar
                ? SvgPicture.string(avatars[avatarIndex])
                : Icon(
                    Icons.person, 
                    color: isMe ? const Color(0xFFE94560) : Colors.white70,
                  ),          
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: isMyTurn ? Colors.white : Colors.white70,
                    fontWeight: isMyTurn ? FontWeight.bold : FontWeight.normal,
                    fontSize: 16,
                  ),
                ),
                if (captured.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _buildCapturedRow(captured, color == "white" ? chess_lib.Color.BLACK : chess_lib.Color.WHITE),
                ],
              ],
            ),
          ),
          if (isMyTurn)
            const Icon(Icons.timer, color: Color(0xFFE94560), size: 18),
        ],
      ),
    );
  }

  Map<chess_lib.PieceType, int> _getCapturedPieces(chess_lib.Color colorOfOwner) {
    final initialCounts = {
      chess_lib.PieceType.PAWN: 8,
      chess_lib.PieceType.ROOK: 2,
      chess_lib.PieceType.KNIGHT: 2,
      chess_lib.PieceType.BISHOP: 2,
      chess_lib.PieceType.QUEEN: 1,
    };

    final currentCounts = {
      chess_lib.PieceType.PAWN: 0,
      chess_lib.PieceType.ROOK: 0,
      chess_lib.PieceType.KNIGHT: 0,
      chess_lib.PieceType.BISHOP: 0,
      chess_lib.PieceType.QUEEN: 0,
    };

    for (var i = 0; i < 64; i++) {
      final piece = _chess.get(_indexToSquare(i));
      if (piece != null && piece.color == colorOfOwner) {
        if (currentCounts.containsKey(piece.type)) {
          currentCounts[piece.type] = currentCounts[piece.type]! + 1;
        }
      }
    }

    Map<chess_lib.PieceType, int> captured = {};
    initialCounts.forEach((type, initial) {
      int count = initial - (currentCounts[type] ?? 0);
      if (count > 0) captured[type] = count;
    });
    return captured;
  }

  Widget _buildCapturedRow(Map<chess_lib.PieceType, int> captured, chess_lib.Color color) {
    List<Widget> pieces = [];
    captured.forEach((type, count) {
      pieces.add(
        Padding(
          padding: const EdgeInsets.only(right: 8.0, bottom: 4.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: _renderSvgPiece(chess_lib.Piece(type, color), isSmall: true),
              ),
              if (count > 1)
                Padding(
                  padding: const EdgeInsets.only(left: 2.0),
                  child: Text(
                    "x$count", 
                    style: const TextStyle(
                      color: Colors.white, 
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    )
                  ),
                ),
            ],
          ),
        )
      );
    });
    return Wrap(children: pieces);
  }

  // Widget _buildBoard() {
  // }

  // Widget _buildSquare(String square, bool isDark, int visualRow, int visualCol) {
  // }

  // Widget _buildPiece(String square) {
  // }

  // String _getSvgForPiece(chess_lib.Piece piece) {
  // }

  // String _indexToSquare(int index) {
  // }
}
