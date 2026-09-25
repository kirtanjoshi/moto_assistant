import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class VoiceWaveVisualizer extends StatefulWidget {
  final bool isAwake;
  final bool isListening;
  final VoidCallback onTap;

  const VoiceWaveVisualizer({
    super.key,
    required this.isAwake,
    required this.isListening,
    required this.onTap,
  });

  @override
  State<VoiceWaveVisualizer> createState() => _VoiceWaveVisualizerState();
}

class _VoiceWaveVisualizerState extends State<VoiceWaveVisualizer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.isAwake ? AppColors.neonCyan : (widget.isListening ? AppColors.neonGreen : AppColors.textMuted);

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          final scale = widget.isAwake ? _scaleAnimation.value : 1.0;
          return Stack(
            alignment: Alignment.center,
            children: [
              // Outer Pulsing Glow
              if (widget.isAwake)
                Container(
                  width: 170 * scale,
                  height: 170 * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: activeColor.withValues(alpha: 0.15),
                    boxShadow: [
                      BoxShadow(
                        color: activeColor.withValues(alpha: 0.3),
                        blurRadius: 30,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                ),
              // Middle Ring
              Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceLight,
                  border: Border.all(
                    color: activeColor,
                    width: widget.isAwake ? 3 : 2,
                  ),
                ),
              ),
              // Core Mic Button
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: activeColor,
                  boxShadow: [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.4),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  widget.isAwake ? Icons.graphic_eq_rounded : Icons.mic_rounded,
                  size: 42,
                  color: AppColors.background,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
