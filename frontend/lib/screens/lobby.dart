import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chess/chess.dart' as chess_lib;
import 'package:flutter_svg/flutter_svg.dart';
import '../services/websocket_service.dart';
import '../services/chess_pieces_svg.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  late WebSocketService _wsService;
  StreamSubscription? _roomSubscription;
  
  // Local state for warmup
  late chess_lib.Chess _chess;
  String? _selectedSquare;
  List<Map<String, dynamic>> _possibleMovesData = [];
  String? _lastMoveFrom;
  String? _lastMoveTo;
  
  late ImageProvider _lightSquareImg;
  late ImageProvider _darkSquareImg;

  @override
  void initState() {
    super.initState();
    _chess = chess_lib.Chess();
    _lightSquareImg = const AssetImage('assets/board/light_square.png');
    _darkSquareImg = const AssetImage('assets/board/dark_square.png');
    
    _wsService = Provider.of<WebSocketService>(context, listen: false);
    _wsService.prepareNewSession(); // Clear any stale connections
    _wsService.connectToLobby('wss://colory-kaci-dreadingly.ngrok-free.dev/rooms');
    
    // Start listening immediately - the WebSocketService connection tracking handles safety
    if (!mounted) return;
    _roomSubscription = _wsService.roomStream.listen((message) {
      if (!mounted) return;
      
      final parts = message.split(':');
      if (parts.length >= 3 && parts[0] == 'JOIN') {
        final roomID = parts[1];
        final assignedColor = parts[2];
        Navigator.pushReplacementNamed(
          context, 
          '/game', 
          arguments: '$roomID:$assignedColor',
        );
      }
    });
  }

  @override
  void dispose() {
    _roomSubscription?.cancel();
    _wsService.disconnectLobby();
    super.dispose();
  }

  void _onSquareTap(String square) {
    if (_chess.game_over) return;
    setState(() {
      if (_selectedSquare == null) {
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
            final moveData = _possibleMovesData[moveIndex];
            _handleMove(_selectedSquare!, square, moveData);
            _selectedSquare = null;
            _possibleMovesData = [];
          } else {
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

  void _handleMove(String from, String to, Map<String, dynamic> moveData) async {
    if (_chess.game_over) return;
    String? promotion;
    
    // Check if the engine flags this move as a promotion
    bool isPromotion = (moveData["flags"] as String).contains("p") || moveData.containsKey("promotion");
    
    if (isPromotion) {
      promotion = await _showPromotionDialog(chess_lib.Color.WHITE);
      if (promotion == null) return;
    }

    setState(() {
      final success = _chess.move({"from": from, "to": to, if (promotion != null) "promotion": promotion});
      if (success) {
        _lastMoveFrom = from;
        _lastMoveTo = to;
        if (_chess.game_over) {
          _showGameOver();
        } else {
          Timer(const Duration(milliseconds: 800), _makeMiniBotMove);
        }
      }
    });
  }

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
              child: const Text("RESTART", style: TextStyle(color: Color(0xFFE94560), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

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

  Widget _promotionOption(chess_lib.PieceType type, chess_lib.Color color, String code) {
    bool isWhite = color == chess_lib.Color.WHITE;
    String svg = "";
    switch (type) {
      case chess_lib.PieceType.QUEEN: svg = isWhite ? PieceSvg.wQ : PieceSvg.bQ; break;
      case chess_lib.PieceType.KNIGHT: svg = isWhite ? PieceSvg.wN : PieceSvg.bN; break;
      case chess_lib.PieceType.ROOK: svg = isWhite ? PieceSvg.wR : PieceSvg.bR; break;
      case chess_lib.PieceType.BISHOP: svg = isWhite ? PieceSvg.wB : PieceSvg.bB; break;
      default: break;
    }

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(code),
      child: Container(
        padding: const EdgeInsets.all(8),
        width: 54, height: 54,
        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
        child: SvgPicture.string(svg),
      ),
    );
  }

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

  void _resetWarmup() {
    setState(() {
      _chess = chess_lib.Chess();
      _selectedSquare = null;
      _possibleMovesData = [];
      _lastMoveFrom = null;
      _lastMoveTo = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isGameOver = _chess.game_over;
    return Scaffold(
      backgroundColor: const Color(0xFF262421),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                   const Text("Matching...", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                   const SizedBox(height: 8),
                   Text(
                     isGameOver ? "Warm up ended!" : "Warm up while you wait", 
                     style: TextStyle(color: isGameOver ? const Color(0xFFE94560) : Colors.white54, fontSize: 16),
                   ),
                ],
              ),
            ),
            Expanded(
              child: _buildBoard(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  const CircularProgressIndicator(color: Color(0xFFE94560)),
                  const SizedBox(height: 24),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(context),
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
              if (piece != null) Center(child: Padding(padding: const EdgeInsets.all(4), child: SvgPicture.string(_getSvgForPiece(piece)))),
              if (isPossible) Center(child: Container(width: 12, height: 12, decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle))),
            ],
          ),
        ),
      ),
    );
  }

  String _getSvgForPiece(chess_lib.Piece piece) {
    bool isW = piece.color == chess_lib.Color.WHITE;
    switch (piece.type) {
      case chess_lib.PieceType.PAWN: return isW ? PieceSvg.wP : PieceSvg.bP;
      case chess_lib.PieceType.ROOK: return isW ? PieceSvg.wR : PieceSvg.bR;
      case chess_lib.PieceType.KNIGHT: return isW ? PieceSvg.wN : PieceSvg.bN;
      case chess_lib.PieceType.BISHOP: return isW ? PieceSvg.wB : PieceSvg.bB;
      case chess_lib.PieceType.QUEEN: return isW ? PieceSvg.wQ : PieceSvg.bQ;
      case chess_lib.PieceType.KING: return isW ? PieceSvg.wK : PieceSvg.bK;
      default: return "";
    }
  }
}
