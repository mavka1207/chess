part of 'game_board.dart';

// ─── DIALOGS ─────────────────────────────────────────────────────────────────

extension _GameBoardDialogs on _GameBoardScreenState {

  // ── Resign Confirmation Dialog ───────────────────────────────────────────
  void _showResignDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF262421),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Resign Party?", 
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
        ),
        content: const Text("Are you sure you want to admit defeat?", 
          style: TextStyle(color: Colors.white70)
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("NO", style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _wsService.sendMove("RESIGN");
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE94560),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("YES", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Promotion Dialog ─────────────────────────────────────────────────────
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
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            title: Column(
              children: [
                const Text(
                  "Promote Pawn", 
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                ),
                const SizedBox(height: 4),
                Text(
                  "Choose a piece to promote to:",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white54,   // ← dimmer color to feel secondary
                    fontSize: 14,            // ← smaller than the title
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
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

  // ── Game Over Dialog ───────────────────────────────────────────────────
  void _showGameOverDialog(String reason) {
    bool isVictory = false;
    bool isDraw = reason.contains("1/2-1/2");

    if (!isDraw) {
      if (reason.contains("1-0") || reason.contains("WhiteWon")) {
        isVictory = _myColor == "white";
      } else if (reason.contains("0-1") || reason.contains("BlackWon")) {
        isVictory = _myColor == "black";
      }
    }

    final String originalTitle =
        isDraw ? "Draw" : (isVictory ? "Victory!" : "You lost");

    final IconData originalIcon = isDraw
        ? Icons.handshake_outlined
        : (isVictory
            ? Icons.emoji_events
            : Icons.sentiment_very_dissatisfied);

    final Color originalMainColor = isDraw
        ? const Color(0xFFF1C40F)
        : (isVictory
            ? const Color(0xFF27AE60)
            : const Color(0xFFE94560));

    String originalFriendlyReason = "";
    String method = reason.split(" by ").last;

    if (isDraw) {
      originalFriendlyReason = "The game ended in a draw by $method";
    } else if (isVictory) {
      String opponentColor = _myColor == "white" ? "Black" : "White";
      originalFriendlyReason = "You defeated $opponentColor by $method";
    } else {
      String winnerColor = reason.contains("1-0") ? "White" : "Black";
      originalFriendlyReason = "$winnerColor wins by $method";
    }

    final bool abandonedBeforeStart = _opponentLeft && _moveHistory.isEmpty;
    final bool resignedMidGame = _opponentLeft && _moveHistory.isNotEmpty;

    final String title = resignedMidGame
        ? "Victory!"
        : abandonedBeforeStart
            ? "Opponent Left"
            : originalTitle;

    final String friendlyReason = resignedMidGame
        ? "Your opponent resigned."
        : abandonedBeforeStart
            ? "Your opponent left before the game started."
            : originalFriendlyReason;

    final Color mainColor = resignedMidGame
        ? const Color(0xFF27AE60)
        : abandonedBeforeStart
            ? const Color(0xFFE94560)
            : originalMainColor;

    final IconData icon = resignedMidGame
        ? Icons.emoji_events
        : abandonedBeforeStart
            ? Icons.exit_to_app
            : originalIcon;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, dialogSetState) {
          _dialogSetState = dialogSetState;
          return BackdropFilter(
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
                      ),
                    ),
                    if (_opponentWantsRematch && !_opponentLeft) ...[
                      const SizedBox(height: 16),
                      const Text(
                        "Opponent wants a rematch! \nPress REMATCH to accept.",
                        style: TextStyle(
                          color: Color(0xFFE94560),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _opponentLeft
                              ? Colors.white10
                              : const Color(0xFFE94560),
                          foregroundColor: _opponentLeft
                              ? Colors.white30
                              : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: _opponentLeft ? 0 : 8,
                          shadowColor: const Color(0xFFE94560).withValues(alpha: 0.4),
                        ),
                        onPressed: (_opponentLeft || _rematchRequestedByMe) ? null : () {
                          _wsService.sendMove("REMATCH");
                        },
                        child: Text(
                          _opponentLeft 
                            ? "OPPONENT LEFT" 
                            : _rematchRequestedByMe 
                              ? "PENDING..." 
                              : "REMATCH",
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF27AE60), width: 1.5),
                          foregroundColor: const Color(0xFF27AE60),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => AnalysisScreen(
                                fenHistory: _fenHistory,
                                moveHistory: _moveHistory,
                                myColor: _myColor,
                              ),
                            ),
                          );
                        },
                        child: const Text("ANALYZE"),
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: () {
                          _dialogSetState = null;
                          Navigator.of(context).popUntil((route) => route.isFirst);
                        },
                        child: const Text("MAIN MENU"),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}