import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class BingoAssetImage extends StatelessWidget {
  const BingoAssetImage({
    required this.asset,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.medium,
    this.semanticLabel,
    this.opacity,
    super.key,
  });

  final String asset;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final FilterQuality filterQuality;
  final String? semanticLabel;
  final Animation<double>? opacity;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      filterQuality: filterQuality,
      semanticLabel: semanticLabel,
      opacity: opacity,
      errorBuilder: (context, error, stackTrace) => _AssetFallback(
        width: width,
        height: height,
        semanticLabel: semanticLabel,
      ),
    );
  }
}

class _AssetFallback extends StatelessWidget {
  const _AssetFallback({this.width, this.height, this.semanticLabel});

  final double? width;
  final double? height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: semanticLabel == null
          ? 'Imagem temporariamente indisponivel'
          : '$semanticLabel. Imagem temporariamente indisponivel',
      child: Container(
        width: width,
        height: height,
        color: AppColors.surface,
        alignment: Alignment.center,
        child: const Icon(
          Icons.image_not_supported_outlined,
          color: AppColors.textMuted,
          size: 28,
        ),
      ),
    );
  }
}
