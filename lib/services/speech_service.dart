import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'settings_service.dart';

enum VoiceLoopState {
  wakeWordListening, // WAKE_WORD_LISTENING: background wake-word detector active
  commandListening,  // COMMAND_LISTENING: STT capturing speech with timeout
  processing,        // PROCESSING: Parsing deterministic intent
  executing,         // EXECUTING: Running Android intent / MediaStore / phone / volume
  speaking,          // SPEAKING: TTS feedback active
}

class MotoVoiceSpeechService {
  static const MethodChannel wakeChannel = MethodChannel('com.motovoice.moto_assistant/wakeword');
  static const MethodChannel _audioChannel = MethodChannel('com.motovoice.moto_assistant/audio_routing');
  static const Duration _commandTimeout = Duration(seconds: 6);

  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _isInitialized = false;
  bool _isDisposed = false;
  VoiceLoopState _state = VoiceLoopState.wakeWordListening;

  Timer? _commandTimer;
  Timer? _safetyRecoveryTimer;

  List<String> wakeWords = ['hey jarvis', 'jarvis', 'hey device', 'device', 'hey moto', 'moto'];

  final ValueNotifier<VoiceLoopState> stateNotifier = ValueNotifier<VoiceLoopState>(VoiceLoopState.wakeWordListening);
  final ValueNotifier<String> partialTextNotifier = ValueNotifier<String>('');
  final ValueNotifier<String> liveHeardNotifier = ValueNotifier<String>('');
  final ValueNotifier<bool> isAwakeNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String> statusNotifier = ValueNotifier<String>('Starting...');
  final ValueNotifier<bool> ridingModeNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> onDeviceSttNotifier = ValueNotifier<bool>(false);

  static final ValueNotifier<String> wakePhraseNotifier =
      ValueNotifier<String>(SettingsService.wakePhrase(SettingsService.defaultWakeEngine));

  String get _standbyStatus =>
      ridingModeNotifier.value ? 'Listening for ${wakePhraseNotifier.value}' : 'Riding mode off - tap mic';

  VoidCallback? onWakeWord;
  Future<void> Function(String command)? onCommand;
  Function(String error)? onError;

  bool get isInitialized => _isInitialized;
  VoiceLoopState get state => _state;
  bool get isListening => _state == VoiceLoopState.commandListening;
  bool get isAwake => _state != VoiceLoopState.wakeWordListening;

  Future<bool> init({List<String>? customWakeWords}) async {
    if (_isInitialized) return true;

    if (customWakeWords != null && customWakeWords.isNotEmpty) {
      wakeWords = customWakeWords.map((w) => w.toLowerCase().trim()).toList();
    }

    _updateState(VoiceLoopState.wakeWordListening, 'Checking permissions...');
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      _updateState(VoiceLoopState.wakeWordListening, 'Mic Permission Denied');
      onError?.call('Microphone permission denied.');
      return false;
    }

    // Android 13+: without this the riding-mode notification is hidden (the service still runs).
    await Permission.notification.request();

    // Register native wake-word bridge handler
    wakeChannel.setMethodCallHandler((call) async {
      if (call.method == 'onWakeWordDetected') {
        final score = (call.arguments?['score'] as num? ?? 0).toDouble();
        final keyword = call.arguments?['keyword'] as String? ?? '';
        print('[MotoVoice State] Native Wake Event | $keyword score: $score | currentState: $_state');
        // Sherpa reports which phrase fired (score is always 1); openWakeWord reports a real score.
        _handleWakeWordTrigger(heard: score < 1 ? '$keyword ${score.toStringAsFixed(2)}' : keyword);
      } else if (call.method == 'onRidingModeChanged') {
        ridingModeNotifier.value = call.arguments == true;
        if (_state == VoiceLoopState.wakeWordListening) statusNotifier.value = _standbyStatus;
      }
    });

