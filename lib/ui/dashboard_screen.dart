import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/constants/app_colors.dart';
import '../core/debug_log.dart';
import '../models/parsed_intent.dart';
import '../services/audio_feedback_service.dart';
import '../services/intercom_audio_service.dart';
import '../services/intent_parser_service.dart';
import '../services/media_intent_service.dart';
import '../services/settings_service.dart';
import '../services/speech_service.dart';
import '../services/system_status_service.dart';
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
  final SystemStatusService _statusService = SystemStatusService();

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
      debugLog('[MotoVoice] TTS init error: $e');
    }

    try {
      await _audioService.stopBluetoothSco();
      // Audio/storage to find song files; phone so voice calls can be placed with the screen off;
      // contacts so "call <name>" can find the number.
      await [Permission.audio, Permission.storage, Permission.phone, Permission.contacts].request();
    } catch (_) {}
    _isScoActive = false;

    _speechService.onWakeWord = () {
      debugLog('[MotoVoice] onWakeWord callback fired');
    };

    _speechService.onCommand = (rawText) async {
      debugLog('[MotoVoice] onCommand callback received: "$rawText"');
      await _executeCommand(rawText);
    };

    _speechService.onError = (err) {
      debugLog('[MotoVoice] onError: $err');
    };

    // Initialize speech service in ready standby
    await _speechService.init();
  }

  Future<void> _executeCommand(String commandText) async {
    final intents = _intentParser.parseAll(commandText);
    for (var i = 0; i < intents.length; i++) {
      // Give an app opened by the previous step a moment to come up before the next action.
      if (i > 0) await Future.delayed(const Duration(milliseconds: 1200));
      await _executeIntent(intents[i], commandText);
    }
  }

  Future<void> _executeIntent(ParsedIntent intent, String commandText) async {
    debugLog('[MotoVoice] Executing parsed intent: ${intent.type}');

    switch (intent.type) {
      case IntentType.greeting:
        _feedbackService.speak('Hello rider. How can I help?');
        break;

      case IntentType.help:
        _feedbackService.speak('You can say play a song, shuffle, next, volume up, or call someone');
        break;

      case IntentType.cancel:
        break;

      case IntentType.playMusic:
        final query = intent.songOrArtist ?? '';
        final app = intent.targetApp;
        _feedbackService.speak('Playing $query');
        await _mediaService.playMedia(query: query, targetApp: app);
        break;

      case IntentType.playArtist:
        final artist = intent.slots['artist'] ?? '';
        _feedbackService.speak('Playing $artist');
        await _mediaService.playMedia(query: artist);
        break;

      case IntentType.shuffleMusic:
        _feedbackService.speak(
          await _mediaService.shuffle() ? 'Shuffling your songs' : 'Unable to play shuffle in your music player',
        );
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

      case IntentType.volumeUnmute:
        await _audioService.adjustVolume('unmute');
        break;

      case IntentType.setVolume:
        final percent = intent.volumePercent ?? 50;
        await _audioService.setVolumePercent(percent);
        _feedbackService.speak('Volume set to $percent percent');
        break;

      case IntentType.makeCall:
        await _callByNumberOrName(intent);
        break;

      case IntentType.openApp:
        final app = intent.targetApp ?? '';
        final opened = await _mediaService.openApp(app);
        _feedbackService.speak(opened ? 'Opening $app' : 'I could not find $app');
        break;

      case IntentType.timeStatus:
        final now = DateTime.now();
        final timeStr = DateFormat('h:mm a').format(now);
        _feedbackService.speak('It is $timeStr');
        break;

      case IntentType.dateStatus:
        final today = DateTime.now();
        final dateStr = DateFormat('MMMM d, y').format(today);
        _feedbackService.speak('Today is $dateStr');
        break;

      case IntentType.batteryStatus:
        final level = await _statusService.getBatteryLevel();
        _feedbackService.speak(
          level != null ? 'Battery is at $level percent' : 'Battery status unavailable',
        );
        break;

      case IntentType.unknown:
        debugLog('[MotoVoice] Unrecognized command: $commandText');
        _feedbackService.speak('Sorry, I didn\'t understand.');
        break;
    }
  }

  Future<void> _callByNumberOrName(ParsedIntent intent) async {
    // SIM: one named in the command ("on Ncell") wins, then the Calling SIM from Settings, else Android asks.
    final sims = await _mediaService.listSims();
    var target = intent.phoneNumber ?? '';
    String? sim;
    final spokenSim = intent.spokenSim;
    final simIndex = spokenSim == null ? null : MediaIntentService.matchSim(spokenSim, sims);
    if (simIndex != null) {
      sim = sims[simIndex];
      target = intent.contactBeforeSim!;
    } else {
      final saved = await SettingsService.getCallingSim();
      if (sims.contains(saved)) sim = saved;
    }
    final onSim = sim == null ? '' : ' on $sim';

    final digits = target.replaceAll(RegExp(r'[\s\-()]'), '');
    if (RegExp(r'^\+?\d{3,}$').hasMatch(digits)) {
      _feedbackService.speak('Calling ${digits.split('').join(' ')}$onSim');
      await _mediaService.makePhoneCall(digits, sim: sim);
      return;
    }

    final matches = await _mediaService.findContacts(target);
    if (matches == null) {
      _feedbackService.speak('Please allow contacts access so I can call people by name');
      return;
    }
    if (matches.isEmpty) {
      _feedbackService.speak('I could not find $target in your contacts');
      return;
    }
    // Two different people scoring about the same (e.g. "John Smith" and "John Doe" for "John"): ask, don't guess.
    if (matches.length > 1 && matches[1].score >= matches[0].score - 0.05) {
      _feedbackService.speak(
        'I found ${matches[0].name} and ${matches[1].name}. Say call, and the full name.',
      );
      return;
    }
    final contact = matches.first;
    _feedbackService.speak('Calling ${contact.name}$onSim');
    // Let the announcement finish before the call takes over the audio.
    await Future.delayed(const Duration(milliseconds: 1500));
    await _mediaService.makePhoneCall(contact.number, sim: sim);
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
          ValueListenableBuilder<bool>(
            valueListenable: _speechService.onDeviceSttNotifier,
            builder: (context, offline, _) {
              final color = offline ? AppColors.neonGreen : AppColors.neonAmber;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.surfaceLight),
                ),
                child: Row(
                  children: [
                    Icon(offline ? Icons.wifi_off_rounded : Icons.wifi_rounded, size: 16, color: color),
                    const SizedBox(width: 6),
                    Text(
                      offline ? 'OFFLINE' : 'ONLINE STT',
                      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              );
            },
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
                        wakePhrase: MotoVoiceSpeechService.wakePhraseNotifier.value,
                        isBluetoothScoOn: _isScoActive,
                        onToggleSco: _toggleBluetoothSco,
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 12),

              ValueListenableBuilder<bool>(
                valueListenable: _speechService.ridingModeNotifier,
                builder: (context, on, _) {
                  return SwitchListTile(
                    value: on,
                    onChanged: _speechService.setRidingMode,
                    activeThumbColor: AppColors.neonGreen,
                    tileColor: AppColors.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    secondary: Icon(
                      Icons.hearing_rounded,
                      color: on ? AppColors.neonGreen : AppColors.textMuted,
                    ),
                    title: const Text(
                      'RIDING MODE',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                    subtitle: ValueListenableBuilder<String>(
                      valueListenable: MotoVoiceSpeechService.wakePhraseNotifier,
                      builder: (context, phrase, _) => Text(
                        on ? '"$phrase" works with screen off' : 'Off - no background battery use',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

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
