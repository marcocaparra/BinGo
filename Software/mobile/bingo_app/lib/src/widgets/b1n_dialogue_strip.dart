import 'package:flutter/material.dart';

import '../theme/app_assets.dart';
import '../theme/app_theme.dart';

class B1nDialogueStrip extends StatelessWidget {
  const B1nDialogueStrip({
    required this.message,
    this.tone = AppColors.blue,
    this.speaker = 'B1N',
    this.asset = AppAssets.b1nIcon,
    this.portraitScale,
    this.portraitAlignment,
    this.portraitSize = 40,
    super.key,
  });

  final String message;
  final Color tone;
  final String speaker;
  final String asset;
  final double? portraitScale;
  final Alignment? portraitAlignment;
  final double portraitSize;

  @override
  Widget build(BuildContext context) {
    final usesClosePortrait = asset != AppAssets.b1nIcon;
    final resolvedAlignment =
        portraitAlignment ??
        (usesClosePortrait ? Alignment.topCenter : Alignment.center);
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
                width: portraitSize,
                height: portraitSize,
                child: ClipRect(
                  child: Transform.scale(
                    scale: portraitScale ?? (usesClosePortrait ? 2.15 : 1),
                    alignment: resolvedAlignment,
                    child: Image.asset(
                      asset,
                      fit: BoxFit.contain,
                      alignment: resolvedAlignment,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
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
