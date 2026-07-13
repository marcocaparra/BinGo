import 'package:flutter/material.dart';

import '../theme/app_assets.dart';
import '../theme/app_theme.dart';

class BinCoinAmount extends StatelessWidget {
  const BinCoinAmount({
    required this.value,
    this.size = 24,
    this.style,
    super.key,
  });

  final num value;
  final double size;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final label = '$value BinCoins';

    return Semantics(
      label: label,
      container: true,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: size,
              child: Image.asset(
                AppAssets.bincoinV2,
                width: size,
                height: size,
                fit: BoxFit.contain,
              ),
            ),
            SizedBox(width: size * 0.3),
            Text(
              '$value',
              style:
                  style ??
                  Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.navy,
                    fontFamily: 'Sora',
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
