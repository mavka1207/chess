// Widget → State variables → Lifecycle → Listener → Logic → Dialogs → Build → Board widgets

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chess/chess.dart' as chess_lib;
import 'package:flutter_svg/flutter_svg.dart';
import '../services/websocket_service.dart';
import '../services/chess_pieces_svg.dart';

// ─── Widget ───────────────────────────────────────────────────────────────────

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

// ─── State ────────────────────────────────────────────────────────────────────

class _LobbyScreenState extends State<LobbyScreen> {

  // ── Services ─────────────────────────────
  late WebSocketService _wsService;
  StreamSubscription? _roomSubscription;
  bool _navigating = false;

  // ── Warmup Chess Engine ──────────────────
  late chess_lib.Chess _chess;
  String? _selectedSquare;
  List<Map<String, dynamic>> _possibleMovesData = [];
  String? _lastMoveFrom;
  String? _lastMoveTo;

  // ── Board Textures ─────────────────────────
  late ImageProvider _lightSquareImg;
  late ImageProvider _darkSquareImg;

  // ── Lifecycle ─────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Initialize warmup board
    _chess = chess_lib.Chess();
    _lightSquareImg = const AssetImage('assets/board/light_square.png');
    _darkSquareImg = const AssetImage('assets/board/dark_square.png');
    
    _wsService = Provider.of<WebSocketService>(context, listen: false);
    _setupMatchmakingListener();

