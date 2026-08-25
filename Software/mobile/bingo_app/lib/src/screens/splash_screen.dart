import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_assets.dart';
import '../theme/app_theme.dart';
import '../widgets/bingo_asset_image.dart';

const _cinematicDuration = Duration(milliseconds: 2800);

double _phase(
  double value,
  double begin,
  double end, [
  Curve curve = Curves.linear,
]) {
  return curve.transform(((value - begin) / (end - begin)).clamp(0.0, 1.0));
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({this.error, this.onRetry, super.key});

  final Object? error;
  final VoidCallback? onRetry;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _story;
  late final AnimationController _idle;
  bool _motionConfigured = false;

  @override
  void initState() {
    super.initState();
    _story = AnimationController(vsync: this, duration: _cinematicDuration);
    _idle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionConfigured) return;
    _motionConfigured = true;

    if (MediaQuery.disableAnimationsOf(context)) {
      _story.value = 1;
      return;
    }

    _story.forward().whenComplete(() {
      if (mounted) _idle.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _story.dispose();
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('bingo-splash'),
      backgroundColor: AppColors.surface,
      body: RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([_story, _idle]),
          builder: (context, child) => LayoutBuilder(
            builder: (context, constraints) {
              final t = _story.value;
              final idle = _idle.value;
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              final heroSize = (height * 0.46).clamp(235.0, 390.0);
              final logoWidth = (width * 0.76).clamp(230.0, 360.0);

              return Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(painter: _UniversePainter(progress: t)),
                  _HeroMotion(progress: t, idle: idle, size: heroSize),
                  CustomPaint(painter: _ImpactPainter(progress: t)),
                  _LogoReveal(progress: t, idle: idle, width: logoWidth),
                  if (widget.error != null)
                    Align(
                      alignment: const Alignment(0, 0.76),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: _RetryCard(onRetry: widget.onRetry),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _UniversePainter extends CustomPainter {
  const _UniversePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(size.width, size.height),
        const [Color(0xFFFCFEFF), Color(0xFFEDF7FF)],
        const [0, 1],
      );
    canvas.drawRect(Offset.zero & size, background);

    final energy =
        _phase(progress, 0.01, 0.34, Curves.easeOutCubic) *
        (1 - _phase(progress, 0.80, 0.98));
    final center = Offset(size.width * 0.5, size.height * 0.43);
    final aura = Paint()
      ..shader = ui.Gradient.radial(
        center,
        size.shortestSide * 0.62,
        [
          const Color(0xFF22E8FF).withValues(alpha: 0.24 * energy),
          const Color(0xFF168CFF).withValues(alpha: 0.08 * energy),
          Colors.transparent,
        ],
        const [0, 0.44, 1],
      );
    canvas.drawRect(Offset.zero & size, aura);
  }

  @override
  bool shouldRepaint(_UniversePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _HeroMotion extends StatelessWidget {
  const _HeroMotion({
    required this.progress,
    required this.idle,
    required this.size,
  });

  final double progress;
  final double idle;
  final double size;

  @override
  Widget build(BuildContext context) {
    final approach = _phase(progress, 0.05, 0.30, Curves.easeOutCubic);
    final drop = _phase(progress, 0.30, 0.49, Curves.easeInCubic);
    final compression = _phase(progress, 0.47, 0.54, Curves.easeOutCubic);
    final rebound = _phase(progress, 0.54, 0.66, Curves.easeOutBack);
    final exit = _phase(progress, 0.66, 0.79, Curves.easeInOutCubic);
    final flightToDescent = _phase(progress, 0.27, 0.31, Curves.easeInOutCubic);
    final descentToLanding = _phase(
      progress,
      0.43,
      0.47,
      Curves.easeInOutCubic,
    );
    final flightWeight = 1 - flightToDescent;
    final descentWeight = flightToDescent * (1 - descentToLanding);
    final landingWeight = descentToLanding;
    final landingKick = math.sin(compression * math.pi);
    final approachY = -190 + (98 * approach);
    final y =
        approachY +
        (92 * drop) +
        (6 * landingKick) -
        (5 * rebound) -
        (14 * exit);
    final scale =
        (0.34 + (0.44 * approach) + (0.22 * drop)) * (1 + idle * 0.004);
    final rotation =
        (-0.13 * (1 - approach)) + (0.045 * drop * (1 - compression));
    final opacity =
        _phase(progress, 0.04, 0.13, Curves.easeOutCubic) * (1 - exit);

    return Align(
      alignment: const Alignment(0, -0.22),
      child: Transform.translate(
        offset: Offset(0, y),
        child: Transform.rotate(
          angle: rotation,
          child: Transform.scale(
            scaleX: scale * (1 + (landingKick * 0.045)),
            scaleY: scale * (1 - (landingKick * 0.065)),
            child: Opacity(
              opacity: opacity,
              child: SizedBox(
                width: size,
                height: size,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Opacity(
                      opacity: flightWeight,
                      child: Transform.translate(
                        offset: Offset(0, -5 * flightToDescent),
                        child: BingoAssetImage(
                          asset: AppAssets.b1nSplashFlight,
                          key: const ValueKey('b1n-splash-flight'),
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                    Opacity(
                      opacity: descentWeight,
                      child: Transform.translate(
                        offset: Offset(0, 3 * descentToLanding),
                        child: BingoAssetImage(
                          asset: AppAssets.b1nSplashDescent,
                          key: const ValueKey('b1n-splash-descent'),
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                    Opacity(
                      opacity: landingWeight,
                      child: Transform.scale(
                        scale: 0.88 + (0.12 * rebound),
                        child: BingoAssetImage(
                          asset: AppAssets.b1nSplashHero,
                          key: const ValueKey('b1n-splash-hero'),
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
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

class _ImpactPainter extends CustomPainter {
  const _ImpactPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final contact = _phase(progress, 0.47, 0.53, Curves.easeOutCubic);
    final dissolve = 1 - _phase(progress, 0.60, 0.70, Curves.easeInOutCubic);
    final opacity = contact * dissolve;
    if (opacity <= 0) return;

    final center = Offset(size.width * 0.5, size.height * 0.60);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(1, 0.17);
    final groundGlow = Paint()
      ..shader = ui.Gradient.radial(
        Offset.zero,
        size.width * 0.36,
        [
          const Color(0xFF26DFFF).withValues(alpha: opacity * 0.18),
          const Color(0xFF168CFF).withValues(alpha: opacity * 0.05),
          Colors.transparent,
        ],
        const [0, 0.42, 1],
      );
    canvas.drawCircle(Offset.zero, size.width * 0.36 * contact, groundGlow);
    canvas.restore();

    for (var ring = 0; ring < 3; ring++) {
      final begin = 0.48 + (ring * 0.022);
      final local = _phase(progress, begin, begin + 0.17);
      if (local <= 0 || local >= 1) continue;
      final eased = Curves.easeOutCubic.transform(local);
      final radiusX = size.width * (0.05 + (eased * 0.39));
      final radiusY = radiusX * 0.145;
      final ringOpacity =
          math.sin(local * math.pi) * dissolve * (0.60 - ring * 0.09);
      final paint = Paint()
        ..color = const Color(0xFF1FDFFF).withValues(alpha: ringOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 - ring * 0.24
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width: radiusX * 2,
          height: radiusY * 2,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ImpactPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _LogoReveal extends StatelessWidget {
  const _LogoReveal({
    required this.progress,
    required this.idle,
    required this.width,
  });

  final double progress;
  final double idle;
  final double width;

  @override
  Widget build(BuildContext context) {
    final reveal = _phase(progress, 0.70, 0.84, const Cubic(0.2, 0.8, 0.2, 1));
    final finalFloat = progress >= 1 ? (idle - 0.5) * 2 : 0.0;
    return Align(
      alignment: const Alignment(0, 0.04),
      child: Transform.translate(
        offset: Offset(0, (9 * (1 - reveal)) + finalFloat),
        child: Transform.scale(
          scale: 0.97 + (0.03 * reveal) + (idle * 0.002),
          child: Opacity(
            opacity: reveal,
            child: SizedBox(
              width: width,
              child: BingoAssetImage(
                asset: AppAssets.splashLogo,
                key: const ValueKey('splash-logo'),
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RetryCard extends StatelessWidget {
  const _RetryCard({required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 330),
        padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.line),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.12),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(
              Icons.wifi_tethering_error_rounded,
              color: AppColors.blue,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'N\u00e3o consegui iniciar agora.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Tentar novamente',
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
