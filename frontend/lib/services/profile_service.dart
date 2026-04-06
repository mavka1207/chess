import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../services/chess_pieces_svg.dart';

class ProfileService {
  static const String _keyDeviceId = 'device_id';
  static const String _keyNickname = 'nickname';
  static const String _keyAvatarIndex = 'avatar_index';

  static final ProfileService _instance = ProfileService._internal();
  factory ProfileService() => _instance;
  ProfileService._internal();

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    
    // Generate UUID if it doesn't exist
    if (_prefs.getString(_keyDeviceId) == null) {
      var uuid = const Uuid().v4();
      await _prefs.setString(_keyDeviceId, uuid);
    }
  }

  String get deviceId => _prefs.getString(_keyDeviceId) ?? '';
  
  String get nickname => _prefs.getString(_keyNickname) ?? '';
  set nickname(String value) => _prefs.setString(_keyNickname, value);

  int get avatarIndex => _prefs.getInt(_keyAvatarIndex) ?? 0;
  set avatarIndex(int value) => _prefs.setInt(_keyAvatarIndex, value);

  bool get isProfileSet => nickname.isNotEmpty;

  // List of available avatars using existing piece definitions
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

  String get avatarSvg => getAvailableAvatars()[avatarIndex];
}
