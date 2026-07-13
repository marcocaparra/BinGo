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

class _BingoActionButtonState extends State<BingoActionButton>
    with SingleTickerProviderStateMixin {
  var _pressed = false;
  late final AnimationController _energyController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  );
  late final Animation<Offset> _energyPosition = Tween<Offset>(
    begin: const Offset(-1.35, 0),
    end: const Offset(1.35, 0),
  ).animate(
    CurvedAnimation(parent: _energyController, curve: Curves.easeInOutSine),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncEnergyAnimation();
  }

  @override
  void didUpdateWidget(covariant BingoActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncEnergyAnimation();
  }

  void _syncEnergyAnimation() {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final shouldAnimate = !reduceMotion &&
        widget.onPressed != null &&
        widget.style == BingoActionStyle.primary;
    if (shouldAnimate && !_energyController.isAnimating) {
      _energyController.repeat(reverse: true);
    } else if (!shouldAnimate) {
      _energyController
        ..stop()
        ..value = 0.5;
    }
  }

  @override
  void dispose() {
    _energyController.dispose();
    super.dispose();
  }

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
            clipBehavior: Clip.antiAlias,
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
                      Positioned.fill(
                        child: IgnorePointer(
                          child: reduceMotion
                              ? _EnergyHighlight(tone: _toneColor)
                              : SlideTransition(
                                  key: const Key('bingo-action-energy-slide'),
                                  position: _energyPosition,
                                  child: _EnergyHighlight(tone: _toneColor),
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

class _EnergyHighlight extends StatelessWidget {
  const _EnergyHighlight({required this.tone});

  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Align(
      key: const Key('bingo-action-energy-highlight'),
      child: FractionallySizedBox(
        widthFactor: 0.42,
        heightFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                tone.withValues(alpha: 0),
                Colors.white.withValues(alpha: 0.24),
                const Color(0xFFB9FFDF).withValues(alpha: 0.32),
                tone.withValues(alpha: 0),
              ],
              stops: const [0, 0.38, 0.56, 1],
            ),
          ),
        ),
      ),
    );
  }
}
