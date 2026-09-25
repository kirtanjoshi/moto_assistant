// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_assistant/services/intent_parser_service.dart';
import 'package:moto_assistant/models/parsed_intent.dart';

void main() {
  final parser = IntentParserService();

  test('Test various speech commands', () {
    final t1 = parser.parse('people in music player');
    expect(t1.type, IntentType.playMusic);
    expect(t1.slots['query'], 'people');
    expect(t1.slots['app'], 'music player');

    final t2 = parser.parse('play people in music player');
    expect(t2.type, IntentType.playMusic);
    expect(t2.slots['query'], 'people');
    expect(t2.slots['app'], 'music player');

    final t3 = parser.parse('hey device play people in music player');
    expect(t3.type, IntentType.playMusic);
    expect(t3.slots['query'], 'people');

    final t4 = parser.parse('play people');
    expect(t4.type, IntentType.playMusic);
    expect(t4.slots['query'], 'people');

    final t5 = parser.parse('volume up');
    expect(t5.type, IntentType.volumeUp);

    final t6 = parser.parse('hey device pause');
    expect(t6.type, IntentType.pauseMusic);

    final t7 = parser.parse('next');
    expect(t7.type, IntentType.nextTrack);

    print('ALL PARSER TESTS PASSED!');
  });
}
