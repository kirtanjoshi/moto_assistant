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

  static const String _keyRidingMode = 'pref_riding_mode';
  static const String _keyWakeEngine = 'pref_wake_engine';

  // Sherpa GigaSpeech "Hey Moto" is what the rider validated on the phone: foreground, background,
  // chair distance and through the helmet intercom mic.
  static const String defaultWakeEngine = 'sherpa_giga';
  static const Map<String, String> wakeEngines = {
    'sherpa_giga': 'Sherpa - GigaSpeech, "Hey Moto" (recommended)',
    'sherpa_phone': 'Sherpa - phonemes (experimental)',
    'oww': 'openWakeWord, "Hey Jarvis" (old)',
  };

  // openWakeWord: real "Hey Jarvis" scored 0.03-0.26 on the Nothing A059, never near its 0.5 default.
  // Sherpa GigaSpeech: 0.10 caught every "Hey Moto" in recordings with no false wakes (Hey Moto adds +0.10).
  static double defaultWakeThreshold(String engine) => switch (engine) {
        'oww' => 0.025,
        'sherpa_giga' => 0.10,
        _ => 0.25,
      };

  // openWakeWord only ships a "Hey Jarvis" model; "Hey Moto" is the phrase the rider's voice reliably triggers on Sherpa.
  static String wakePhrase(String engine) => engine == 'oww' ? 'Hey Jarvis' : 'Hey Moto';

  static Future<String> getWakeEngine() async =>
      (await SharedPreferences.getInstance()).getString(_keyWakeEngine) ?? defaultWakeEngine;

  static Future<void> setWakeEngine(String engine) async =>
      (await SharedPreferences.getInstance()).setString(_keyWakeEngine, engine);

  static Future<double> getWakeThreshold(String engine) async =>
      (await SharedPreferences.getInstance()).getDouble('pref_wake_threshold_$engine') ??
      defaultWakeThreshold(engine);

  static Future<void> setWakeThreshold(String engine, double value) async =>
      (await SharedPreferences.getInstance()).setDouble('pref_wake_threshold_$engine', value);

  static const String _keyCallingSim = 'pref_calling_sim';

  /// SIM label used for voice calls ("Ncell"), or null to let Android decide / ask.
  static Future<String?> getCallingSim() async =>
      (await SharedPreferences.getInstance()).getString(_keyCallingSim);

  static Future<void> setCallingSim(String? sim) async {
    final prefs = await SharedPreferences.getInstance();
    sim == null ? await prefs.remove(_keyCallingSim) : await prefs.setString(_keyCallingSim, sim);
  }

  static Future<bool> getRidingMode() async =>
      (await SharedPreferences.getInstance()).getBool(_keyRidingMode) ?? true;

  static Future<void> setRidingMode(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_keyRidingMode, value);
}