    try {
      _updateState(VoiceLoopState.wakeWordListening, 'Initializing Android Speech...');
      final available = await _speech.initialize(
        onStatus: _handleStatus,
        onError: _handleError,
        debugLogging: false,
      );

      if (!available) {
        _updateState(VoiceLoopState.wakeWordListening, 'Speech engine unavailable');
        onError?.call('Speech recognition is not available on this device.');
        return false;
      }

      _isInitialized = true;
      try {
        onDeviceSttNotifier.value =
            await _audioChannel.invokeMethod<bool>('isOnDeviceSpeechAvailable') ?? false;
      } catch (_) {}

      // Mic permission is granted by now, so the native detector can actually open the mic.
      // Engine switched in Settings -> the idle status names the new phrase right away.
      wakePhraseNotifier.addListener(() {
        if (_state == VoiceLoopState.wakeWordListening) statusNotifier.value = _standbyStatus;
      });
      await applyWakeSettings();
      await setRidingMode(await SettingsService.getRidingMode(), persist: false);
      _updateState(VoiceLoopState.wakeWordListening, _standbyStatus);
      return true;
    } catch (e) {
      print('[MotoVoice State] Init error: $e');
      _updateState(VoiceLoopState.wakeWordListening, 'Init Error: $e');
      onError?.call('Init Error: $e');
      return false;
    }
  }

  static Future<void> applyWakeSettings() async {
    final engine = await SettingsService.getWakeEngine();
    wakePhraseNotifier.value = SettingsService.wakePhrase(engine);
    await wakeChannel.invokeMethod('setEngine', {'engine': engine});
    await wakeChannel.invokeMethod('setThreshold', {'threshold': await SettingsService.getWakeThreshold(engine)});
  }

  // Riding mode = foreground service keeping "Hey Jarvis" alive with the screen off. Off = zero background cost.
  Future<void> setRidingMode(bool enabled, {bool persist = true}) async {
    var ok = false;
    try {
      ok = await wakeChannel.invokeMethod<bool>('setRidingMode', {'enabled': enabled}) ?? false;
    } catch (_) {}
    ridingModeNotifier.value = enabled && ok;
    if (persist) await SettingsService.setRidingMode(enabled);
    if (_state == VoiceLoopState.wakeWordListening) statusNotifier.value = _standbyStatus;
  }

  void _updateState(VoiceLoopState newState, String statusMsg) {
    if (_isDisposed) return;
    _state = newState;
    stateNotifier.value = newState;
    isAwakeNotifier.value = (newState != VoiceLoopState.wakeWordListening);
    statusNotifier.value = statusMsg;
    print('[MotoVoice State] STATE: ${_stateToString(newState)} | "$statusMsg"');
  }

  String _stateToString(VoiceLoopState s) {
    switch (s) {
      case VoiceLoopState.wakeWordListening: return 'WAKE_WORD_LISTENING';
      case VoiceLoopState.commandListening:  return 'COMMAND_LISTENING';
      case VoiceLoopState.processing:        return 'PROCESSING';
      case VoiceLoopState.executing:         return 'EXECUTING';
      case VoiceLoopState.speaking:          return 'SPEAKING';
    }
  }

  // 1. Wake word detected or manual mic button tapped
  void manualWake() => _handleWakeWordTrigger();

  Future<void> _handleWakeWordTrigger({String? heard}) async {
    if (_isDisposed) return;

    // Duplicate-trigger protection
    if (_state != VoiceLoopState.wakeWordListening) {
      print('[MotoVoice State] Wake trigger ignored (already in ${_stateToString(_state)})');
      return;
    }

    if (!_isInitialized) {
      final ok = await init();
      if (!ok) return;
    }

    print('[MotoVoice State] ---> WAKE TRIGGERED: Releasing wake detector & starting STT');
    // Showing which phrase fired (and its score) helps calibrate the slider against the rider's voice/mic.
    _updateState(
      VoiceLoopState.commandListening,
      heard == null ? 'Listening...' : 'Listening... ($heard)',
    );
    partialTextNotifier.value = '';
    liveHeardNotifier.value = '';
    onWakeWord?.call();

    // Ensure native detector has completely stopped/released mic
    try {
      await wakeChannel.invokeMethod('stopWakeWord');
    } catch (_) {}

    // Duck any playing music so the recognizer hears the rider, not the song.
    try {
      await _audioChannel.invokeMethod('requestAudioFocus');
    } catch (_) {}

    // Audible "I'm listening" cue; the 250ms gap lets it finish (and the mic release) before STT opens.
    try {
      await _audioChannel.invokeMethod('beep');
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 250));

    try {
      if (_speech.isListening) {
        await _speech.cancel();
        await Future.delayed(const Duration(milliseconds: 150));
      }

      await _speech.listen(
        onResult: _onSpeechResult,
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.confirmation,
          // Riders pause mid-command ("call daddy ... on Ncell"); Android otherwise ends listening after
          // ~1 s of silence and drops everything said after the pause.
          pauseFor: const Duration(milliseconds: 2500),
          listenFor: const Duration(seconds: 20),
          cancelOnError: false,
          partialResults: true,
          // The plugin falls back to the normal (online) recognizer when no offline model is installed.
          onDevice: true,
        ),
      );

      _armCommandTimer();
    } catch (e) {
      print('[MotoVoice State] Exception starting STT: $e');
      _recoverToWakeWordStandby();
    }
  }

  // Restarted on every partial result, so it only fires after silence, never mid-sentence.
  void _armCommandTimer() {
    _commandTimer?.cancel();
    _commandTimer = Timer(_commandTimeout, () {
      print('[MotoVoice State] Command listening timeout expired.');
      _runHeardOrGiveUp();
    });
  }

  // The recognizer can stop without ever sending a final result (or send it too late); the words
  // already heard are the command, so run them rather than drop them.
  void _runHeardOrGiveUp() {
    if (_state != VoiceLoopState.commandListening) return;
    final heard = partialTextNotifier.value.trim();
    if (heard.isNotEmpty) {
      print('[MotoVoice State] No final result - running last heard words: "$heard"');
      _processAndExecuteCommand(heard.toLowerCase());
    } else {
      _recoverToWakeWordStandby();
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (_state != VoiceLoopState.commandListening) return;

    final words = result.recognizedWords.trim();
    if (words.isEmpty) return;

    partialTextNotifier.value = words;
    liveHeardNotifier.value = words;

    // Wait for the recognizer's final result (it ends after the rider stops talking);
    // acting on partials cut off compound commands like "open X and play Y".
    if (result.finalResult) {
      _processAndExecuteCommand(words.toLowerCase());
    } else {
      _armCommandTimer();
    }
  }

  Future<void> _processAndExecuteCommand(String commandText) async {
    if (_state != VoiceLoopState.commandListening) return;

    _commandTimer?.cancel();
    _updateState(VoiceLoopState.processing, 'Processing...');

    // Stop STT to release microphone before execution & TTS
    try {
      await _speech.stop();
    } catch (_) {}

    _updateState(VoiceLoopState.executing, 'Executing...');

    // Safety watchdog: ensure state recovers within 12 seconds if execution hangs
    _safetyRecoveryTimer?.cancel();
    _safetyRecoveryTimer = Timer(const Duration(seconds: 12), () {
      print('[MotoVoice State] Safety watchdog triggered recovery');
      _recoverToWakeWordStandby();
    });

    try {
      if (onCommand != null) {
        await onCommand!(commandText);
      }
    } catch (e) {
      print('[MotoVoice State] Execution exception: $e');
    }

    // Wait a brief window before resuming wake word so TTS has finished
    await Future.delayed(const Duration(milliseconds: 1500));
    _recoverToWakeWordStandby();
  }

  void _handleStatus(String status) {
    if (_isDisposed) return;
    print('[MotoVoice State] STT engine status: $status (currentState: $_state)');

    if (status == 'notListening' || status == 'done') {
      if (_state == VoiceLoopState.commandListening) {
        // With the long pause setting the final result can arrive ~2 s after listening stops.
        Future.delayed(const Duration(milliseconds: 2500), _runHeardOrGiveUp);
      }
    }
  }

  void _handleError(SpeechRecognitionError error) {
    if (_isDisposed) return;
    print('[MotoVoice State] STT engine error: ${error.errorMsg} (permanent: ${error.permanent})');

    if (_state == VoiceLoopState.commandListening) {
      statusNotifier.value = 'Sorry, I didn\'t understand.';
      _recoverToWakeWordStandby();
    }
  }

  // Guaranteed Recovery to WAKE_WORD_LISTENING
  Future<void> _recoverToWakeWordStandby() async {
    if (_isDisposed) return;

    _commandTimer?.cancel();
    _safetyRecoveryTimer?.cancel();

    try {
      if (_speech.isListening) {
        await _speech.stop();
      }
    } catch (_) {}

    _updateState(VoiceLoopState.wakeWordListening, _standbyStatus);

    try {
      await _audioChannel.invokeMethod('abandonAudioFocus');
    } catch (_) {}

    // Resume native wake word detector (native ignores this when riding mode is off)
    try {
      await Future.delayed(const Duration(milliseconds: 200));
      await wakeChannel.invokeMethod('startWakeWord');
      print('[MotoVoice State] ---> WAKE_WORD_LISTENING restored cleanly.');
    } catch (e) {
      print('[MotoVoice State] Error restarting native wake word: $e');
    }
  }

  Future<void> stopListening() async {
    await _recoverToWakeWordStandby();
  }

  void dispose() {
    _isDisposed = true;
    _commandTimer?.cancel();
    _safetyRecoveryTimer?.cancel();
    _speech.stop();
  }
}
