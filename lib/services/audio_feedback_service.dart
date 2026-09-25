import 'package:flutter_tts/flutter_tts.dart';

class AudioFeedbackService {
  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      await _tts.setLanguage('en-US');
      await _tts.setPitch(1.0);
      await _tts.setSpeechRate(0.55); // Slightly faster for quick helmet audio feedback
      _isInitialized = true;
    } catch (e) {
      // Fallback
    }
  }

  Future<void> speak(String text) async {
    try {
      if (!_isInitialized) await init();
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      // Audio fallback
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
