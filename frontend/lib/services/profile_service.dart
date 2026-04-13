import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../services/chess_pieces_svg.dart';

class ProfileService {

  // ── Storage Keys ──────────────────────────────────────────────────────────────

  static const String _keyDeviceId = 'device_id';
  static const String _keyNickname = 'nickname';
  static const String _keyAvatarIndex = 'avatar_index';

  // ── Singleton ─────────────────────────────────────────────────────────────────

  // Single instance shared across the entire app — profile data is global
  static final ProfileService _instance = ProfileService._internal();
  factory ProfileService() => _instance;
  ProfileService._internal();

  // ── Storage ───────────────────────────────────────────────────────────────────
  late SharedPreferences _prefs;

  // ── Initialization ────────────────────────────────────────────────────────────

  // Must be called once at app startup before any profile data is accessed
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    
    // Generate a unique device ID on first launch — never changes after that
    if (_prefs.getString(_keyDeviceId) == null) {
      final uuid = const Uuid().v4();
      await _prefs.setString(_keyDeviceId, uuid);
    }
  }

  // ── Profile Properties ────────────────────────────────────────────────────────

  // Unique device identifier — used to recognize the player on the server
  String get deviceId => _prefs.getString(_keyDeviceId) ?? '';
  
  // Player's display name — shown to opponents and in the lobby
  String get nickname => _prefs.getString(_keyNickname) ?? '';
  set nickname(String value) => _prefs.setString(_keyNickname, value);

  // Index into getAvailableAvatars() — determines which piece icon is shown
  int get avatarIndex => _prefs.getInt(_keyAvatarIndex) ?? 0;
  set avatarIndex(int value) => _prefs.setInt(_keyAvatarIndex, value);

  // Returns true if the player has completed profile setup
  bool get isProfileSet => nickname.isNotEmpty;

  // Convenience getter — returns the SVG string for the player's chosen avatar
  String get avatarSvg => getAvailableAvatars()[avatarIndex];

  // ── Avatars ───────────────────────────────────────────────────────────────────

  // Returns the list of selectable avatar SVGs — reuses chess piece artwork
  static List<String> getAvailableAvatars() => [
    PieceSvg.wK,
    PieceSvg.wQ,
    PieceSvg.wN,
    PieceSvg.wB,
    PieceSvg.wR,
    PieceSvg.bK,
    PieceSvg.bQ,
    PieceSvg.bN,
    PieceSvg.bB,
    PieceSvg.bR,
  ];
}
