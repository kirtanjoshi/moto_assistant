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

  /// Turns shuffle on in the music player chosen in Settings and starts it playing.
  /// False when no player is chosen or it can't be remote-controlled.
  Future<bool> shuffle() async {
    final player = await _savedPlayer();
    if (player == null) return false;
    try {
      return await _channel.invokeMethod<bool>('shuffleInPlayer', {'package': player}) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Contacts whose name sounds like [name], best match first. Null when contacts permission is missing.
  Future<List<({String name, String number, double score})>?> findContacts(String name) async {
    try {
      final rows = await _channel.invokeListMethod<Map>('findContacts', {'name': name}) ?? [];
      return [
        for (final r in rows)
          (name: r['name'] as String, number: r['number'] as String, score: (r['score'] as num).toDouble()),
      ];
    } on PlatformException catch (e) {
      if (e.code == 'NO_CONTACTS_PERMISSION') return null;
      return [];
    }
  }

  /// Carrier names of the phone's SIMs in slot order, e.g. ["Namaste", "Ncell"]. Empty without Phone permission.
  Future<List<String>> listSims() async {
    try {
      return await _channel.invokeListMethod<String>('listSims') ?? [];
    } catch (_) {
      return [];
    }
  }

  /// Index in [sims] of a spoken SIM ("ncell", "n cell", "sim 2", "second sim"), or null if none matches.
  static int? matchSim(String spoken, List<String> sims) {
    final s = spoken
        .toLowerCase()
        .replaceAll(RegExp(r'\b(?:the|sim|card|number)\b'), '')
        .replaceAll(RegExp(r'\s+'), '');
    const slots = {'1': 0, 'one': 0, 'first': 0, '2': 1, 'two': 1, 'second': 1};
    final slot = slots[s];
    if (slot != null) return slot < sims.length ? slot : null;
    if (s.length < 3) return null;
    for (var i = 0; i < sims.length; i++) {
      final label = sims[i].toLowerCase().replaceAll(RegExp(r'\s+'), '');
      if (label.contains(s) || s.contains(label)) return i;
    }
    return null;
  }

  /// [sim] is a label from [listSims]; null lets Android choose (it may ask which SIM).
  Future<bool> makePhoneCall(String phoneNumber, {String? sim}) async {
    try {
      final bool? result =
          await _channel.invokeMethod<bool>('makePhoneCall', {'phoneNumber': phoneNumber, 'sim': sim});
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
