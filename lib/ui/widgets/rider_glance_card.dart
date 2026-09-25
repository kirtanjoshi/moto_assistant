import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class RiderGlanceCard extends StatelessWidget {
  final String statusText;
  final String transcript;
  final bool isBluetoothScoOn;
  final VoidCallback onToggleSco;

  const RiderGlanceCard({
    super.key,
    required this.statusText,
    required this.transcript,
    required this.isBluetoothScoOn,
    required this.onToggleSco,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isBluetoothScoOn ? AppColors.neonCyan.withValues(alpha: 0.5) : AppColors.surfaceLight,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Status text wrapped in Expanded/Flexible to prevent screen overflow
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isBluetoothScoOn ? AppColors.neonGreen : AppColors.neonAmber,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        statusText.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onToggleSco,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isBluetoothScoOn
                        ? AppColors.neonCyan.withValues(alpha: 0.15)
                        : AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.headset_mic_rounded,
                        size: 16,
                        color: isBluetoothScoOn ? AppColors.neonCyan : AppColors.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isBluetoothScoOn ? 'INTERCOM ON' : 'INTERCOM OFF',
                        style: TextStyle(
                          color: isBluetoothScoOn ? AppColors.neonCyan : AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            transcript.isNotEmpty ? '"$transcript"' : 'Say "Hey Device" followed by your command...',
            style: TextStyle(
              color: transcript.isNotEmpty ? AppColors.neonCyan : AppColors.textSecondary,
              fontSize: 15,
              fontStyle: transcript.isNotEmpty ? FontStyle.italic : FontStyle.normal,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
