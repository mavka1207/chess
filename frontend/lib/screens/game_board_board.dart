part of 'game_board.dart';

// ─── BOARD ───────────────────────────────────────────────────────────────────

extension _GameBoardBoard on _GameBoardScreenState {

  // ── Board Layout ──────────────────────────────────────────────────────────
  // Draws the grid
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

  // Draws each cell
  Widget _buildSquare(String square, bool isDark, int visualRow, int visualCol) {
    final isSelected = _selectedSquare == square;
    final isLastMove = square == _lastMoveFrom || square == _lastMoveTo;
    final isPossible = _possibleMoves.contains(square);
    final hasPieceOnTarget = _chess.get(square) != null;
    
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
          color: isSelected 
              ? Colors.orange.withValues(alpha: 0.5) 
              : (isLastMove ? Colors.yellow.withValues(alpha: 0.35) : Colors.transparent),
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
                          border: Border.all(color: Colors.orange, width: 4),
                        ),
                      )
                    : Container(
                        width: 12, height: 12,
                        decoration: BoxDecoration(
                          color: Colors.orange,
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

  // ── Piece Rendering ───────────────────────────────────────────────────────
  // Puts a piece on a cell
  Widget _buildPiece(String square) {
    final piece = _chess.get(square);
    if (piece == null) return const SizedBox();
    return _renderSvgPiece(piece);
  }

  // Converts piece → SVG widget
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

  // 	Maps piece type → SVG string
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

  // 	Renders a piece choice widget (uses _renderSvgPiece)
  Widget _promotionOption(chess_lib.PieceType type, chess_lib.Color color, String code) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(code),
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: _renderSvgPiece(chess_lib.Piece(type, color)),
        ),
      ),
    );
  }

  // Board utility used only inside board logic
  String _indexToSquare(int index) {
    int row = 7 - (index ~/ 8);
    int col = index % 8;
    return String.fromCharCode('a'.codeUnitAt(0) + col) + (row + 1).toString();
  }
}