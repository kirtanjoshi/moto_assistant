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

  // openWakeWord is the default: it is the only engine that has detected the rider's voice on the phone.
  // Sherpa never fired on-device (models work offline on PC) — kept as experimental until that is solved.
  static const String defaultWakeEngine = 'oww';
  static const Map<String, String> wakeEngines = {
    'oww': 'openWakeWord (recommended)',
    'sherpa_phone': 'Sherpa - phonemes (experimental)',
    'sherpa_giga': 'Sherpa - GigaSpeech (experimental)',
  };

  // openWakeWord: real "Hey Jarvis" scored 0.03-0.26 on the Nothing A059, never near its 0.5 default.
  // Sherpa: 0.25 is the library's own default trigger threshold.
  static double defaultWakeThreshold(String engine) => engine == 'oww' ? 0.025 : 0.25;

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
