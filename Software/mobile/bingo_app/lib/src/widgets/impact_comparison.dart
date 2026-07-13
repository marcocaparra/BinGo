import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ImpactComparison extends StatelessWidget {
  const ImpactComparison({
    required this.beforeImage,
    required this.nowImage,
    this.beforeLabel = 'Antes',
    this.nowLabel = 'Agora',
    this.aspectRatio = 4 / 3,
    this.alignment = Alignment.center,
    super.key,
  });

  final String beforeImage;
  final String nowImage;
  final String beforeLabel;
  final String nowLabel;
  final double aspectRatio;
  final Alignment alignment;

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
            alignment: alignment,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ImpactFrame(
            image: nowImage,
            label: nowLabel,
            aspectRatio: aspectRatio,
            alignment: alignment,
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
    required this.alignment,
  });

  final String image;
  final String label;
  final double aspectRatio;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      image: true,
      child: ExcludeSemantics(
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(image, fit: BoxFit.cover, alignment: alignment),
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
