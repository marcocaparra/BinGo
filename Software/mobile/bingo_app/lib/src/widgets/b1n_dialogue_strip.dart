import 'package:flutter/material.dart';

import '../theme/app_assets.dart';
import '../theme/app_theme.dart';

class B1nDialogueStrip extends StatelessWidget {
  const B1nDialogueStrip({
    required this.message,
    this.tone = AppColors.blue,
    this.speaker = 'B1N',
    this.asset = AppAssets.b1nIcon,
    super.key,
  });

  final String message;
  final Color tone;
  final String speaker;
  final String asset;

  @override
  Widget build(BuildContext context) {
    final usesClosePortrait = asset != AppAssets.b1nIcon;
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
                width: 40,
                height: 40,
                child: ClipRect(
                  child: Transform.scale(
                    scale: usesClosePortrait ? 2.15 : 1,
                    alignment: usesClosePortrait
                        ? Alignment.topCenter
                        : Alignment.center,
                    child: Image.asset(
                      asset,
                      fit: BoxFit.contain,
                      alignment: usesClosePortrait
                          ? Alignment.topCenter
                          : Alignment.center,
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
