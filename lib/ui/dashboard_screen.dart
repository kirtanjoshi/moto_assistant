import 'package:permission_handler/permission_handler.dart';
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/constants/app_colors.dart';
import '../models/parsed_intent.dart';
import '../services/audio_feedback_service.dart';
import '../services/intercom_audio_service.dart';
import '../services/intent_parser_service.dart';
import '../services/media_intent_service.dart';
import '../services/speech_service.dart';
import 'widgets/quick_action_card.dart';
import 'widgets/rider_glance_card.dart';
import 'widgets/voice_wave_visualizer.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final MotoVoiceSpeechService _speechService = MotoVoiceSpeechService();
  final IntentParserService _intentParser = IntentParserService();
  final MediaIntentService _mediaService = MediaIntentService();
  final IntercomAudioService _audioService = IntercomAudioService();
  final AudioFeedbackService _feedbackService = AudioFeedbackService();

  bool _isScoActive = false;

  @override
  void initState() {
    super.initState();
    _initAssistant();
  }

  Future<void> _initAssistant() async {
    try {
      await _feedbackService.init();
    } catch (e) {
      print('[MotoVoice] TTS init error: $e');
    }

    try {
      await _audioService.stopBluetoothSco();
      // Request audio/storage permissions so app can locate song files
      await [Permission.audio, Permission.storage].request();
    } catch (_) {}
    _isScoActive = false;

    _speechService.onWakeWord = () {
      print('[MotoVoice] onWakeWord callback fired');
    };

    _speechService.onCommand = (rawText) {
      print('[MotoVoice] onCommand callback received: "$rawText"');
      _executeCommand(rawText);
    };

    _speechService.onError = (err) {
      print('[MotoVoice] onError: $err');
    };

    // Initialize speech service in ready standby
    await _speechService.init();
  }

  Future<void> _executeCommand(String commandText) async {
    final intent = _intentParser.parse(commandText);
    print('[MotoVoice] Executing parsed intent: ${intent.type}');

    switch (intent.type) {
      case IntentType.greeting:
        _feedbackService.speak('Hello rider. How can I help?');
        break;

      case IntentType.help:
        _feedbackService.speak('You can say play song, next, volume up, or call');
        break;

      case IntentType.cancel:
        break;

      case IntentType.playMusic:
        final query = intent.songOrArtist ?? '';
        final app = intent.targetApp;
        _feedbackService.speak('Playing $query');
        await _mediaService.playMedia(query: query, targetApp: app);
        break;

      case IntentType.nextTrack:
        await _mediaService.sendMediaCommand('next');
        _feedbackService.speak('Next track');
        break;

      case IntentType.previousTrack:
        await _mediaService.sendMediaCommand('previous');
        _feedbackService.speak('Previous track');
        break;

      case IntentType.pauseMusic:
        await _mediaService.sendMediaCommand('pause');
        _feedbackService.speak('Music paused');
        break;

      case IntentType.resumeMusic:
        await _mediaService.sendMediaCommand('play');
        _feedbackService.speak('Resuming');
        break;

      case IntentType.volumeUp:
        await _audioService.adjustVolume('up');
        break;

      case IntentType.volumeDown:
        await _audioService.adjustVolume('down');
        break;

      case IntentType.volumeMax:
        await _audioService.adjustVolume('max');
        _feedbackService.speak('Full volume');
        break;

      case IntentType.volumeMute:
        await _audioService.adjustVolume('mute');
        break;

      case IntentType.makeCall:
        final target = intent.phoneNumber ?? '';
        _feedbackService.speak('Calling $target');
        await _mediaService.makePhoneCall(target);
        break;

      case IntentType.timeStatus:
        final now = DateTime.now();
        final timeStr = DateFormat('h:mm a').format(now);
        _feedbackService.speak('It is $timeStr');
        break;

      case IntentType.batteryStatus:
        _feedbackService.speak('Battery levels normal');
        break;

      case IntentType.unknown:
        print('[MotoVoice] Unrecognized command: $commandText');
        break;
    }
  }

  Future<void> _toggleBluetoothSco() async {
    if (_isScoActive) {
      await _audioService.stopBluetoothSco();
      // Request audio/storage permissions so app can locate song files
      await [Permission.audio, Permission.storage].request();
    } else {
      await _audioService.startBluetoothSco();
    }
    final active = await _audioService.isBluetoothScoOn();
    if (mounted) {
      setState(() {
        _isScoActive = active;
      });
    }
  }

  @override
  void dispose() {
    _speechService.dispose();
    _feedbackService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.two_wheeler_rounded, color: AppColors.neonCyan),
            SizedBox(width: 8),
            Text(
              'MOTOVOICE HUD',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                fontSize: 18,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceLight),
            ),
            child: const Row(
              children: [
                Icon(Icons.wifi_off_rounded, size: 16, color: AppColors.neonGreen),
                SizedBox(width: 6),
                Text(
                  '100% OFFLINE',
                  style: TextStyle(
                    color: AppColors.neonGreen,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded, color: AppColors.textPrimary),
            tooltip: 'Rider Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            children: [
              // 1. Status & Live Transcript Card
              ValueListenableBuilder<String>(
                valueListenable: _speechService.statusNotifier,
                builder: (context, status, _) {
                  return ValueListenableBuilder<String>(
                    valueListenable: _speechService.liveHeardNotifier,
                    builder: (context, heard, _) {
                      return RiderGlanceCard(
                        statusText: status,
                        transcript: heard,
                        isBluetoothScoOn: _isScoActive,
                        onToggleSco: _toggleBluetoothSco,
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 24),

              // 2. Central Mic / Animated Visualizer (Tap to manually wake)
              Expanded(
                child: Center(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _speechService.isAwakeNotifier,
                    builder: (context, isAwake, _) {
                      return VoiceWaveVisualizer(
                        isAwake: isAwake,
                        isListening: _speechService.isListening,
                        onTap: () {
                          _speechService.manualWake();
                        },
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 3. Glove-Friendly Quick Action Grid
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: QuickActionCard(
                          icon: Icons.skip_next_rounded,
                          label: 'Next Song',
                          subtitle: 'Skip track',
                          accentColor: AppColors.neonCyan,
                          onTap: () => _executeCommand('next'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: QuickActionCard(
                          icon: Icons.play_arrow_rounded,
                          label: 'Play / Pause',
                          subtitle: 'Toggle media',
                          accentColor: AppColors.neonGreen,
                          onTap: () => _executeCommand('pause'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: QuickActionCard(
                          icon: Icons.volume_up_rounded,
                          label: 'Volume +',
                          subtitle: 'Raise audio',
                          accentColor: AppColors.neonAmber,
                          onTap: () => _executeCommand('volume up'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: QuickActionCard(
                          icon: Icons.access_time_filled_rounded,
                          label: 'Time Check',
                          subtitle: 'Spoken clock',
                          accentColor: AppColors.textPrimary,
                          onTap: () => _executeCommand('what time is it'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
