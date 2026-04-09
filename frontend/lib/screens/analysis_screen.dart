import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:chess/chess.dart' as chess_lib;
import '../services/chess_pieces_svg.dart';

class AnalysisScreen extends StatefulWidget {
  final List<String> fenHistory;
  final String moveHistory;
  final String myColor;

  const AnalysisScreen({
    super.key,
    required this.fenHistory,
    required this.moveHistory,
    required this.myColor,
  });

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  int _currentIndex = 0;
  late chess_lib.Chess _chess;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.fenHistory.length - 1;
    _chess = chess_lib.Chess.fromFEN(widget.fenHistory[_currentIndex]);
  }

  void _goToIndex(int index) {
    if (index >= 0 && index < widget.fenHistory.length) {
      setState(() {
        _currentIndex = index;
        _chess = chess_lib.Chess.fromFEN(widget.fenHistory[index]);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF262421),
      appBar: AppBar(
        title: const Text("Game Analysis"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          _buildBoard(),
          const SizedBox(height: 30),
          _buildControls(),
          Expanded(child: _MoveList(
            moveHistory: widget.moveHistory,
            currentIndex: _currentIndex,
            onMoveTap: _goToIndex,
          )),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.first_page, color: Colors.white70, size: 32),
          onPressed: () => _goToIndex(0),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white70, size: 32),
          onPressed: () => _goToIndex(_currentIndex - 1),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            "Move $_currentIndex / ${widget.fenHistory.length - 1}",
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, color: Colors.white70, size: 32),
          onPressed: () => _goToIndex(_currentIndex + 1),
        ),
        IconButton(
          icon: const Icon(Icons.last_page, color: Colors.white70, size: 32),
          onPressed: () => _goToIndex(widget.fenHistory.length - 1),
        ),
      ],
    );
  }

  Widget _buildBoard() {
    double size = MediaQuery.of(context).size.width - 32;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF33312E), width: 2),
      ),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
        itemCount: 64,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, index) {
          int row = index ~/ 8;
          int col = index % 8;
          
          String square;
          bool isDark;
          if (widget.myColor == "black") {
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
          
          final piece = _chess.get(square);
          return Container(
            color: isDark ? const Color(0xFFB58863) : const Color(0xFFF0D9B5),
            child: piece == null ? null : Padding(
              padding: const EdgeInsets.all(4.0),
              child: SvgPicture.string(_getSvgForPiece(piece)),
            ),
          );
        },
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
}

class _MoveList extends StatelessWidget {
  final String moveHistory;
  final int currentIndex;
  final Function(int) onMoveTap;

  const _MoveList({
    required this.moveHistory,
    required this.currentIndex,
    required this.onMoveTap,
  });

  @override
  Widget build(BuildContext context) {
    // Parse moves from history: "1. e4 e5 2. Nf3 Nc6"
    List<String> tokens = moveHistory.split(" ").where((s) => s.isNotEmpty).toList();
    List<Widget> chips = [];
    
    int moveIndex = 1; // 0 is start, 1 is after first move
    for (int i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (token.contains(".")) {
        // Just a move number, skip
      } else {
        final currentIdx = moveIndex;
        final bool isSelected = currentIndex == currentIdx;
        chips.add(
          GestureDetector(
            onTap: () => onMoveTap(currentIdx),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFE94560) : Colors.white10,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                token,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        );
        moveIndex++;
      }
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: SingleChildScrollView(
        child: Wrap(
          children: [
            GestureDetector(
              onTap: () => onMoveTap(0),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: currentIndex == 0 ? const Color(0xFFE94560) : Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text("Start", style: TextStyle(color: Colors.white70)),
              ),
            ),
            ...chips,
          ],
        ),
      ),
    );
  }
}
