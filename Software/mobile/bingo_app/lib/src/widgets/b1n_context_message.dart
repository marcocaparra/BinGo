import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class B1nContextMessage extends StatelessWidget {
  const B1nContextMessage({
    required this.asset,
    required this.message,
    this.tone = AppColors.blue,
    this.compact = false,
    super.key,
  });

  final String asset;
  final String message;
  final Color tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final imageSize = compact ? 58.0 : 92.0;
    final character = SizedBox.square(
      dimension: imageSize,
      child: Image.asset(asset, fit: BoxFit.contain),
    );
    final speech = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 16,
        vertical: compact ? 12 : 14,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.09),
        border: Border.all(color: tone.withValues(alpha: 0.24)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AppColors.navy),
      ),
    );

    if (compact) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          character,
          const SizedBox(width: 12),
          Expanded(child: speech),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        character,
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: speech),
      ],
    );
  }
}
