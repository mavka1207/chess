// Widget → State → Lifecycle → Navigation → Build → Board → Controls

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:chess/chess.dart' as chess_lib;
import '../services/chess_pieces_svg.dart';

// ─── Widget ───────────────────────────────────────────────────────────────────

class AnalysisScreen extends StatefulWidget {
  final List<String> fenHistory;  // All board positions from the game
  final String moveHistory;       // Full move list string e.g. "1. e4 e5 2. Nf3"
  final String myColor;           // Used to flip the board for black players

  const AnalysisScreen({
    super.key,
    required this.fenHistory,
    required this.moveHistory,
    required this.myColor,
  });

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

// ─── State ────────────────────────────────────────────────────────────────────

class _AnalysisScreenState extends State<AnalysisScreen> {

  // ── Analysis State ───────────────────────────
  int _currentIndex = 0;        // Which position in fenHistory we are viewing
  late chess_lib.Chess _chess;  // Chess engine loaded with the current position
  final ScrollController _scrollController = ScrollController();

  // ── Lifecycle ─────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _currentIndex = widget.fenHistory.length - 1;
    _chess = chess_lib.Chess.fromFEN(widget.fenHistory[_currentIndex]);
  }

  @override
  void dispose() {  
    _scrollController.dispose();
    super.dispose();
  }

  // ── Navigation ────────────────────────────────────────────────────────────────

  // Jumps to a specific move by index and reloads the board position
  void _goToIndex(int index) {
    debugPrint('🔍 _goToIndex called: index=$index, fenHistory.length=${widget.fenHistory.length}');
    if (index >= 0 && index < widget.fenHistory.length) {
      setState(() {
        // Start at the final position of the game
        _currentIndex = index;
        _chess = chess_lib.Chess.fromFEN(widget.fenHistory[index]);
      });
    } 
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

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

          // ── Board at the selected position ────────────────
          _buildBoard(),
          const SizedBox(height: 30),

          // ── Prev / Next controls ──────────────────────────
          _buildControls(),

          // ── Scrollable move list ──────────────────────────
          Expanded(child: _MoveHistoryList(
            moveHistory: widget.moveHistory,
            currentIndex: _currentIndex,
            onMoveTap: _goToIndex,
            totalMoves: widget.fenHistory.length - 1,
          )),
        ],
      ),
    );
  }

  // ── Board Widget ──────────────────────────────────────────────────────────────

  // Renders the board for the currently selected position
  Widget _buildBoard() {
    final double size = MediaQuery.of(context).size.width - 32;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF33312E), width: 2),
      ),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
        ),
        itemCount: 64,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, index) {
          final int row = index ~/ 8;
          final int col = index % 8;

          String square;
          bool isDark;
          int fRow, fCol;

          // Flip board orientation for black players
          if (widget.myColor == "black") {
            fRow = row;
            fCol = 7 - col;
            square = "${String.fromCharCode(97 + fCol)}${fRow + 1}";
            isDark = (fRow + fCol) % 2 == 0;
          } else {
            fRow = 7 - row;
            fCol = col;
            square = "${String.fromCharCode(97 + fCol)}${fRow + 1}";
            isDark = (fRow + fCol) % 2 == 0;
          }

          final piece = _chess.get(square);
          final Color labelColor = isDark
              ? const Color(0xFFF0D9B5)
              : const Color(0xFFB58863);

          return Container(
            color: isDark
                ? const Color(0xFFB58863)
                : const Color(0xFFF0D9B5),
            child: Stack(
              children: [

                // Rank number — left edge, only on col 0
                if (col == 0)
                  Positioned(
                    top: 2,
                    left: 2,
                    child: Text(
                      "${fRow + 1}",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: labelColor,
                      ),
                    ),
                  ),

                // File letter — bottom edge, only on last row
                if (row == 7)
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Text(
                      String.fromCharCode(97 + fCol),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: labelColor,
                      ),
                    ),
                  ),

                // Chess piece
                if (piece != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: SvgPicture.string(PieceSvg.getSvgForPiece(piece)),
                    ),
                  ),

              ],
            ),
          );
        },
      ),
    );
  }
  
  // ── Controls Widget ───────────────────────────────────────────────────────────

  // Navigation bar: jump to start, step back, move counter, step forward, jump to end
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
}

// ─── Move List Widget ─────────────────────────────────────────────────────────

// Displays all moves as tappable chips; highlights the currently viewed move
class _MoveHistoryList extends StatelessWidget {
  final String moveHistory;
  final int currentIndex;
  final Function(int) onMoveTap;
  final int totalMoves;

  const _MoveHistoryList({
    required this.moveHistory,
    required this.currentIndex,
    required this.onMoveTap,
    required this.totalMoves,
  });

  @override
  Widget build(BuildContext context) {
    // Tokenize the move string — skip move numbers like "1.", "2.", etc.
    final List<String> tokens = moveHistory
      .split(" ")
      .where((s) => s.isNotEmpty && !s.contains("."))
      .toList();

    debugPrint('🔍 tokens: $tokens');
    
    // Build a chip for each move; moveIndex starts at 1 (0 = starting position)
    final List<Widget> chips = [];
    int moveIndex = 1; 

    for (final token in tokens) {
      // Stop if we exceed the number of recorded board positions
      if (moveIndex > totalMoves) break;

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
