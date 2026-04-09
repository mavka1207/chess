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

// Part files — each handles a focused area of the game screen
part 'game_board_dialogs.dart'; 
part 'game_board_board.dart';

// ─── Widget ──────────────────────────────────────────────────────────────────

class GameBoardScreen extends StatefulWidget {
  const GameBoardScreen({super.key});

  @override
  State<GameBoardScreen> createState() => _GameBoardScreenState();
}

// ─── State ────────────────────────────────────────────────────────────────────

class _GameBoardScreenState extends State<GameBoardScreen> {

  // ── Services ─────────────────────
  late WebSocketService _wsService;
  StreamSubscription? _gameSubscription;
  bool _connected = false;

  // ── Chess Engine ─────────────────
  late chess_lib.Chess _chess;
  List<String> _fenHistory = []; // Track FENs for analysis
  String _moveHistory = "";

  // ── Room & Player Info ────────────
  String? _roomID;
  String? _assignedColor;
  String _myColor = "";
  Map<String, String>? _whitePlayer;
  Map<String, String>? _blackPlayer;

  // ── Turn & Selection State ─────────
  String _turn = "white";
  String? _selectedSquare;
  List<String> _possibleMoves = [];
  String? _lastMoveFrom;
  String? _lastMoveTo;

  // ── Opponent Status ────────────────
  bool _opponentLeft = false;

  // ── Rematch State ──────────────────
  bool _opponentWantsRematch = false;
  bool _rematchRequestedByMe = false;
  StateSetter? _dialogSetState;  // Used to update the active dialog from outside

  // ── Board Textures ─────────────────
  // High-fidelity board colors (Modern Wood)
  late ImageProvider _lightSquareImg;
  late ImageProvider _darkSquareImg;

