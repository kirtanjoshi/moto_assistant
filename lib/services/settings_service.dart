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
}
