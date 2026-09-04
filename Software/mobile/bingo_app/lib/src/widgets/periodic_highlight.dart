import 'dart:async';

import 'package:flutter/material.dart';

class PeriodicHighlight extends StatefulWidget {
  const PeriodicHighlight({
    required this.child,
    required this.colors,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.interval = const Duration(seconds: 6),
    this.duration = const Duration(milliseconds: 1800),
    super.key,
  });

  final Widget child;
  final List<Color> colors;
  final BorderRadius borderRadius;
  final Duration interval;
  final Duration duration;

  @override
  State<PeriodicHighlight> createState() => _PeriodicHighlightState();
}

class _PeriodicHighlightState extends State<PeriodicHighlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _timer?.cancel();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 0;
      return;
    }
    _timer = Timer.periodic(widget.interval, (_) {
      if (mounted && !_controller.isAnimating) {
        _controller.forward(from: 0);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final position = -1.45 + (_controller.value * 2.9);
                  return FractionalTranslation(
                    translation: Offset(position, 0),
                    child: Align(
                      child: FractionallySizedBox(
                        widthFactor: 0.34,
                        heightFactor: 1.7,
                        child: Transform.rotate(
                          angle: -0.24,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  ...widget.colors,
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