  // ── Lifecycle ────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _lightSquareImg = const AssetImage('assets/board/light_square.png');
    _darkSquareImg = const AssetImage('assets/board/dark_square.png');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_connected) return; // Guard: connect only once
    _connected = true;
    
    // Parse route arguments — supports "ID:color" or just "ID"
    final args = ModalRoute.of(context)!.settings.arguments as String;
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

    // Build the WebSocket URL with player profile info
    final profile = ProfileService();
    final name = Uri.encodeComponent(profile.nickname);
    final avatar = profile.avatarIndex.toString();
    final id = profile.deviceId;

    String wsUrl = 
      'wss://${WebSocketService.serverUrl}/rooms/$_roomID?name=$name&avatar=$avatar&id=$id';

    if (_assignedColor != null) {
      wsUrl += '&color=$_assignedColor';
    }
    _wsService.connectToGame(wsUrl);

    // Initialize chess engine and record the starting position
    _chess = chess_lib.Chess();
    _fenHistory = [_chess.fen]; 
  }

  @override
  void dispose() {
    _gameSubscription?.cancel();
    _wsService.disconnectGame();
    super.dispose();
  }

  // ── WebSocket Listener ───────────────────────────────────────────────────────

  void _setupListeners() {
    _gameSubscription = _wsService.gameStream.listen((message) {
      if (mounted) {
        setState(() {
          // Color assignment from server
          if (message == "white" || message == "black") {
            _myColor = message;
          
          // Opponent profile info received
          } else if (message.startsWith("PLAYER_INFO:")) {
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
          
          // New board position received after a move
          } else if (message.startsWith("BOARD:")) {
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
          
          // Move history string for analysis
          } else if (message.startsWith("MOVES:")) {
            _moveHistory = message.substring(6);

          // Server confirmed a full game restart
          } else if (message == "RESTARTED") {
            // print('[GAME] Match Restarted');
            // Close any open dialog first
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
            // print('[DEBUG] Board Reset Successful and UI Updated');

          // Opponent clicked rematch — update the open dialog
          } else if (message == "REMATCH_REQUESTED") {
            if (_dialogSetState != null) {
              _opponentWantsRematch = true;
              _dialogSetState!(() {});
            }

          // Our own rematch request was received by the server
          } else if (message == "REMATCH_SENT") {
            if (_dialogSetState != null) {
              _rematchRequestedByMe = true;
              _dialogSetState!(() {});
            }

          // Opponent disconnected during or before the game
          } else if (message.startsWith("OPPONENT_LEFT")) {
            // print('[GAME] Opponent Left Event Received');
            _opponentLeft = true;
            if (_dialogSetState != null) {
              // A dialog is already open — let it react to the flag
              _dialogSetState!(() {});
            } else {  
              // No dialog open — show a standalone "Opponent Left" dialog
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
          
          // Turn ownership changed
          } else if (message.startsWith("TURN:")) {
            _turn = message.substring(5);
            // print('[GAME] Turn Received: $_turn');

          // Game ended — show result dialog
          } else if (message.startsWith("GAMEOVER:")) {
            _showGameOverDialog(message.substring(9));
            HapticFeedback.vibrate();

          // Server error — display as a snackbar
          } else if (message.startsWith("ERROR:")) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message)),
            );
          }
        });
      }
    });
  }

  // ── Move Logic ────────────────────────────────────────────────────────────────

  // Handles a tap on a board square — select, deselect, or move
  void _onSquareTap(String square) {
    if (_turn != _myColor) return;

    setState(() {
      if (_selectedSquare == null) {
        // First tap — select the piece if it belongs to us
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
        if (square == _selectedSquare) {
          // Tap same square — deselect
          _selectedSquare = null;
          _possibleMoves = [];
        } else if (_possibleMoves.contains(square)) {
          // Valid target — execute the move
          final piece = _chess.get(_selectedSquare!);
          final fromSquare = _selectedSquare!; // Capture it!
          _handleMove(fromSquare, square, piece);
          _selectedSquare = null;
          _possibleMoves = [];
        } else {
          // Tap a different friendly piece — switch selection
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

  // Sends the move to the server; prompts for promotion if needed
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
          return; // Player cancelled the promotion picker
        }
      }
    }
    // print('[GAME] Sending Move: $moveStr');
    _wsService.sendMove(moveStr);
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool isWhite = _myColor == "white" || _myColor == "";

    return Scaffold(
      backgroundColor: const Color(0xFF262421),
      appBar: AppBar(
        // Show room ID in the title, with special cases for invite/bot rooms
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
              // Opponent panel always on top, our panel on the bottom
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

  // ── Player Panel ──────────────────────────────────────────────────────────────

  Widget _buildPlayerPanel(String color) {
    final bool isMe = _myColor == color;
    final bool isMyTurn = _turn == color;
    final player = (color == 'white') ? _whitePlayer : _blackPlayer;
    final profile = ProfileService();

    // Detect practice mode: we are white and there is no black player connected
    final bool isBotOpponent =
        _myColor == 'white' && color == 'black' && player == null;

    final String label = isBotOpponent
        ? 'Bot'
        : (player?['name'] ?? (isMe ? profile.nickname : 'Opponent'));

    // Resolve avatar index safely
    int? avatarIndex;
    final String? avatarIndexStr = player?['avatar'];
    if (avatarIndexStr != null) {
      avatarIndex = int.tryParse(avatarIndexStr); // tryParse won't crash on bad input
    } else if (isMe) {
      avatarIndex = profile.avatarIndex; 
    }
    
    final avatars = ProfileService.getAvailableAvatars();
    final bool hasValidAvatar = 
        avatarIndex != null 
        && avatarIndex >= 0 
        && avatarIndex < avatars.length;
    
    // Count pieces the opponent has captured from this player
    final captured = _getCapturedPieces(
      color == "white" ? chess_lib.Color.BLACK : chess_lib.Color.WHITE);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isMyTurn ? Colors.white.withValues(alpha: 0.05) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Avatar circle
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
          // Name and captured pieces
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
          // Active turn indicator
          if (isMyTurn)
            const Icon(Icons.timer, color: Color(0xFFE94560), size: 18),
        ],
      ),
    );
  }

  // Returns how many pieces of [colorOfOwner] are missing from the board
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

    // Count surviving pieces on the board
    for (var i = 0; i < 64; i++) {
      final piece = _chess.get(_indexToSquare(i));
      if (piece != null && piece.color == colorOfOwner) {
        if (currentCounts.containsKey(piece.type)) {
          currentCounts[piece.type] = currentCounts[piece.type]! + 1;
        }
      }
    }

    // Captured = started with X, now only Y remain
    final Map<chess_lib.PieceType, int> captured = {};
    initialCounts.forEach((type, initial) {
      int count = initial - (currentCounts[type] ?? 0);
      if (count > 0) captured[type] = count;
    });
    return captured;
  }

  // Renders a row of small piece icons showing what has been captured
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

  // ── Stubs (implemented in part files) ─────────────────────────────────────────

  // _buildBoard()               → game_board_board.dart
  // _buildSquare()              → game_board_board.dart
  // _buildPiece()               → game_board_board.dart
  // _renderSvgPiece()           → game_board_board.dart
  // _getSvgForPiece()           → game_board_board.dart
  // _promotionOption()          → game_board_board.dart
  // _indexToSquare()            → game_board_board.dart
  // _showResignDialog()         → game_board_dialogs.dart
  // _showPromotionDialog()      → game_board_dialogs.dart
  // _showGameOverDialog()       → game_board_dialogs.dart
}
