import 'package:flutter/material.dart';

import '../theme/app_assets.dart';
import '../theme/app_theme.dart';

class BinCoinAmount extends StatelessWidget {
  const BinCoinAmount({
    required this.value,
    this.size = 24,
    this.style,
    this.showIcon = true,
    super.key,
  }) : assert(value >= 0),
       assert(size > 0);

  final int value;
  final double size;
  final TextStyle? style;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final label = '$value BinCoins';
    final formattedValue = _formatVisualBinCoins(value);
    final valueText = Text(
      formattedValue,
      style:
          style ??
          Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppColors.navy,
            fontFamily: 'Sora',
          ),
    );

    return Semantics(
      label: label,
      container: true,
      child: ExcludeSemantics(
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: size * 0.3,
          runSpacing: 4,
          children: [
            if (showIcon) BinCoinIcon(size: size),
            valueText,
          ],
        ),
      ),
    );
  }
}

class BinCoinIcon extends StatelessWidget {
  const BinCoinIcon({this.size = 28, super.key}) : assert(size > 0);

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Image.asset(
        AppAssets.bincoinV2,
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }
}

String _formatBinCoins(int value) {
  final digits = value.toString();
  final firstGroupLength = digits.length % 3;
  final groups = <String>[];
  var offset = 0;

  if (firstGroupLength > 0) {
    groups.add(digits.substring(0, firstGroupLength));
    offset = firstGroupLength;
  }

  while (offset < digits.length) {
    groups.add(digits.substring(offset, offset + 3));
    offset += 3;
  }

  return groups.join('.');
}

String _formatVisualBinCoins(int value) {
  if (value >= 1000000000) {
    return '${_formatDecimal(value / 1000000000)} bi';
  }
  if (value >= 1000000) {
    return '${_formatDecimal(value / 1000000)} mi';
  }
  if (value >= 100000) {
    return '${_formatDecimal(value / 1000)} mil';
  }
  return _formatBinCoins(value);
}

String _formatDecimal(double value) {
  return value.toStringAsFixed(1).replaceFirst('.', ',');
}
