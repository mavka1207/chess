import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/websocket_service.dart';
import 'services/profile_service.dart';
import 'screens/main_menu.dart';
import 'screens/lobby.dart';
import 'screens/game_board.dart';
import 'screens/profile_setup.dart';

// ── Entry Point ───────────────────────────────────────────────────────────────
void main() async {
  // Required before any async work in main()
  WidgetsFlutterBinding.ensureInitialized();
    
  // Load profile from storage before the app renders
  await ProfileService().init();

  runApp(
    // WebSocketService is provided globally so any screen can access it
    Provider<WebSocketService>(
      create: (_) => WebSocketService(),
      dispose: (_, service) => service.dispose(),
      child: const ChessApp(),
    ),
  );
}

// ── App ───────────────────────────────────────────────────────────────────────

class ChessApp extends StatelessWidget {
  const ChessApp({super.key});

  @override
  Widget build(BuildContext context) {
    final profileService = ProfileService();
    
    return MaterialApp(
      title: 'Chess Mobile',
      debugShowCheckedModeBanner: false,

      // ── Theme ──────────────────────────────────────────────────────────────
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFFE94560),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE94560),
          secondary: Color(0xFFC0392B),
        ),
      ),

      // ── Routing ────────────────────────────────────────────────────────────
      // Send new players to setup; returning players go straight to main menu
      initialRoute: profileService.isProfileSet ? '/' : '/setup',
      routes: {
        '/': (context) => const MainMenuScreen(),
        '/setup': (context) => const ProfileSetupScreen(),
        '/lobby': (context) => const LobbyScreen(),
        '/game': (context) => const GameBoardScreen(),
      },
    );
  }
}
