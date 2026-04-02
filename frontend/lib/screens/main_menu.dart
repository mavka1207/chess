import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_svg/flutter_svg.dart';
import '../services/chess_pieces_svg.dart';

class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({super.key});

  final String baseUrl = 'https://colory-kaci-dreadingly.ngrok-free.dev';

  Future<void> _createRoom(BuildContext context) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/create'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final roomID = data['roomID'];
        if (context.mounted) {
          Navigator.pushNamed(context, '/game', arguments: roomID);
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating room: $e')),
        );
      }
    }
  }

  Future<void> _startPractice(BuildContext context) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/practice'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final roomID = data['roomID'];
        if (context.mounted) {
          Navigator.pushNamed(context, '/game', arguments: roomID);
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting practice: $e')),
        );
      }
    }
  }

  void _showJoinDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('JOIN PRIVATE GAME'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Enter Room Code'),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () {
              final code = controller.text.trim().toUpperCase();
              if (code.isNotEmpty) {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/game', arguments: code);
              }
            },
            child: const Text('JOIN'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF262421), Color(0xFF21201D)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white10, width: 1),
                    ),
                    child: SvgPicture.string(
                      PieceSvg.wP,
                      width: 80,
                      height: 80,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'CHESS',
                    style: TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 12,
                    ),
                  ),
                  const SizedBox(height: 48),
                  _MenuButton(
                    title: 'PUBLIC MATCH',
                    onPressed: () => Navigator.pushNamed(context, '/lobby'),
                  ),
                  const SizedBox(height: 16),
                  _MenuButton(
                    title: 'CREATE PRIVATE',
                    onPressed: () => _createRoom(context),
                  ),
                  const SizedBox(height: 16),
                  _MenuButton(
                    title: 'JOIN PRIVATE',
                    onPressed: () => _showJoinDialog(context),
                  ),
                  const SizedBox(height: 16),
                  _MenuButton(
                    title: 'PLAY BOT',
                    onPressed: () => _startPractice(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final String title;
  final VoidCallback onPressed;

  const _MenuButton({required this.title, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [Color(0xFF27AE60), Color(0xFF1E8449)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF27AE60).withValues(alpha: 0.2),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
