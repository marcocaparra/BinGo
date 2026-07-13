import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum BingoActionTone { blue, green, purple, yellow }

enum BingoActionStyle { primary, secondary, quiet }

class BingoActionButton extends StatefulWidget {
  const BingoActionButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.tone = BingoActionTone.blue,
    this.style = BingoActionStyle.primary,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final BingoActionTone tone;
  final BingoActionStyle style;

  @override
  State<BingoActionButton> createState() => _BingoActionButtonState();
}

class _BingoActionButtonState extends State<BingoActionButton> {
  var _pressed = false;

  Color get _toneColor {
    return switch (widget.tone) {
      BingoActionTone.blue => AppColors.blue,
      BingoActionTone.green => AppColors.green,
      BingoActionTone.purple => AppColors.scr4p,
      BingoActionTone.yellow => AppColors.warning,
    };
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final isPrimary = widget.style == BingoActionStyle.primary;
    final isQuiet = widget.style == BingoActionStyle.quiet;
    final foreground = isPrimary ? Colors.white : _toneColor;
    final background = isPrimary
        ? _toneColor
        : isQuiet
        ? Colors.transparent
        : _toneColor.withValues(alpha: 0.10);

    return Semantics(
      button: true,
      enabled: enabled,
      child: SizedBox(
        width: double.infinity,
        height: isQuiet ? 44 : 56,
        child: AnimatedScale(
          duration: Duration(milliseconds: reduceMotion ? 0 : AppMotion.fast),
          curve: Curves.easeOutCubic,
          scale: _pressed && enabled ? 0.975 : 1,
          child: AnimatedContainer(
            duration: Duration(milliseconds: reduceMotion ? 0 : AppMotion.fast),
            decoration: BoxDecoration(
              color: enabled ? background : AppColors.line,
              borderRadius: BorderRadius.circular(16),
              border: isPrimary
                  ? Border.all(color: Colors.white.withValues(alpha: 0.24))
                  : isQuiet
                  ? null
                  : Border.all(color: _toneColor.withValues(alpha: 0.28)),
              boxShadow: isPrimary && enabled
                  ? [
                      BoxShadow(
                        color: _toneColor.withValues(alpha: 0.26),
                        blurRadius: AppElevation.buttonBlur,
                        offset: AppElevation.buttonOffset,
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: widget.onPressed,
                onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
                onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
                onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (isPrimary && enabled)
                      Positioned(
                        top: 2,
                        left: 14,
                        right: 14,
                        height: 17,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(99),
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withValues(alpha: 0.30),
                                  Colors.white.withValues(alpha: 0.02),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.icon != null) ...[
                            Icon(widget.icon, color: foreground, size: 20),
                            const SizedBox(width: 9),
                          ],
                          Flexible(
                            child: Text(
                              widget.label,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: enabled ? foreground : AppColors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
