import '../models/parsed_intent.dart';

class IntentParserService {
  String _normalizePhonetics(String text) {
    var s = text.trim().toLowerCase();

    // Strip leading wake words if the whole utterance was captured
    final wakeWords = [
      'hey jarvis',
      'oi jarvis',
      'oy jarvis',
      'jarvis',
      'oi moto',
      'oy moto',
      'hey device',
      'device',
      'hey moto',
      'moto',
      'hey google',
      'ok google',
      'assistant'
    ];
    for (final ww in wakeWords) {
      if (s.startsWith('$ww ')) {
        s = s.substring(ww.length + 1).trim();
        break;
      } else if (s == ww) {
        return '';
      }
    }

    // Common phonetic misrecognitions for 'play'
    s = s.replaceAll(
      RegExp(r'^(?:please\s+be|please|plea|lay|pray|blade|plain\s+evil|plain|bleeping)\s+'),
      'play ',
    );
    // Common misrecognitions for 'music'
    s = s.replaceAll('in misery', 'in music');
    s = s.replaceAll('misery player', 'music player');
    s = s.replaceAll('bullying music', 'music');
    // Common misrecognitions for 'volume'
    s = s.replaceAll('follow him', 'volume');
    s = s.replaceAll('bolium', 'volume');

    return s;
  }

  // "open music player and play people" -> [openApp, playMusic]. Only splits when every part is a
  // known command, so song titles like "salt and pepper" stay whole.
  List<ParsedIntent> parseAll(String rawText) {
    final parts = _normalizePhonetics(rawText).split(RegExp(r'\s+(?:and then|and|then)\s+'));
    if (parts.length > 1) {
      final intents = parts.map(parse).toList();
      if (intents.every((i) => i.type != IntentType.unknown)) return intents;
    }
    return [parse(rawText)];
  }

