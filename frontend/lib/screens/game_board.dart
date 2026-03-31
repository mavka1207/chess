import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:chess/chess.dart' as chess_lib;
import 'package:flutter_svg/flutter_svg.dart';
import '../services/websocket_service.dart';
import '../services/chess_pieces_svg.dart';

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
  String _moveHistory = "";
  String? _assignedColor;
  bool _isInitialized = false;

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
    if (_isInitialized) return;
    _isInitialized = true;
    
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
    String wsUrl = 'ws://192.168.1.57:8080/rooms/$_roomID';
    if (_assignedColor != null) {
      wsUrl += '?color=$_assignedColor';
    }
    _wsService.connectToGame(wsUrl);
    _chess = chess_lib.Chess();
  }

  void _setupListeners() {
    _gameSubscription = _wsService.gameStream.listen((message) {
      if (mounted) {
        setState(() {
          if (message == "white" || message == "black") {
            _myColor = message;
          } else if (message.startsWith("BOARD:")) {
            final parts = message.split(":");
            final fen = parts[1];
            _chess.load(fen);
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
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
            _moveHistory = "";
            _lastMoveFrom = null;
            _lastMoveTo = null;
            _selectedSquare = null;
            _possibleMoves = [];
            HapticFeedback.vibrate();
          } else if (message.startsWith("TURN:")) {
            _turn = message.substring(5);
          } else if (message.startsWith("GAMEOVER:")) {
            _showGameOver(message.substring(9));
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
          final moveStr = "$_selectedSquare$square";
          _wsService.sendMove(moveStr);
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

  void _showGameOver(String reason) {
    bool isVictory = false;
    bool isDraw = reason.contains("1/2-1/2");
    
    if (!isDraw) {
      if (reason.contains("1-0")) {
        isVictory = _myColor == "white";
      } else if (reason.contains("0-1")) {
        isVictory = _myColor == "black";
      }
    }

    final String title = isDraw ? "Draw" : (isVictory ? "Victory!" : "Defeat");
    final IconData icon = isDraw 
        ? Icons.handshake_outlined 
        : (isVictory ? Icons.emoji_events : Icons.sentiment_very_dissatisfied);
    final Color mainColor = isDraw 
        ? const Color(0xFFF1C40F) // Yellow for draw
        : (isVictory ? const Color(0xFF27AE60) : const Color(0xFFE94560)); // Green for win, Pink/Red for loss

    // Friendly reason text
    String friendlyReason = reason;
    if (reason.contains("1-0")) friendlyReason = reason.replaceFirst("1-0", "White Wins");
    if (reason.contains("0-1")) friendlyReason = reason.replaceFirst("0-1", "Black Wins");
    if (reason.contains("1/2-1/2")) friendlyReason = reason.replaceFirst("1/2-1/2", "Draw");

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          backgroundColor: const Color(0xFF262421).withValues(alpha: 0.95),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: mainColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon, 
                    size: 48, 
                    color: mainColor,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  title, 
                  style: TextStyle(
                    fontSize: 28, 
                    fontWeight: FontWeight.bold, 
                    color: mainColor,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  friendlyReason, 
                  textAlign: TextAlign.center, 
                  style: const TextStyle(
                    fontSize: 16, 
                    color: Colors.white70,
                    height: 1.4,
                  )
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF27AE60), // Match success green
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      textStyle: const TextStyle(
                        fontSize: 16, 
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    onPressed: () {
                      _wsService.sendMove("RESTART");
                    },
                    child: const Text("REMATCH"),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                      foregroundColor: Colors.white70,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      textStyle: const TextStyle(
                        fontSize: 16, 
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    child: const Text("MAIN MENU"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isWhite = _myColor == "white" || _myColor == "";
    return Scaffold(
      backgroundColor: const Color(0xFF262421),
      appBar: AppBar(
        title: Text(
          (_roomID != null && _roomID!.length == 6) 
            ? "Chess [$_roomID]" 
            : "Chess"
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
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
    final String label = isMe ? "You" : "Opponent";
    
    // Calculate captured pieces
    Map<chess_lib.PieceType, int> captured = _getCapturedPieces(color == "white" ? chess_lib.Color.BLACK : chess_lib.Color.WHITE);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isMyTurn ? Colors.white.withValues(alpha: 0.05) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.grey[800],
            radius: 20,
            child: Icon(Icons.person, color: isMe ? const Color(0xFFE94560) : Colors.white70),
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

  Widget _buildBoard() {
    double size = MediaQuery.of(context).size.width - 32;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF33312E), width: 2),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 5),
        ],
      ),
      child: Stack(
        children: [
          GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
            itemCount: 64,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (context, index) {
              int row = index ~/ 8;
              int col = index % 8;
              
              String square;
              bool isDark;
              if (_myColor == "black") {
                int fRow = row; 
                int fCol = 7 - col;
                square = "${String.fromCharCode(97 + fCol)}${fRow + 1}";
                isDark = (fRow + fCol) % 2 == 0;
              } else {
                int fRow = 7 - row;
                int fCol = col;
                square = "${String.fromCharCode(97 + fCol)}${fRow + 1}";
                isDark = (fRow + fCol) % 2 == 0;
              }
              return _buildSquare(square, isDark, row, col);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSquare(String square, bool isDark, int visualRow, int visualCol) {
    final isSelected = _selectedSquare == square;
    final isPossible = _possibleMoves.contains(square);
    final hasPieceOnTarget = _chess.get(square) != null;
    
    // Wood palette
    final darkColor = const Color(0xFFB58863);
    final lightColor = const Color(0xFFF0D9B5);

    return GestureDetector(
      onTap: () {
        if (isPossible) HapticFeedback.lightImpact();
        _onSquareTap(square);
      },
      child: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: isDark ? _darkSquareImg : _lightSquareImg,
            fit: BoxFit.cover,
          ),
        ),
        child: Container(
          color: isSelected ? Colors.yellow.withValues(alpha: 0.4) : Colors.transparent,
          child: Stack(
            children: [
              // Coordinates labels on specific squares
              if (visualCol == 0) 
                Positioned(
                  top: 2, left: 2,
                  child: Text(
                    _myColor == "black" ? "${visualRow + 1}" : "${8 - visualRow}",
                    style: TextStyle(fontSize: 10, color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold),
                  ),
                ),
              if (visualRow == 7)
                Positioned(
                  bottom: 2, right: 2,
                  child: Text(
                    _myColor == "black" ? String.fromCharCode(104 - visualCol) : String.fromCharCode(97 + visualCol),
                    style: TextStyle(fontSize: 10, color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold),
                  ),
                ),
              
              // Piece
              Center(child: RepaintBoundary(child: _buildPiece(square))),

              // Possible move dot or ring
              if (isPossible)
                Center(
                  child: hasPieceOnTarget
                    ? Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black.withValues(alpha: 0.2), width: 4),
                        ),
                      )
                    : Container(
                        width: 12, height: 12,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                      ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPiece(String square) {
    final piece = _chess.get(square);
    if (piece == null) return const SizedBox();
    return _renderSvgPiece(piece);
  }

  Widget _renderSvgPiece(chess_lib.Piece piece, {bool isSmall = false}) {
    String svgCode = _getSvgForPiece(piece);
    return Padding(
      padding: EdgeInsets.all(isSmall ? 1.0 : 4.0),
      child: SvgPicture.string(
        svgCode,
        placeholderBuilder: (BuildContext context) => Container(
          padding: const EdgeInsets.all(10.0),
          child: const CircularProgressIndicator(),
        ),
      ),
    );
  }

  String _getSvgForPiece(chess_lib.Piece piece) {
    final isWhite = piece.color == chess_lib.Color.WHITE;
    switch (piece.type) {
      case chess_lib.PieceType.PAWN: return isWhite ? PieceSvg.wP : PieceSvg.bP;
      case chess_lib.PieceType.ROOK: return isWhite ? PieceSvg.wR : PieceSvg.bR;
      case chess_lib.PieceType.KNIGHT: return isWhite ? PieceSvg.wN : PieceSvg.bN;
      case chess_lib.PieceType.BISHOP: return isWhite ? PieceSvg.wB : PieceSvg.bB;
      case chess_lib.PieceType.QUEEN: return isWhite ? PieceSvg.wQ : PieceSvg.bQ;
      case chess_lib.PieceType.KING: return isWhite ? PieceSvg.wK : PieceSvg.bK;
      default: return "";
    }
  }

  String _indexToSquare(int index) {
    int row = 7 - (index ~/ 8);
    int col = index % 8;
    return String.fromCharCode('a'.codeUnitAt(0) + col) + (row + 1).toString();
  }
}
