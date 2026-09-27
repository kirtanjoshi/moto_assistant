import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/constants/app_colors.dart';
import '../../services/settings_service.dart';
import '../../services/speech_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedPackage = 'musicplayer.musicapps.music.mp3player';
  final TextEditingController _customPackageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  double _threshold = SettingsService.defaultWakeThreshold;
  bool _batteryExempt = false;

  Future<void> _loadSettings() async {
    final current = await SettingsService.getSelectedMusicPlayer();
    final threshold = await SettingsService.getWakeThreshold();
    final exempt = await Permission.ignoreBatteryOptimizations.isGranted;
    if (!mounted) return;
    setState(() {
      _selectedPackage = current;
      _threshold = threshold;
      _batteryExempt = exempt;
    });
  }

  Future<void> _applyThreshold(double value) async {
    await SettingsService.setWakeThreshold(value);
    try {
      await MotoVoiceSpeechService.wakeChannel.invokeMethod('setThreshold', {'threshold': value});
    } catch (_) {}
  }

  Future<void> _requestBatteryExemption() async {
    final status = await Permission.ignoreBatteryOptimizations.request();
    if (mounted) setState(() => _batteryExempt = status.isGranted);
  }

  Future<void> _selectPlayer(String packageName) async {
    setState(() {
      _selectedPackage = packageName;
    });
    await SettingsService.setSelectedMusicPlayer(packageName);
  }

  @override
  void dispose() {
    _customPackageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'RIDER SETTINGS',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            const Row(
              children: [
                Icon(Icons.hearing_rounded, color: AppColors.neonCyan, size: 22),
                SizedBox(width: 8),
                Text(
                  'HEY JARVIS',
                  style: TextStyle(
                    color: AppColors.neonCyan,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Wake strictness: ${_threshold.toStringAsFixed(2)}. Raise it if Jarvis wakes by itself '
              '(wind, engine, music); lower it if it misses you.',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            Slider(
              value: _threshold,
              min: 0.01,
              max: 0.9,
              divisions: 89,
              label: _threshold.toStringAsFixed(2),
              activeColor: AppColors.neonCyan,
              onChanged: (v) => setState(() => _threshold = v),
              onChangeEnd: _applyThreshold,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.battery_saver_rounded,
                color: _batteryExempt ? AppColors.neonGreen : AppColors.neonAmber,
              ),
              title: Text(
                _batteryExempt ? 'Battery optimization: off for MotoVoice' : 'Allow running in background',
                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
              ),
              subtitle: const Text(
                'Stops Samsung/Xiaomi/etc. from killing riding mode after a few minutes.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              onTap: _batteryExempt ? null : _requestBatteryExemption,
            ),
            const SizedBox(height: 20),

            const Row(
              children: [
                Icon(Icons.library_music_rounded, color: AppColors.neonCyan, size: 22),
                SizedBox(width: 8),
                Text(
                  'DEFAULT MUSIC APP',
                  style: TextStyle(
                    color: AppColors.neonCyan,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Select which music player opens automatically when you say "Play [Song]".',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),

            // List of available players
            ...SettingsService.availablePlayers.map((player) {
              final isSelected = _selectedPackage == player.packageName;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? AppColors.neonCyan : AppColors.surfaceLight,
                    width: isSelected ? 2 : 1.2,
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: Text(
                    player.name,
                    style: TextStyle(
                      color: isSelected ? AppColors.neonCyan : AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Text(
                    player.description,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  trailing: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? AppColors.neonCyan : AppColors.textMuted,
                        width: 2,
                      ),
                      color: isSelected ? AppColors.neonCyan : Colors.transparent,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, size: 16, color: AppColors.background)
                        : null,
                  ),
                  onTap: () => _selectPlayer(player.packageName),
                ),
              );
            }),

            const SizedBox(height: 20),
            // Custom Package Input Accordion
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                title: const Text(
                  'Use Another Music App (Custom Package)',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.surfaceLight),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Enter Android Package Name:',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _customPackageController,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'e.g. com.maxmpz.audioplayer',
                            hintStyle: const TextStyle(color: AppColors.textMuted),
                            filled: true,
                            fillColor: AppColors.surfaceLight,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.neonCyan,
                              foregroundColor: AppColors.background,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              final pkg = _customPackageController.text.trim();
                              if (pkg.isNotEmpty) {
                                _selectPlayer(pkg);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Custom player set to: $pkg')),
                                );
                              }
                            },
                            child: const Text('Save Custom Player', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
