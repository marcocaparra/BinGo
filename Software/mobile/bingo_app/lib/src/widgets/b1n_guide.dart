import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'b1n_dialogue_strip.dart';
import 'bingo_asset_image.dart';

class B1nGuide extends StatelessWidget {
  const B1nGuide({
    required this.asset,
    required this.title,
    required this.message,
    this.tone = AppColors.blue,
    this.compact = false,
    this.portrait = B1nPortraitVariant.neutral,
    super.key,
  });

  final String asset;
  final String title;
  final String message;
  final Color tone;
  final bool compact;
  final B1nPortraitVariant portrait;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return B1nDialogueStrip(message: message, tone: tone, portrait: portrait);
    }

    final image = BingoAssetImage(
      asset: asset,
      fit: BoxFit.contain,
      semanticLabel: title,
    );
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
      child: Column(
        children: [
          SizedBox(width: 132, height: 126, child: image),
          const SizedBox(height: 4),
          text,
        ],
      ),
    );
  }
}