  ParsedIntent parse(String rawText) {
    final text = _normalizePhonetics(rawText);
    if (text.isEmpty) {
      return ParsedIntent(type: IntentType.unknown, rawQuery: rawText);
    }

    // 1. Greetings & System Help
    if (text == 'hello' || text == 'hi' || text == 'hey') {
      return ParsedIntent(type: IntentType.greeting, rawQuery: rawText);
    }
    if (text.contains('help') || text.contains('what can you do')) {
      return ParsedIntent(type: IntentType.help, rawQuery: rawText);
    }
    if (text == 'cancel' || text == 'nevermind' || text == 'stop') {
      return ParsedIntent(type: IntentType.cancel, rawQuery: rawText);
    }

    // Shuffle the phone's songs: "shuffle", "play any song in this shuffle", "play some music", "play random songs".
    // Checked before the play cases, which would otherwise search for a song literally named "some music".
    if (RegExp(r'\bshuffl(?:e|ing)\b').hasMatch(text) ||
        RegExp(r'^(?:play|put on)\s+(?:me\s+)?(?:any|some|a|random|a random|any random)\s+(?:random\s+)?'
                r'(?:song|songs|music|track|tracks)(?:\s+for me)?$')
            .hasMatch(text) ||
        RegExp(r'^(?:random|any)\s+(?:song|songs|music)$').hasMatch(text)) {
      return ParsedIntent(type: IntentType.shuffleMusic, rawQuery: rawText);
    }

    // 2. Track controls
    if (text.contains('next') || text.contains('skip')) {
      return ParsedIntent(type: IntentType.nextTrack, rawQuery: rawText);
    }
    if (text.contains('previous') || text.contains('prev') || text == 'back') {
      return ParsedIntent(type: IntentType.previousTrack, rawQuery: rawText);
    }
    if (text == 'pause' || text == 'pause music' || text == 'stop music') {
      return ParsedIntent(type: IntentType.pauseMusic, rawQuery: rawText);
    }
    if (text == 'resume' ||
        text == 'resume music' ||
        text == 'continue' ||
        text == 'unpause') {
      return ParsedIntent(type: IntentType.resumeMusic, rawQuery: rawText);
    }

    // Open an app: "open music player", "launch spotify", "open the maps app"
    final openMatch = RegExp(r'^(?:open|launch|start)\s+(?:the\s+)?(.+?)(?:\s+app)?$').firstMatch(text);
    if (openMatch != null) {
      return ParsedIntent(
        type: IntentType.openApp,
        slots: {'app': openMatch.group(1)!.trim()},
        rawQuery: rawText,
      );
    }

    // 3. Playback:
    // Case A: [play] <song> in/on <app> (e.g. "people in music player", "play people on spotify")
    final appMatch = RegExp(
      r'^(?:play\s+)?(.*?)\s+(?:in|on)\s+(music player|mp3 player|mp3|player|spotify|youtube music|youtube|yt music|vlc)$',
      caseSensitive: false,
    ).firstMatch(text);

    if (appMatch != null) {
      final songPart = appMatch.group(1)?.trim() ?? '';
      final appPart = appMatch.group(2)?.trim();
      if (songPart.isNotEmpty) {
        return ParsedIntent(
          type: IntentType.playMusic,
          slots: {
            'query': songPart,
            if (appPart != null) 'app': appPart,
          },
          rawQuery: rawText,
        );
      }
    }

    // Case B: General play commands
    if (text == 'play' || text == 'play music' || text == 'play my music') {
      return ParsedIntent(type: IntentType.resumeMusic, rawQuery: rawText);
    }

    // Case C: play (songs by|music by|some) <artist> -> artist-only playback
    final artistOnlyMatch = RegExp(
      r'^play\s+(?:songs\s+by|music\s+by|some\s+songs\s+by|some\s+music\s+by)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (artistOnlyMatch != null) {
      final artist = (artistOnlyMatch.group(1) ?? '').trim();
      if (artist.isNotEmpty) {
        return ParsedIntent(
          type: IntentType.playArtist,
          slots: {'artist': artist},
          rawQuery: rawText,
        );
      }
    }

    // Case D: play <song> by <artist>
    final byArtistMatch = RegExp(
      r'^play\s+(.+?)\s+by\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (byArtistMatch != null) {
      final song = byArtistMatch.group(1)?.trim() ?? '';
      final artist = byArtistMatch.group(2)?.trim() ?? '';
      if (song.isNotEmpty && artist.isNotEmpty) {
        return ParsedIntent(
          type: IntentType.playMusic,
          slots: {'query': song, 'artist': artist},
          rawQuery: rawText,
        );
      }
    }

    if (text.startsWith('play ') || text.contains('play ')) {
      final queryText = text.substring(text.indexOf('play ') + 5).trim();
      if (queryText.isNotEmpty) {
        return ParsedIntent(
          type: IntentType.playMusic,
          slots: {'query': queryText},
          rawQuery: rawText,
        );
      }
    }

    // 4. Volume Commands
    final setVolumeMatch = RegExp(
      r'^(?:set\s+)?volume\s+(?:to\s+)?(\d{1,3})\s*(?:percent|%)?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (setVolumeMatch != null) {
      final value = setVolumeMatch.group(1) ?? '';
      final clamped = (int.tryParse(value) ?? 0).clamp(0, 100);
      return ParsedIntent(
        type: IntentType.setVolume,
        slots: {'value': '$clamped'},
        rawQuery: rawText,
      );
    }
    if (text.contains('volume up') ||
        text.contains('turn up the volume') ||
        text.contains('turn the volume up') ||
        text.contains('increase volume') ||
        text.contains('increase the volume') ||
        text.contains('louder') ||
        text == 'louder') {
      return ParsedIntent(type: IntentType.volumeUp, rawQuery: rawText);
    }
    if (text.contains('volume down') ||
        text.contains('turn down the volume') ||
        text.contains('turn the volume down') ||
        text.contains('decrease volume') ||
        text.contains('decrease the volume') ||
        text.contains('lower volume') ||
        text == 'quieter') {
      return ParsedIntent(type: IntentType.volumeDown, rawQuery: rawText);
    }
    if (text == 'unmute' || text.contains('unmute')) {
      return ParsedIntent(type: IntentType.volumeUnmute, rawQuery: rawText);
    }
    if (text.contains('mute') || text.contains('silence')) {
      return ParsedIntent(type: IntentType.volumeMute, rawQuery: rawText);
    }
    if (text.contains('max volume') ||
        text.contains('maximum volume') ||
        text.contains('full volume')) {
      return ParsedIntent(type: IntentType.volumeMax, rawQuery: rawText);
    }

    // 5. Calling Commands: call / dial <number / contact>
    final callMatch = RegExp(
      r'^(?:make\s+a\s+(?:phone\s+)?call\s+to|call|dial|phone|ring)\s+(?:to\s+)?(?:my\s+)?(.+?)(?:\s+(?:please|now))?$',
    ).firstMatch(text);
    if (callMatch != null) {
      final target = callMatch.group(1)?.trim() ?? '';
      if (target.isNotEmpty) {
        // "daddy on ncell" / "daddy from sim 2": the tail may name a SIM. Kept alongside the full target,
        // because a tail that matches no SIM is part of the name ("ram on mobile").
        final simTail = RegExp(r'^(.+?)\s+(?:on|from|using|with|via|through)\s+(?:my\s+|the\s+)?(.+)$')
            .firstMatch(target);
        return ParsedIntent(
          type: IntentType.makeCall,
          slots: {
            'phone': target,
            if (simTail != null) 'contact': simTail.group(1)!,
            if (simTail != null) 'sim': simTail.group(2)!,
          },
          rawQuery: rawText,
        );
      }
    }

    // 6. System Status
    if (text.contains('battery')) {
      return ParsedIntent(type: IntentType.batteryStatus, rawQuery: rawText);
    }
    if (text.contains('date')) {
      return ParsedIntent(type: IntentType.dateStatus, rawQuery: rawText);
    }
    if (text.contains('time') || text.contains('clock')) {
      return ParsedIntent(type: IntentType.timeStatus, rawQuery: rawText);
    }

    return ParsedIntent(type: IntentType.unknown, rawQuery: rawText);
  }
}
