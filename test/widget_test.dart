import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_assistant/models/parsed_intent.dart';
import 'package:moto_assistant/services/intent_parser_service.dart';
import 'package:moto_assistant/services/media_intent_service.dart';
import 'package:moto_assistant/ui/widgets/voice_wave_visualizer.dart';

void main() {
  testWidgets('Mic pulse animates only while awake (no idle redraw)', (tester) async {
    Widget build(bool awake) => MaterialApp(
          home: VoiceWaveVisualizer(isAwake: awake, isListening: false, onTap: () {}),
        );

    await tester.pumpWidget(build(false));
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pumpWidget(build(true));
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pumpWidget(build(false));
    expect(tester.hasRunningAnimations, isFalse);
  });

  group('MotoVoice IntentParserService Tests', () {
    final parser = IntentParserService();

    test('Parses music playback with 3rd-party player', () {
      final intent = parser.parse('play people in music player');
      expect(intent.type, IntentType.playMusic);
      expect(intent.songOrArtist, 'people');
      expect(intent.targetApp, 'music player');
    });

    test('Parses music playback on Spotify', () {
      final intent = parser.parse('play belvedere on spotify');
      expect(intent.type, IntentType.playMusic);
      expect(intent.songOrArtist, 'belvedere');
      expect(intent.targetApp, 'spotify');
    });

    test('Parses track navigation commands', () {
      expect(parser.parse('next song').type, IntentType.nextTrack);
      expect(parser.parse('skip').type, IntentType.nextTrack);
      expect(parser.parse('previous song').type, IntentType.previousTrack);
      expect(parser.parse('pause music').type, IntentType.pauseMusic);
      expect(parser.parse('resume').type, IntentType.resumeMusic);
    });

    test('Parses volume controls', () {
      expect(parser.parse('volume up').type, IntentType.volumeUp);
      expect(parser.parse('volume down').type, IntentType.volumeDown);
      expect(parser.parse('mute').type, IntentType.volumeMute);
      expect(parser.parse('max volume').type, IntentType.volumeMax);
    });

    test('Parses phone call intent', () {
      final intent = parser.parse('call 9876543210');
      expect(intent.type, IntentType.makeCall);
      expect(intent.phoneNumber, '9876543210');
    });

    test('Parses time and battery status queries', () {
      expect(parser.parse('what time is it').type, IntentType.timeStatus);
      expect(parser.parse('battery status').type, IntentType.batteryStatus);
    });
  });

  group('Phase 2.3 MotoVoice IntentParserService Tests', () {
    final parser = IntentParserService();

    test('Media: play song variations', () {
      expect(parser.parse('play Believer').type, IntentType.playMusic);
      expect(parser.parse('Play believer').type, IntentType.playMusic);
      expect(parser.parse('play Believer').songOrArtist, 'believer');
    });

    test('Media: play artist variations', () {
      final t = parser.parse('play songs by Imagine Dragons');
      expect(t.type, IntentType.playArtist);
      expect(t.slots['artist'], 'imagine dragons');
    });

    test('Media: play my music resumes playback', () {
      expect(parser.parse('play my music').type, IntentType.resumeMusic);
    });

    test('Media: playback controls', () {
      expect(parser.parse('pause').type, IntentType.pauseMusic);
      expect(parser.parse('resume').type, IntentType.resumeMusic);
      expect(parser.parse('continue').type, IntentType.resumeMusic);
      expect(parser.parse('next song').type, IntentType.nextTrack);
      expect(parser.parse('previous song').type, IntentType.previousTrack);
      expect(parser.parse('stop').type, IntentType.cancel);
    });

    test('Volume: natural language up/down', () {
      expect(parser.parse('turn the volume up').type, IntentType.volumeUp);
      expect(parser.parse('increase volume').type, IntentType.volumeUp);
      expect(parser.parse('turn the volume down').type, IntentType.volumeDown);
      expect(parser.parse('decrease volume').type, IntentType.volumeDown);
    });

    test('Volume: mute and unmute', () {
      expect(parser.parse('mute').type, IntentType.volumeMute);
      expect(parser.parse('unmute').type, IntentType.volumeUnmute);
    });

    test('Volume: set to an explicit percentage', () {
      final t1 = parser.parse('set volume to 50 percent');
      expect(t1.type, IntentType.setVolume);
      expect(t1.volumePercent, 50);

      final t2 = parser.parse('volume 50');
      expect(t2.type, IntentType.setVolume);
      expect(t2.volumePercent, 50);
    });

    test('Calls: call a named contact', () {
      final t = parser.parse('call John');
      expect(t.type, IntentType.makeCall);
      expect(t.phoneNumber, 'john');
    });

    test('Calls: filler words are stripped from the contact name', () {
      expect(parser.parse('call my mom').phoneNumber, 'mom');
      expect(parser.parse('call to ram please').phoneNumber, 'ram');
      expect(parser.parse('make a call to john smith').phoneNumber, 'john smith');
      expect(parser.parse('dial 98765 43210').phoneNumber, '98765 43210');
    });

    test('Calls: SIM named in the command', () {
      final t = parser.parse('call daddy on ncell');
      expect(t.phoneNumber, 'daddy on ncell');
      expect(t.contactBeforeSim, 'daddy');
      expect(t.spokenSim, 'ncell');
      expect(parser.parse('call daddy from sim 2').spokenSim, 'sim 2');
      expect(parser.parse('call daddy').spokenSim, isNull);
    });

    test('Calls: spoken SIM matches the phone SIM labels', () {
      const sims = ['Namaste', 'Ncell'];
      expect(MediaIntentService.matchSim('ncell', sims), 1);
      expect(MediaIntentService.matchSim('n cell', sims), 1);
      expect(MediaIntentService.matchSim('namaste sim', sims), 0);
      expect(MediaIntentService.matchSim('sim 2', sims), 1);
      expect(MediaIntentService.matchSim('first sim', sims), 0);
      expect(MediaIntentService.matchSim('sim 3', sims), isNull);
      // Not a SIM -> the caller keeps "ram on mobile" as the contact name.
      expect(MediaIntentService.matchSim('mobile', sims), isNull);
    });

    test('Shuffle: phone songs in random order', () {
      for (final phrase in [
        'shuffle',
        'shuffle my songs',
        'play some music',
        'play any song',
        'play random songs',
        'play any song in this shuffle',
      ]) {
        expect(parser.parse(phrase).type, IntentType.shuffleMusic, reason: phrase);
      }
      // Still regular playback, not shuffle:
      expect(parser.parse('play music').type, IntentType.resumeMusic);
      expect(parser.parse('play a song by arijit').type, IntentType.playMusic);
      expect(parser.parse('play believer').type, IntentType.playMusic);
    });

    test('Shuffle: works chained after opening the player', () {
      final intents = parser.parseAll('open music player and play any song in this shuffle');
      expect(intents.map((i) => i.type), [IntentType.openApp, IntentType.shuffleMusic]);
    });

    test('System: time, date, battery queries', () {
      expect(parser.parse('what time is it').type, IntentType.timeStatus);
      expect(parser.parse('what is today\'s date').type, IntentType.dateStatus);
      expect(parser.parse('battery status').type, IntentType.batteryStatus);
    });

    test('Apps: open / launch commands, wake word stripped', () {
      final t = parser.parse('open music player');
      expect(t.type, IntentType.openApp);
      expect(t.targetApp, 'music player');
      expect(parser.parse('launch the spotify app').targetApp, 'spotify');
      expect(parser.parse('jarvis open whatsapp').targetApp, 'whatsapp');
      expect(parser.parse('oi jarvis next song').type, IntentType.nextTrack);
      expect(parser.parse('oi moto volume up').type, IntentType.volumeUp);
      expect(parser.parse('hey moto pause').type, IntentType.pauseMusic);
    });

    test('Compound commands split on and/then, song titles stay whole', () {
      final both = parser.parseAll('hey jarvis open music player and play people');
      expect(both.map((i) => i.type), [IntentType.openApp, IntentType.playMusic]);
      expect(both[1].songOrArtist, 'people');

      expect(parser.parseAll('next song then volume up').map((i) => i.type),
          [IntentType.nextTrack, IntentType.volumeUp]);

      final title = parser.parseAll('play salt and pepper');
      expect(title.single.songOrArtist, 'salt and pepper');
    });

    test('Returns unknown for unrecognized input', () {
      expect(
        parser.parse('the weather looks nice today near the mountains').type,
        IntentType.unknown,
      );
    });
  });
}
