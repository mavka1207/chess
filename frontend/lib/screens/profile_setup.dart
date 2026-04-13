// Widget → Controllers & Services → Profile State → Lifecycle → Actions → Build

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/profile_service.dart';

// ─── Widget ───────────────────────────────────────────────────────────────────

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

// ─── Widget ───────────────────────────────────────────────────────────────────

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {

  // ── Controllers & Services ───────────────────
  final TextEditingController _nicknameController = TextEditingController();
  final ProfileService _profileService = ProfileService();

  // ── Profile State ────────────────────────────
  int _selectedAvatarIndex = 0;

  // ── Lifecycle ─────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Pre-fill with existing profile data so returning users see their current settings
    _nicknameController.text = _profileService.nickname;
    _selectedAvatarIndex = _profileService.avatarIndex;
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────────────

  // Validates, saves the profile, and navigates to the main menu
  void _saveProfile() {
    final nickname = _nicknameController.text.trim();

    if (nickname.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a nickname'),
        duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    _profileService.nickname = nickname;
    _profileService.avatarIndex = _selectedAvatarIndex;
    
    Navigator.pushReplacementNamed(context, '/');
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

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

              // ── Page title ───────────────────────────────────────────────
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
              
              // ── Nickname input ────────────────────────────────────────────  
              TextField(
                controller: _nicknameController,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: InputDecoration(
                  labelText: 'ENTER NICKNAME',
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

              // ── Avatar selection label ────────────────────────────────────────────
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
              
              // ── Avatar grid ───────────────────────────────────────────────
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
              
              // ── Save button ───────────────────────────────────────────────              
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
