import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:chess/chess.dart' as chess_lib;
import '../services/websocket_service.dart';

class GameBoardScreen extends StatefulWidget {
  const GameBoardScreen({super.key});

  @override
  State<GameBoardScreen> createState() => _GameBoardScreenState();
}

class _GameBoardScreenState extends State<GameBoardScreen> {
  late WebSocketService _wsService;
  late chess_lib.Chess _chess;
  String? _roomID;
  String _myColor = "";
  String _turn = "white";
  String? _selectedSquare;
  List<String> _possibleMoves = [];
  String? _lastMoveFrom;
  String? _lastMoveTo;
  String _moveHistory = "";

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
    _wsService.gameStream.listen((message) {
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

  void _onSquareTap(String square) {
    if (_turn != _myColor) return;

    setState(() {
      if (_selectedSquare == null) {
        // Select piece
        final piece = _chess.get(square);
        if (piece != null && piece.color == (_myColor == "white" ? chess_lib.Color.WHITE : chess_lib.Color.BLACK)) {
          _selectedSquare = square;
          _possibleMoves = _chess.moves({"square": square, "verbose": true}).map((m) => m["to"] as String).toList();
        }
      } else {
        // Try move
        if (_possibleMoves.contains(square)) {
          final moveStr = "$_selectedSquare$square";
          _wsService.sendMove(moveStr);
          _selectedSquare = null;
          _possibleMoves = [];
        } else {
          // Deselect or select another piece
          final piece = _chess.get(square);
          if (piece != null && piece.color == (_myColor == "white" ? chess_lib.Color.WHITE : chess_lib.Color.BLACK)) {
            _selectedSquare = square;
            _possibleMoves = _chess.moves({"square": square, "verbose": true}).map((m) => m["to"] as String).toList();
          } else {
            _selectedSquare = null;
            _possibleMoves = [];
          }
        }
      }
    });
  }

  void _showGameOver(String reason) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Game Over"),
        content: Text(reason),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text("EXIT"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: Text("Room: $_roomID ($_myColor)"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            tooltip: "Restart Game",
            onPressed: () {
              _wsService.sendMove("RESTART"); // Overusing sendMove for command
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildPlayerInfo(_myColor == "white" ? "Opponent (Black)" : "Opponent (White)", _turn != _myColor),
            const Spacer(),
            Column(
              children: [
                _buildCapturedPieces(_myColor == "white" ? chess_lib.Color.WHITE : chess_lib.Color.BLACK),
                const SizedBox(height: 12),
                _buildBoard(),
                const SizedBox(height: 12),
                _buildCapturedPieces(_myColor == "white" ? chess_lib.Color.BLACK : chess_lib.Color.WHITE),
              ],
            ),
            const SizedBox(height: 20),
            _buildMoveHistory(),
            const Spacer(),
            _buildPlayerInfo("You ($_myColor)", _turn == _myColor),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildCapturedPieces(chess_lib.Color colorOfCaptured) {
    // Standard set of pieces
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

    // Count pieces on board
    for (var i = 0; i < 64; i++) {
      final piece = _chess.get(_indexToSquare(i));
      if (piece != null && piece.color == colorOfCaptured) {
        if (currentCounts.containsKey(piece.type)) {
          currentCounts[piece.type] = currentCounts[piece.type]! + 1;
        }
      }
    }

    List<Widget> capturedWidgets = [];
    initialCounts.forEach((type, initialCount) {
      int capturedCount = initialCount - currentCounts[type]!;
      for (int i = 0; i < initialCount; i++) {
        bool isCaptured = i < capturedCount;
        if (isCaptured) {
          capturedWidgets.add(
            SizedBox(
              width: 20,
              height: 20,
              child: _renderPiece(chess_lib.Piece(type, colorOfCaptured), 18),
            ),
          );
        } else {
          capturedWidgets.add(
            Opacity(
              opacity: 0.1,
              child: SizedBox(
                width: 20,
                height: 20,
                child: _renderPiece(chess_lib.Piece(type, colorOfCaptured), 18),
              ),
            ),
          );
        }
      }
    });

    return Container(
      width: MediaQuery.of(context).size.width - 32,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Wrap(
          spacing: 2,
          children: capturedWidgets,
        ),
      ),
    );
  }

  String _indexToSquare(int index) {
    int row = 7 - (index ~/ 8);
    int col = index % 8;
    return String.fromCharCode('a'.codeUnitAt(0) + col) + (row + 1).toString();
  }

  Widget _buildPlayerInfo(String label, bool isTurn) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: isTurn ? const Color(0xFFE94560).withOpacity(0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isTurn) const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(Icons.timer, color: Color(0xFFE94560), size: 16),
          ),
          Text(
            label,
            style: TextStyle(
              color: isTurn ? const Color(0xFFE94560) : Colors.white70,
              fontWeight: isTurn ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoard() {
    double size = MediaQuery.of(context).size.width - 32;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white24, width: 4),
      ),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
        itemCount: 64,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, index) {
          int row = index ~/ 8;
          int col = index % 8;
          
          if (_myColor == "black") {
            // Black perspective: Top-left is h1, Bottom-right is a8
            // Index 0 -> row 0, col 7 (h1)
            // Index 63 -> row 7, col 0 (a8)
            int flippedRow = row; 
            int flippedCol = 7 - col;
            final square = "${String.fromCharCode(97 + flippedCol)}${flippedRow + 1}";
            return _buildSquare(square, (flippedRow + flippedCol) % 2 == 0);
          } else {
            // White perspective: Top-left is a8, Bottom-right is h1
            // Index 0 -> row 7, col 0 (a8)
            // Index 63 -> row 0, col 7 (h1)
            int flippedRow = 7 - row;
            int flippedCol = col;
            final square = "${String.fromCharCode(97 + flippedCol)}${flippedRow + 1}";
            return _buildSquare(square, (flippedRow + flippedCol) % 2 == 0);
          }
        },
      ),
    );
  }

