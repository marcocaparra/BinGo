import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class PinKeypad extends StatelessWidget {
  const PinKeypad({
    required this.value,
    required this.onChanged,
    this.errorText,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? errorText;

  void _append(String digit) {
    if (value.length < 4) {
      onChanged('$value$digit');
    }
  }

  @override
  Widget build(BuildContext context) {
    const labels = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', 'back'];

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (index) {
            final filled = index < value.length;
            return Container(
              width: 17,
              height: 17,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: filled ? AppColors.blue : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: errorText != null ? AppColors.danger : AppColors.line,
                  width: 2,
                ),
              ),
            );
          }),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 10),
          Text(
            errorText!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.danger,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 20),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          mainAxisSpacing: 9,
          crossAxisSpacing: 9,
          physics: const NeverScrollableScrollPhysics(),
          children: labels.map((label) {
            if (label.isEmpty) return const SizedBox();
            final isBack = label == 'back';
            return Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: isBack
                    ? () => onChanged(value.isEmpty ? value : value.substring(0, value.length - 1))
                    : () => _append(label),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: isBack
                      ? const Icon(Icons.backspace_outlined, color: AppColors.navy)
                      : Text(label, style: Theme.of(context).textTheme.titleLarge),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
