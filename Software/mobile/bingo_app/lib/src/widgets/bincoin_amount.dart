import 'package:flutter/material.dart';

import '../theme/app_assets.dart';
import '../theme/app_theme.dart';

class BinCoinAmount extends StatelessWidget {
  const BinCoinAmount({
    required this.value,
    this.size = 24,
    this.style,
    super.key,
  }) : assert(value >= 0),
       assert(size > 0);

  final int value;
  final double size;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final label = '$value BinCoins';
    final formattedValue = _formatBinCoins(value);
    final icon = BinCoinIcon(size: size);
    final valueText = Text(
      formattedValue,
      maxLines: 1,
      softWrap: false,
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final text = constraints.hasBoundedWidth
                ? Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: valueText,
                    ),
                  )
                : valueText;

            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                SizedBox(width: size * 0.3),
                text,
              ],
            );
          },
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
