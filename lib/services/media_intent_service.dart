import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'settings_service.dart';

class MediaIntentService {
  static const MethodChannel _channel = MethodChannel('com.motovoice.moto_assistant/media_control');

  static String? _knownPackage(String lowerApp) {
    if (lowerApp.contains('spotify')) return 'com.spotify.music';
    if (lowerApp.contains('youtube') || lowerApp.contains('yt')) return 'com.google.android.apps.youtube.music';
    if (lowerApp.contains('vlc')) return 'org.videolan.vlc';
    if (lowerApp.contains('mp3') || lowerApp.contains('music player') || lowerApp.contains('player')) {
      return 'musicplayer.musicapps.music.mp3player';
    }
    return null;
  }

  static Future<String?> _savedPlayer() async {
    final saved = await SettingsService.getSelectedMusicPlayer();
    return saved == 'system_prompt' ? null : saved;
  }

  Future<bool> playMedia({required String query, String? targetApp}) async {
    final packageName = _knownPackage((targetApp ?? '').toLowerCase()) ?? await _savedPlayer();

    try {
      final bool? result = await _channel.invokeMethod<bool>('playMediaFromSearch', {
        'query': query,
        'package': packageName,
      });
      return result ?? false;
    } catch (_) {
      if (packageName == 'com.spotify.music') {
        final uri = Uri.parse('spotify:search:$query');
        if (await canLaunchUrl(uri)) {
          return await launchUrl(uri);
        }
      }
      return false;
    }
  }

  // "music"/"music player" -> the player chosen in Settings; otherwise native matches installed app labels.
  Future<bool> openApp(String name) async {
    final lower = name.toLowerCase();
    final package = (lower == 'music' || lower == 'music player')
        ? await _savedPlayer()
        : _knownPackage(lower);
    try {
      return await _channel.invokeMethod<bool>('openApp', {'package': package, 'name': lower}) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sendMediaCommand(String action) async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('sendMediaKeyEvent', {'action': action});
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> makePhoneCall(String phoneNumber) async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('makePhoneCall', {'phoneNumber': phoneNumber});
      return result ?? false;
    } catch (_) {
      final uri = Uri.parse('tel:$phoneNumber');
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri);
      }
      return false;
    }
  }
}
