import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class B1nGuide extends StatelessWidget {
  const B1nGuide({
    required this.asset,
    required this.title,
    required this.message,
    this.tone = AppColors.blue,
    this.compact = false,
    super.key,
  });

  final String asset;
  final String title;
  final String message;
  final Color tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(asset, fit: BoxFit.contain);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 5),
        Text(message, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tone.withValues(alpha: 0.20)),
      ),
      child: compact
          ? Row(
              children: [
                SizedBox(width: 62, height: 62, child: image),
                const SizedBox(width: 13),
                Expanded(child: text),
              ],
            )
          : Column(
              children: [
                SizedBox(width: 132, height: 126, child: image),
                const SizedBox(height: 4),
                text,
              ],
            ),
    );
  }
}
