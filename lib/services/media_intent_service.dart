import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'settings_service.dart';

class MediaIntentService {
  static const MethodChannel _channel = MethodChannel('com.motovoice.moto_assistant/media_control');

  Future<bool> playMedia({required String query, String? targetApp}) async {
    String? packageName;
    final lowerApp = (targetApp ?? '').toLowerCase();

    if (lowerApp.contains('spotify')) {
      packageName = 'com.spotify.music';
    } else if (lowerApp.contains('youtube') || lowerApp.contains('yt')) {
      packageName = 'com.google.android.apps.youtube.music';
    } else if (lowerApp.contains('vlc')) {
      packageName = 'org.videolan.vlc';
    } else if (lowerApp.contains('mp3') || lowerApp.contains('music player') || lowerApp.contains('player')) {
      packageName = 'musicplayer.musicapps.music.mp3player';
    } else {
      // Read dynamic user preference from Settings
      final savedPlayer = await SettingsService.getSelectedMusicPlayer();
      if (savedPlayer != 'system_prompt') {
        packageName = savedPlayer;
      }
    }

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