  Widget _buildSquare(String square, bool isDark) {
    final isSelected = _selectedSquare == square;
    final isPossible = _possibleMoves.contains(square);
    final isLastMove = square == _lastMoveFrom || square == _lastMoveTo;

    return GestureDetector(
      onTap: () {
        if (isPossible) HapticFeedback.lightImpact();
        _onSquareTap(square);
      },
      child: Container(
        color: isSelected 
          ? Colors.yellow.withOpacity(0.5) 
          : isPossible 
            ? Colors.green.withOpacity(0.5)
            : isLastMove
              ? Colors.blue.withOpacity(0.3)
              : (isDark ? const Color(0xFFB58863) : const Color(0xFFF0D9B5)),
        child: _buildPiece(square),
      ),
    );
  }


  Widget _buildPiece(String square, {double size = 32}) {
    final piece = _chess.get(square);
    if (piece == null) return const SizedBox();
    return _renderPiece(piece, size);
  }

  Widget _renderPiece(chess_lib.Piece piece, double size) {
    bool isWhitePiece = piece.color == chess_lib.Color.WHITE;
    return Center(
      child: Text(
        _getPieceSymbol(piece.type, isWhitePiece),
        style: TextStyle(
          fontSize: size,
          color: isWhitePiece ? Colors.white : Colors.black,
          shadows: [
            Shadow(
              color: isWhitePiece ? Colors.black.withOpacity(0.5) : Colors.white.withOpacity(0.3),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }

  String _getPieceSymbol(chess_lib.PieceType type, bool isWhite) {
    if (isWhite) {
      switch (type) {
        case chess_lib.PieceType.PAWN: return "♙";
        case chess_lib.PieceType.ROOK: return "♖";
        case chess_lib.PieceType.KNIGHT: return "♘";
        case chess_lib.PieceType.BISHOP: return "♗";
        case chess_lib.PieceType.QUEEN: return "♕";
        case chess_lib.PieceType.KING: return "♔";
        default: return "";
      }
    } else {
      switch (type) {
        case chess_lib.PieceType.PAWN: return "♟";
        case chess_lib.PieceType.ROOK: return "♜";
        case chess_lib.PieceType.KNIGHT: return "♞";
        case chess_lib.PieceType.BISHOP: return "♝";
        case chess_lib.PieceType.QUEEN: return "♛";
        case chess_lib.PieceType.KING: return "♚";
        default: return "";
      }
    }
  }

  Widget _buildMoveHistory() {
    return Container(
      width: MediaQuery.of(context).size.width - 32,
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(
            _moveHistory.isEmpty ? "No moves yet" : _moveHistory,
            style: const TextStyle(
              color: Colors.white70,
              fontFamily: 'monospace',
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}
