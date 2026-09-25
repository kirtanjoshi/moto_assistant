import 'package:flutter_test/flutter_test.dart';
import 'package:moto_assistant/models/parsed_intent.dart';
import 'package:moto_assistant/services/intent_parser_service.dart';

void main() {
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
}
