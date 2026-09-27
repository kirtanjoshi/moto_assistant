import 'package:shared_preferences/shared_preferences.dart';

class MusicPlayerOption {
  final String name;
  final String packageName;
  final String description;

  const MusicPlayerOption({
    required this.name,
    required this.packageName,
    required this.description,
  });
}

class SettingsService {
  static const String _keyMusicPlayer = 'pref_default_music_player';

  static const List<MusicPlayerOption> availablePlayers = [
    MusicPlayerOption(
      name: 'MP3 Music Player',
      packageName: 'musicplayer.musicapps.music.mp3player',
      description: 'Your offline InShot MP3 Player',
    ),
    MusicPlayerOption(
      name: 'Spotify',
      packageName: 'com.spotify.music',
      description: 'Spotify Music & Podcasts',
    ),
    MusicPlayerOption(
      name: 'YouTube Music',
      packageName: 'com.google.android.apps.youtube.music',
      description: 'YouTube Music Player',
    ),
    MusicPlayerOption(
      name: 'VLC for Android',
      packageName: 'org.videolan.vlc',
      description: 'VLC Media Player',
    ),
    MusicPlayerOption(
      name: 'Samsung Music',
      packageName: 'com.samsung.android.music',
      description: 'Samsung Stock Music Player',
    ),
    MusicPlayerOption(
      name: 'System Prompt',
      packageName: 'system_prompt',
      description: 'Show Android app chooser dialog',
    ),
  ];

  static Future<String> getSelectedMusicPlayer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyMusicPlayer) ?? 'musicplayer.musicapps.music.mp3player';
    } catch (_) {
      return 'musicplayer.musicapps.music.mp3player';
    }
  }

  static Future<void> setSelectedMusicPlayer(String packageName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyMusicPlayer, packageName);
    } catch (_) {}
  }

  static const String _keyWakeThreshold = 'pref_wake_threshold';
  static const String _keyRidingMode = 'pref_riding_mode';
  // Rider's own tuned value: on the Nothing A059 real "Hey Jarvis" scores ranged 0.06-0.26, never near 0.5.
  // ponytail: one global value; a per-voice verifier model is the upgrade if false wakes become a problem.
  static const double defaultWakeThreshold = 0.025;

  static Future<double> getWakeThreshold() async =>
      (await SharedPreferences.getInstance()).getDouble(_keyWakeThreshold) ?? defaultWakeThreshold;

  static Future<void> setWakeThreshold(double value) async =>
      (await SharedPreferences.getInstance()).setDouble(_keyWakeThreshold, value);

  static Future<bool> getRidingMode() async =>
      (await SharedPreferences.getInstance()).getBool(_keyRidingMode) ?? true;

  static Future<void> setRidingMode(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_keyRidingMode, value);
}
