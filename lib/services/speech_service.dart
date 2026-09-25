// ignore_for_file: avoid_print
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'intent_parser_service.dart';
import '../models/parsed_intent.dart';

class MotoVoiceSpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final IntentParserService _parser = IntentParserService();

  bool _isInitialized = false;
  bool _isListening = false;
  bool _isAwake = false;
  bool _isDisposed = false;

  Timer? _awakeTimer;

  List<String> wakeWords = ['hey device', 'device', 'hey moto', 'moto'];

  final ValueNotifier<String> partialTextNotifier = ValueNotifier<String>('');
  final ValueNotifier<String> liveHeardNotifier = ValueNotifier<String>('');
  final ValueNotifier<bool> isAwakeNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String> statusNotifier = ValueNotifier<String>('Starting...');

  VoidCallback? onWakeWord;
  Function(String command)? onCommand;
  Function(String error)? onError;

  bool get isInitialized => _isInitialized;
  bool get isListening => _isListening;
  bool get isAwake => _isAwake;

  Future<bool> init({List<String>? customWakeWords}) async {
    if (_isInitialized) return true;

    if (customWakeWords != null && customWakeWords.isNotEmpty) {
      wakeWords = customWakeWords.map((w) => w.toLowerCase().trim()).toList();
    }

    statusNotifier.value = 'Checking permissions...';
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      statusNotifier.value = 'Mic Permission Denied';
      onError?.call('Microphone permission denied.');
      return false;
    }

    try {
      statusNotifier.value = 'Initializing Android Speech...';
      print('[MotoVoice STT] Initializing on-device speech engine...');

      final available = await _speech.initialize(
        onStatus: _handleStatus,
        onError: _handleError,
        debugLogging: true,
      );

      if (!available) {
        statusNotifier.value = 'Speech engine unavailable';
        onError?.call('Speech recognition is not available on this device.');
        return false;
      }

      _isInitialized = true;
      statusNotifier.value = 'Ready (Tap mic to speak)';
      print('[MotoVoice STT] Speech engine initialized successfully!');
      return true;
    } catch (e) {
      print('[MotoVoice STT] Init exception: $e');
      statusNotifier.value = 'Init Error: $e';
      onError?.call('Init Error: $e');
      return false;
    }
  }

  void _handleStatus(String status) {
    if (_isDisposed) return;
    print('[MotoVoice STT] Engine status: $status');

    if (status == 'listening') {
      _isListening = true;
      statusNotifier.value = 'Listening... Speak now!';
    } else if (status == 'notListening' || status == 'done') {
      _isListening = false;
      if (!_isAwake) {
        statusNotifier.value = 'Ready (Tap mic to speak)';
      }
    }
  }

  void _handleError(SpeechRecognitionError error) {
    if (_isDisposed) return;
    print('[MotoVoice STT] Engine info: ${error.errorMsg} (permanent: ${error.permanent})');
    _isListening = false;
    if (!_isAwake) {
      statusNotifier.value = 'Ready (Tap mic to speak)';
    }
  }

  Future<void> startListening() => manualWake();

  Future<void> manualWake() async {
    print('[MotoVoice STT] Manual mic tap triggered');
    _triggerWake();

    if (!_isInitialized) {
      final ok = await init();
      if (!ok) return;
    }

    try {
      if (_speech.isListening) {
        await _speech.cancel();
        await Future.delayed(const Duration(milliseconds: 200));
      }

      print('[MotoVoice STT] Calling _speech.listen()...');
      await _speech.listen(
        onResult: _onSpeechResult,
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.confirmation,
          cancelOnError: false,
          partialResults: true,
        ),
      );
      _isListening = true;
      statusNotifier.value = 'Listening... Speak now!';
      print('[MotoVoice STT] Listening successfully started!');
    } catch (e) {
      print('[MotoVoice STT] Exception in manualWake: ');
      statusNotifier.value = 'Ready (Tap mic to speak)';
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    final words = result.recognizedWords.trim();
    if (words.isEmpty) return;

    final lower = words.toLowerCase();
    print('[MotoVoice STT] Heard: "$lower" (final: ${result.finalResult}, isAwake: $_isAwake)');
    partialTextNotifier.value = words;
    liveHeardNotifier.value = words;

    // Check if user spoke a wake word
    for (final ww in wakeWords) {
      if (lower.startsWith(ww) || lower.contains(ww)) {
        if (!_isAwake) {
          _triggerWake();
        }
        if (result.finalResult) {
          _dispatchCommand(lower);
        }
        return;
      }
    }

    // Direct command execution (e.g. "play people in music player", "volume up", etc.)
    if (result.finalResult) {
      final parsed = _parser.parse(lower);
      if (parsed.type != IntentType.unknown) {
        print('[MotoVoice STT] Direct command matched: ${parsed.type} ("$lower")');
        _dispatchCommand(lower);
        return;
      }
    }

    // If already awake and final result arrived (e.g. raw song name query)
    if (_isAwake && result.finalResult) {
      _dispatchCommand(lower);
    }
  }

  void _triggerWake() {
    _isAwake = true;
    isAwakeNotifier.value = true;
    statusNotifier.value = 'Listening... Speak now!';
    onWakeWord?.call();

    _awakeTimer?.cancel();
    _awakeTimer = Timer(const Duration(seconds: 12), () {
      print('[MotoVoice STT] Wake window timed out');
      _isAwake = false;
      isAwakeNotifier.value = false;
      statusNotifier.value = 'Ready (Tap mic to speak)';
      _speech.stop();
    });
  }

  void _dispatchCommand(String command) {
    print('[MotoVoice STT] Dispatching command: "$command"');
    _awakeTimer?.cancel();
    _isAwake = false;
    isAwakeNotifier.value = false;
    statusNotifier.value = 'Executing...';
    onCommand?.call(command);

    // Stop listening during execution and return to ready state
    _speech.stop().then((_) {
      _isListening = false;
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (!_isDisposed && !_isAwake) {
          statusNotifier.value = 'Ready (Tap mic to speak)';
        }
      });
    });
  }

  Future<void> stopListening() async {
    try {
      _awakeTimer?.cancel();
      _isAwake = false;
      isAwakeNotifier.value = false;
      await _speech.stop();
      _isListening = false;
      statusNotifier.value = 'Ready (Tap mic to speak)';
    } catch (e) {
      print('[MotoVoice STT] Stop error: $e');
    }
  }

  void dispose() {
    _isDisposed = true;
    _awakeTimer?.cancel();
    _speech.stop();
  }
}
