import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/websocket_service.dart';
import 'services/profile_service.dart';
import 'screens/main_menu.dart';
import 'screens/lobby.dart';
import 'screens/game_board.dart';
import 'screens/profile_setup_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final profileService = ProfileService();
  await profileService.init();

  runApp(
    Provider<WebSocketService>(
      create: (_) => WebSocketService(),
      dispose: (_, service) => service.dispose(),
      child: const ChessApp(),
    ),
  );
}

class ChessApp extends StatelessWidget {
  const ChessApp({super.key});

  @override
  Widget build(BuildContext context) {
    final profileService = ProfileService();
    
    return MaterialApp(
      title: 'Chess Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFFE94560),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE94560),
          secondary: Color(0xFFC0392B),
        ),
      ),
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
