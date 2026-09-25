import '../models/parsed_intent.dart';

class IntentParserService {
  String _normalizePhonetics(String text) {
    var s = text.trim().toLowerCase();

    // Strip leading wake words if the whole utterance was captured
    final wakeWords = [
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
    if (text == 'resume' || text == 'resume music' || text == 'continue') {
      return ParsedIntent(type: IntentType.resumeMusic, rawQuery: rawText);
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
    if (text == 'play' || text == 'play music') {
      return ParsedIntent(type: IntentType.resumeMusic, rawQuery: rawText);
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
    if (text.contains('volume up') ||
        text.contains('increase volume') ||
        text.contains('louder') ||
        text == 'louder') {
      return ParsedIntent(type: IntentType.volumeUp, rawQuery: rawText);
    }
    if (text.contains('volume down') ||
        text.contains('decrease volume') ||
        text.contains('lower volume') ||
        text == 'quieter') {
      return ParsedIntent(type: IntentType.volumeDown, rawQuery: rawText);
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
    final callMatch = RegExp(r'^(?:call|dial|phone)\s+(.+)$', caseSensitive: false).firstMatch(text);
    if (callMatch != null) {
      final target = callMatch.group(1)?.trim() ?? '';
      return ParsedIntent(
        type: IntentType.makeCall,
        slots: {'phone': target},
        rawQuery: rawText,
      );
    }

    // 6. System Status
    if (text.contains('battery')) {
      return ParsedIntent(type: IntentType.batteryStatus, rawQuery: rawText);
    }
    if (text.contains('time') || text.contains('clock')) {
      return ParsedIntent(type: IntentType.timeStatus, rawQuery: rawText);
    }

    return ParsedIntent(type: IntentType.unknown, rawQuery: rawText);
  }
}
