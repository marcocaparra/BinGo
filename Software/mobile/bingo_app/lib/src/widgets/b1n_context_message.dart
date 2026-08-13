import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'b1n_dialogue_strip.dart';

enum B1nMessageLayout { leading, trailing, stacked }

class B1nContextMessage extends StatelessWidget {
  const B1nContextMessage({
    required this.asset,
    required this.message,
    this.tone = AppColors.blue,
    this.compact = false,
    this.layout = B1nMessageLayout.leading,
    super.key,
  });

  final String asset;
  final String message;
  final Color tone;
  final bool compact;
  final B1nMessageLayout layout;

  @override
  Widget build(BuildContext context) {
    return B1nDialogueStrip(message: message, tone: tone);
  }
}