    // Short delay to ensure lobby connection is ready before joining queue
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _wsService.joinPublicQueue();
    });
  }

  @override
  void dispose() {
    _roomSubscription?.cancel();
    _wsService.leavePublicQueue();
    super.dispose();
  }

  // ── Matchmaking Listener ──────────────────────────────────────────────────────

  void _setupMatchmakingListener() {
    _roomSubscription = _wsService.roomStream.listen((message) {
      if (!mounted) return;
      debugPrint('🟡 LOBBY MSG: $message');
      
      // Server found a match — navigate to the game room
      final parts = message.split(':');
      if (parts.length >= 3 && parts[0] == 'JOIN') {
        if (_navigating) return;
        _navigating = true;
        Navigator.pushReplacementNamed(
          context, 
          '/game', 
          arguments: '${parts[1]}:${parts[2]}',
        );
      }
    });
  }

  // ── Warmup Move Logic ─────────────────────────────────────────────────────────

  // Handles a tap on a warmup board square — select, deselect, or move
  void _onSquareTap(String square) {
    if (_chess.game_over) return;

    setState(() {
      if (_selectedSquare == null) {
        // First tap — select a white piece
        final piece = _chess.get(square);
        if (piece != null && piece.color == chess_lib.Color.WHITE) {
          _selectedSquare = square;
          _possibleMovesData = List<Map<String, dynamic>>.from(_chess.moves({"square": square, "verbose": true}));
        }
      } else {
        if (square == _selectedSquare) {
          _selectedSquare = null;
          _possibleMovesData = [];
        } else {
          final moveIndex = _possibleMovesData.indexWhere((m) => m["to"] == square);
          if (moveIndex != -1) {
            // Valid target — execute the move
            final moveData = _possibleMovesData[moveIndex];
            _handleMove(_selectedSquare!, square, moveData);
            _selectedSquare = null;
            _possibleMovesData = [];
          } else {
            // Tap another white piece — switch selection
            final piece = _chess.get(square);
            if (piece != null && piece.color == chess_lib.Color.WHITE) {
              _selectedSquare = square;
              _possibleMovesData = List<Map<String, dynamic>>.from(_chess.moves({"square": square, "verbose": true}));
            } else {
              _selectedSquare = null;
              _possibleMovesData = [];
            }
          }
        }
      }
    });
  }

  // Executes the player's move; handles promotion if needed, then triggers bot reply
  void _handleMove(String from, String to, Map<String, dynamic> moveData) async {
    if (_chess.game_over) return;

    String? promotion;
    
    // Check if this move requires a pawn promotion
    final bool isPromotion = (moveData["flags"] as String).contains("p") || moveData.containsKey("promotion");
    
    if (isPromotion) {
      promotion = await _showPromotionDialog(chess_lib.Color.WHITE);
      if (promotion == null) return; // Player cancelled
    }

    setState(() {
      final Map<String, String> move = {
        "from": from, 
        "to": to, 
      };
      
      if (promotion != null) move["promotion"] = promotion;

      final success = _chess.move(move);

      if (success) {
        _lastMoveFrom = from;
        _lastMoveTo = to;
        if (_chess.game_over) {
          _showGameOver();
        } else {
          // Short pause before bot replies, so the move feels natural
          Timer(const Duration(milliseconds: 800), _makeMiniBotMove);
        }
      }
    });
  }

  // Makes a random move for the bot opponent in the warmup game
  void _makeMiniBotMove() {
    if (!mounted || _chess.game_over) return;

    final moves = _chess.moves({"verbose": true});
    if (moves.isEmpty) return;
    
    setState(() {
      final moveList = List.from(moves);
      moveList.shuffle();
      final move = moveList.first;
      _chess.move(move);
      _lastMoveFrom = move["from"] as String;
      _lastMoveTo = move["to"] as String;
      if (_chess.game_over) {
        _showGameOver();
      }
    });
  }

  // Resets the warmup board back to the starting position
  void _resetWarmup() {
    setState(() {
      _chess = chess_lib.Chess();
      _selectedSquare = null;
      _possibleMovesData = [];
      _lastMoveFrom = null;
      _lastMoveTo = null;
    });
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────────

  // Shows game-over result with an option to restart the warmup
  void _showGameOver() {
    String reason = "Game Over";
    if (_chess.in_checkmate) {
      reason = "Checkmate!";
    } else if (_chess.in_draw) {
      reason = "Draw";
    }
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: const Color(0xFF262421),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text("Warmup Ended", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Text(reason, style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _resetWarmup();
              },
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFE94560),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("RESTART", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // Lets the player pick a piece to promote their pawn to
  Future<String?> _showPromotionDialog(chess_lib.Color color) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: AlertDialog(
            backgroundColor: const Color(0xFF262421),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text("Warmup Promotion", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _promotionOption(chess_lib.PieceType.QUEEN, color, 'q'),
                _promotionOption(chess_lib.PieceType.KNIGHT, color, 'n'),
                _promotionOption(chess_lib.PieceType.ROOK, color, 'r'),
                _promotionOption(chess_lib.PieceType.BISHOP, color, 'b'),
              ],
            ),
          ),
        );
      },
    );
  }

  // Builds a single tappable piece option inside the promotion dialog
  Widget _promotionOption(chess_lib.PieceType type, chess_lib.Color color, String code) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(code),
      child: Container(
        padding: const EdgeInsets.all(8),
        width: 54, height: 54,
        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
        child: SvgPicture.string(PieceSvg.getSvgForPiece(chess_lib.Piece(type, color))),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    bool isGameOver = _chess.game_over;
    return Scaffold(
      backgroundColor: const Color(0xFF262421),
      body: SafeArea(
        child: Column(
          children: [

            // ── Header — matchmaking status ─────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  const Text("Matching...", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    isGameOver ? "Warm up ended!" : "Warm up with Bot while you wait", 
                    style: TextStyle(color: isGameOver ? const Color(0xFFE94560) : Colors.white54, fontSize: 16),
                  ),

                  // ── Turn indicator ──────────────────────────
                  if (!isGameOver) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _chess.turn == chess_lib.Color.WHITE
                                ? Colors.white
                                : Colors.black,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white38),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _chess.turn == chess_lib.Color.WHITE
                              ? "Your turn"
                              : "Bot is thinking...",
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // ── Warmup board ─────────────────────────────────
            Expanded(
              child: _buildBoard(),
            ),

            // ── Footer — spinner + cancel button ─────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  const CircularProgressIndicator(color: Color(0xFFE94560)),
                  const SizedBox(height: 12),
                  const Text(
                    "Searching for an opponent...",
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      _wsService.leavePublicQueue();
                      Navigator.pop(context);
                    },
                    child: const Text("CANCEL SEARCH"),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Board Widgets ─────────────────────────────────────────────────────────────

  // Builds the full 8x8 warmup board grid
  Widget _buildBoard() {
    double size = MediaQuery.of(context).size.width - 32;
    return Center(
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20, spreadRadius: 5)],
        ),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
          itemCount: 64,
          physics: const NeverScrollableScrollPhysics(),
          itemBuilder: (context, index) {
            int row = index ~/ 8;
            int col = index % 8;
            int visualRow = 7 - row;
            int visualCol = col;
            String square = "${String.fromCharCode(97 + visualCol)}${visualRow + 1}";
            bool isDark = (visualRow + visualCol) % 2 == 0;
            return _buildSquare(square, isDark, row, col);
          },
        ),
      ),
    );
  }

  // Builds a single square with its texture, highlights, piece, and move dot
  Widget _buildSquare(String square, bool isDark, int row, int col) {
    bool isSelected = _selectedSquare == square;
    bool isPossible = _possibleMovesData.any((m) => m["to"] == square);
    bool isLastMove = square == _lastMoveFrom || square == _lastMoveTo;
    final piece = _chess.get(square);

    return GestureDetector(
      onTap: () => _onSquareTap(square),
      child: Container(
        decoration: BoxDecoration(
          image: DecorationImage(image: isDark ? _darkSquareImg : _lightSquareImg, fit: BoxFit.cover),
        ),
        child: Container(
          color: isSelected ? Colors.orange.withValues(alpha: 0.5) : (isLastMove ? Colors.yellow.withValues(alpha: 0.2) : Colors.transparent),
          child: Stack(
            children: [
              if (piece != null) Center(child: Padding(padding: const EdgeInsets.all(4), child: SvgPicture.string(PieceSvg.getSvgForPiece(piece)))),
              if (isPossible) Center(child: Container(width: 12, height: 12, decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle))),
            ],
          ),
        ),
      ),
    );
  }
}
