import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'bingo_asset_image.dart';

class ImpactComparison extends StatelessWidget {
  const ImpactComparison({
    required this.beforeImage,
    required this.nowImage,
    this.beforeLabel = 'Antes',
    this.nowLabel = 'Agora',
    this.aspectRatio = 16 / 9,
    this.alignment = Alignment.center,
    this.beforeFit = BoxFit.contain,
    this.nowFit = BoxFit.contain,
    this.beforeAlignment,
    this.nowAlignment,
    super.key,
  });

  final String beforeImage;
  final String nowImage;
  final String beforeLabel;
  final String nowLabel;
  final double aspectRatio;
  final Alignment alignment;
  final BoxFit beforeFit;
  final BoxFit nowFit;
  final Alignment? beforeAlignment;
  final Alignment? nowAlignment;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _ImpactFrame(
            image: beforeImage,
            label: beforeLabel,
            aspectRatio: aspectRatio,
            fit: beforeFit,
            alignment: beforeAlignment ?? alignment,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ImpactFrame(
            image: nowImage,
            label: nowLabel,
            aspectRatio: aspectRatio,
            fit: nowFit,
            alignment: nowAlignment ?? alignment,
          ),
        ),
      ],
    );
  }
}

class _ImpactFrame extends StatelessWidget {
  const _ImpactFrame({
    required this.image,
    required this.label,
    required this.aspectRatio,
    required this.fit,
    required this.alignment,
  });

  final String image;
  final String label;
  final double aspectRatio;
  final BoxFit fit;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      image: true,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: aspectRatio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ColoredBox(
                  color: AppColors.surface,
                  child: BingoAssetImage(
                    asset: image,
                    fit: fit,
                    alignment: alignment,
                    semanticLabel: label,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.navy,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
