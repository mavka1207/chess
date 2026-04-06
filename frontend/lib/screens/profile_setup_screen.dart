import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/profile_service.dart';
import '../services/chess_pieces_svg.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final TextEditingController _nicknameController = TextEditingController();
  int _selectedAvatarIndex = 0;
  final ProfileService _profileService = ProfileService();

  @override
  void initState() {
    super.initState();
    _nicknameController.text = _profileService.nickname;
    _selectedAvatarIndex = _profileService.avatarIndex;
  }

  void _saveProfile() {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a nickname')),
      );
      return;
    }

    _profileService.nickname = nickname;
    _profileService.avatarIndex = _selectedAvatarIndex;
    
    Navigator.pushReplacementNamed(context, '/');
  }

  @override
  Widget build(BuildContext context) {
    final avatars = ProfileService.getAvailableAvatars();

    return Scaffold(
      backgroundColor: const Color(0xFF1B1A17),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              const Text(
                'PROFILE SETUP',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose your identity',
                style: TextStyle(color: Colors.white54, fontSize: 16),
              ),
              const SizedBox(height: 48),
              
              // Nickname Input
              TextField(
                controller: _nicknameController,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: InputDecoration(
                  labelText: 'NICKNAME',
                  labelStyle: const TextStyle(color: Color(0xFFE94560)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Colors.white10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFE94560)),
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                ),
              ),
              
              const SizedBox(height: 40),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'SELECT AVATAR',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Avatar Grid
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: avatars.length,
                  itemBuilder: (context, index) {
                    final isSelected = _selectedAvatarIndex == index;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedAvatarIndex = index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: isSelected 
                              ? const Color(0xFFE94560).withValues(alpha: 0.2) 
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? const Color(0xFFE94560) : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: SvgPicture.string(avatars[index]),
                      ),
                    );
                  },
                ),
              ),
              
              // Save Button
              Padding(
                padding: const EdgeInsets.only(bottom: 24.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE94560),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 8,
                      shadowColor: const Color(0xFFE94560).withValues(alpha: 0.4),
                    ),
                    child: const Text(
                      'START PLAYING',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
