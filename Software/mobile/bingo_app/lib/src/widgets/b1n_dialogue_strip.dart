import 'package:flutter/material.dart';

import '../theme/app_assets.dart';
import '../theme/app_theme.dart';
import 'bingo_asset_image.dart';

enum B1nPortraitVariant { neutral, instruction, question, celebration }

class B1nDialogueStrip extends StatelessWidget {
  const B1nDialogueStrip({
    required this.message,
    this.tone = AppColors.blue,
    this.speaker = 'B1N',
    this.portrait = B1nPortraitVariant.neutral,
    super.key,
  });

  final String message;
  final Color tone;
  final String speaker;
  final B1nPortraitVariant portrait;

  String get _asset => switch (portrait) {
    B1nPortraitVariant.neutral => AppAssets.b1nIcon,
    B1nPortraitVariant.instruction => AppAssets.b1nPortraitInstruction,
    B1nPortraitVariant.question => AppAssets.b1nPortraitQuestion,
    B1nPortraitVariant.celebration => AppAssets.b1nPortraitCelebration,
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$speaker diz: $message',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.07),
          border: Border.all(color: tone.withValues(alpha: 0.16)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ExcludeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 4,
                height: 40,
                decoration: BoxDecoration(
                  color: tone,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 44,
                height: 44,
                child: BingoAssetImage(
                  asset: _asset,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  filterQuality: FilterQuality.high,
                  semanticLabel: speaker,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      speaker,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: tone,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: AppColors.navy),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
