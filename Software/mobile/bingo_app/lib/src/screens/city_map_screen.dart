import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/demo_data.dart';
import '../theme/app_theme.dart';
import '../widgets/bingo_action_button.dart';

class CityMapScreen extends StatefulWidget {
  const CityMapScreen({
    required this.onOpenScenario,
    this.isPilot = false,
    super.key,
  });

  final ValueChanged<CityScenario> onOpenScenario;
  final bool isPilot;

  @override
  State<CityMapScreen> createState() => _CityMapScreenState();
}

class _CityMapScreenState extends State<CityMapScreen>
    with TickerProviderStateMixin {
  static const _mapSize = Size(560, 1080);
  final TransformationController _transformation = TransformationController();
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1050),
  );
  late final AnimationController _storm = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );
  late final AnimationController _discovery = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1650),
  );

  Size _viewport = Size.zero;
  CityScenario _selected = cityScenarios.first;
  bool _simulatedDiscovery = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1;
      _storm.stop();
    } else {
      if (_intro.value == 0) _intro.forward();
      if (!_storm.isAnimating) _storm.repeat();
    }
  }

  @override
  void dispose() {
    _transformation.dispose();
    _intro.dispose();
    _storm.dispose();
    _discovery.dispose();
    super.dispose();
  }

  void _centerCurrent([Size? viewport]) {
    final size = viewport ?? _viewport;
    if (size.isEmpty) return;
    final scale = (size.width / _mapSize.width).clamp(0.58, 0.78);
    final focusY = _simulatedDiscovery ? 420.0 : 750.0;
    _transformation.value = Matrix4.identity()
      ..translateByDouble(
        (size.width - _mapSize.width * scale) / 2,
        (size.height / 2) - focusY * scale,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, scale, 1);
  }

  Future<void> _toggleDiscovery() async {
    if (_simulatedDiscovery) {
      _discovery.value = 0;
      setState(() {
        _simulatedDiscovery = false;
        _selected = cityScenarios.first;
      });
      _centerCurrent();
      return;
    }
    setState(() => _simulatedDiscovery = true);
    if (MediaQuery.disableAnimationsOf(context)) {
      _discovery.value = 1;
    } else {
      await _discovery.forward(from: 0);
    }
    if (!mounted) return;
    setState(() => _selected = cityScenarios[1]);
    _centerCurrent();
  }

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final panelHeight = largeText ? 448.0 : 202.0;
    return Scaffold(
      backgroundColor: const Color(0xFF07122F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF07122F),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('BinGópolis'),
            if (!largeText)
              const Text(
                'Mapa de restauração',
                style: TextStyle(fontSize: 12, color: Color(0xFFB9C9E7)),
              ),
          ],
        ),
        actions: [
          _SimulatedDataBadge(compact: largeText),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            bottom: panelHeight - 22,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final viewport = constraints.biggest;
                if (_viewport != viewport) {
                  _viewport = viewport;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _centerCurrent(viewport);
                  });
                }
                return ClipRect(
                  child: InteractiveViewer(
                    key: const ValueKey('bingopolis-interactive-map'),
                    transformationController: _transformation,
                    constrained: false,
                    boundaryMargin: const EdgeInsets.all(130),
                    minScale: 0.52,
                    maxScale: 1.8,
                    child: SizedBox.fromSize(
                      size: _mapSize,
                      child: AnimatedBuilder(
                        animation: Listenable.merge([
                          _intro,
                          _storm,
                          _discovery,
                        ]),
                        builder: (context, _) => _TerritoryCanvas(
                          intro: Curves.easeOutCubic.transform(_intro.value),
                          stormPhase: _storm.value,
                          discovery: Curves.easeInOutCubic.transform(
                            _discovery.value,
                          ),
                          selectedId: _selected.id,
                          onSelect: (scenario) =>
                              setState(() => _selected = scenario),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            right: 14,
            bottom: panelHeight + 2,
            child: Tooltip(
              message: 'Voltar ao setor atual',
              child: IconButton.filled(
                key: const ValueKey('recenter-bingopolis-map'),
                onPressed: _centerCurrent,
                icon: const Icon(Icons.my_location_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.blue,
                  shadowColor: Colors.black45,
                  elevation: 5,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _ScenarioPanel(
              height: panelHeight,
              scenario: _selected,
              progress: _selected.id == 'central-square'
                  ? (_simulatedDiscovery ? 1 : currentScenario.restoredProgress)
                  : 0,
              discovered:
                  _selected.id == 'central-square' ||
                  (_simulatedDiscovery && _selected.id == 'spring-park'),
              isPilot: widget.isPilot,
              simulatedDiscovery: _simulatedDiscovery,
              onOpen: () => widget.onOpenScenario(_selected),
              onSimulate: _toggleDiscovery,
            ),
          ),
        ],
      ),
    );
  }
}

class _TerritoryCanvas extends StatelessWidget {
  const _TerritoryCanvas({
    required this.intro,
    required this.stormPhase,
    required this.discovery,
    required this.selectedId,
    required this.onSelect,
  });

  final double intro;
  final double stormPhase;
  final double discovery;
  final String selectedId;
  final ValueChanged<CityScenario> onSelect;

  @override
  Widget build(BuildContext context) {
    final squareReveal = intro;
    final parkReveal = (0.13 + discovery * 0.87) * intro;
    final pathReveal = (0.42 + discovery * 0.58) * intro;
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _WorldPainter(stormPhase: stormPhase)),
        CustomPaint(
          painter: _JourneyPathPainter(
            reveal: pathReveal,
            discovery: discovery,
            stormPhase: stormPhase,
          ),
        ),
        Positioned(
          left: 148,
          top: 716,
          child: _TerritoryNode(
            key: const ValueKey('scenario-marker-central-square'),
            scenario: cityScenarios[0],
            progress: 0.68 + discovery * 0.32,
            reveal: squareReveal,
            selected: selectedId == cityScenarios[0].id,
            onTap: () => onSelect(cityScenarios[0]),
          ),
        ),
        Positioned(
          left: 174,
          top: 350,
          child: _TerritoryNode(
            key: const ValueKey('scenario-marker-spring-park'),
            scenario: cityScenarios[1],
            progress: 0,
            reveal: parkReveal,
            obscured: discovery < 1,
            selected: selectedId == cityScenarios[1].id,
            onTap: discovery >= 1 ? () => onSelect(cityScenarios[1]) : null,
          ),
        ),
        if (discovery >= 1)
          Positioned(
            left: 230,
            top: 208,
            child: _NextRouteHint(stormPhase: stormPhase),
          ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _StormVeilPainter(
                reveal: squareReveal,
                discovery: discovery,
                phase: stormPhase,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TerritoryNode extends StatelessWidget {
  const _TerritoryNode({
    required this.scenario,
    required this.progress,
    required this.reveal,
    required this.selected,
    required this.onTap,
    this.obscured = false,
    super.key,
  });

  final CityScenario scenario;
  final double progress;
  final double reveal;
  final bool selected;
  final bool obscured;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final phase = scenario.phaseFor(progress);
    final tone = phase == ScenarioVisualPhase.restored
        ? AppColors.green
        : phase == ScenarioVisualPhase.combat
        ? AppColors.blue
        : AppColors.scr4p;
    return Transform.scale(
      scale: 0.78 + reveal * 0.22,
      child: Opacity(
        opacity: (0.18 + reveal * 0.82).clamp(0, 1),
        child: Semantics(
          button: onTap != null,
          label: '${scenario.name}, ${scenario.restoredPercent}% restaurado',
          child: GestureDetector(
            onTap: onTap,
            child: SizedBox(
              width: 236,
              height: 236,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: phase == ScenarioVisualPhase.corrupted
                            ? const [Color(0xFF35104E), Color(0xFF190C35)]
                            : const [Color(0xFF164A6A), Color(0xFF102B4F)],
                      ),
                      border: Border.all(
                        color: selected ? Colors.white : tone,
                        width: selected ? 5 : 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: tone.withValues(alpha: selected ? 0.72 : 0.38),
                          blurRadius: selected ? 32 : 20,
                          spreadRadius: selected ? 4 : 0,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _TerritoryProgressPainter(
                              progress: progress,
                              tone: tone,
                            ),
                          ),
                        ),
                        Container(
                          width: 174,
                          height: 174,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.08),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.16),
                            ),
                          ),
                        ),
                        Image.asset(
                          scenario.mapLandmarkAsset,
                          width: 166,
                          height: 166,
                          fit: BoxFit.contain,
                          opacity: AlwaysStoppedAnimation(obscured ? 0.28 : 1),
                        ),
                        if (phase == ScenarioVisualPhase.combat && !obscured)
                          Positioned(
                            top: 22,
                            right: 25,
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: AppColors.scr4p,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black38,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.bolt_rounded,
                                color: Colors.white,
                                size: 21,
                              ),
                            ),
                          ),
                        if (obscured)
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.scr4p.withValues(alpha: 0.34),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: 3,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 205),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xF20B1836),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: tone),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(scenario.landmarkIcon, size: 18, color: tone),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              obscured ? 'Próximo setor' : scenario.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScenarioPanel extends StatelessWidget {
  const _ScenarioPanel({
    required this.height,
    required this.scenario,
    required this.progress,
    required this.discovered,
    required this.isPilot,
    required this.simulatedDiscovery,
    required this.onOpen,
    required this.onSimulate,
  });

  final double height;
  final CityScenario scenario;
  final double progress;
  final bool discovered;
  final bool isPilot;
  final bool simulatedDiscovery;
  final VoidCallback onOpen;
  final VoidCallback onSimulate;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final phase = scenario.phaseFor(progress);
    final status = !discovered
        ? 'Oculto pela tempestade'
        : progress == 0
        ? 'Sob corrupção'
        : phase == ScenarioVisualPhase.combat
        ? '${(progress * 100).round()}% restaurada · Em recuperação'
        : 'Setor restaurado';
    return Container(
      key: const ValueKey('bingopolis-scenario-panel'),
      height: height,
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, largeText ? 13 : 16, 20, 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF7FAFF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 28,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: (progress > 0 ? AppColors.green : AppColors.scr4p)
                        .withValues(alpha: 0.13),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    scenario.landmarkIcon,
                    color: progress > 0 ? AppColors.green : AppColors.scr4p,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        scenario.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        status,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (progress > 0)
                  Text(
                    '${(progress * 100).round()}%',
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(color: AppColors.green),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (progress > 0)
              LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                borderRadius: BorderRadius.circular(99),
                backgroundColor: AppColors.scr4p.withValues(alpha: 0.16),
                valueColor: const AlwaysStoppedAnimation(AppColors.green),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.recycling_rounded,
                  size: 17,
                  color: discovered ? AppColors.deepCyan : AppColors.scr4p,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    discovered
                        ? 'Cada descarte correto faz a tempestade recuar.'
                        : scenario.unlockRequirement,
                    maxLines: largeText ? 3 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (largeText)
              _PanelActionsColumn(
                discovered: discovered,
                isPilot: isPilot,
                simulatedDiscovery: simulatedDiscovery,
                onOpen: onOpen,
                onSimulate: onSimulate,
              )
            else
              Row(
                children: [
                  if (isPilot)
                    Expanded(
                      child: BingoActionButton(
                        label: simulatedDiscovery
                            ? 'Reiniciar mapa'
                            : 'Simular descoberta',
                        icon: simulatedDiscovery
                            ? Icons.restart_alt_rounded
                            : Icons.auto_awesome_rounded,
                        style: BingoActionStyle.secondary,
                        onPressed: onSimulate,
                      ),
                    ),
                  if (isPilot && discovered) const SizedBox(width: 10),
                  if (discovered)
                    Expanded(
                      child: BingoActionButton(
                        label: 'Ver cenário',
                        icon: Icons.arrow_forward_rounded,
                        tone: BingoActionTone.green,
                        onPressed: onOpen,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _TerritoryProgressPainter extends CustomPainter {
  const _TerritoryProgressPainter({required this.progress, required this.tone});

  final double progress;
  final Color tone;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 10;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..color = Colors.white.withValues(alpha: 0.1);
    final restored = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 7
      ..shader = SweepGradient(
        colors: [tone, AppColors.green, AppColors.deepCyan],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, base);
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        restored,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TerritoryProgressPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.tone != tone;
}

class _PanelActionsColumn extends StatelessWidget {
  const _PanelActionsColumn({
    required this.discovered,
    required this.isPilot,
    required this.simulatedDiscovery,
    required this.onOpen,
    required this.onSimulate,
  });

  final bool discovered;
  final bool isPilot;
  final bool simulatedDiscovery;
  final VoidCallback onOpen;
  final VoidCallback onSimulate;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (discovered)
          BingoActionButton(
            label: 'Ver cenário',
            icon: Icons.arrow_forward_rounded,
            tone: BingoActionTone.green,
            onPressed: onOpen,
          ),
        if (isPilot && discovered) const SizedBox(height: 8),
        if (isPilot)
          BingoActionButton(
            label: simulatedDiscovery
                ? 'Reiniciar demonstração'
                : 'Simular descoberta de setor',
            icon: simulatedDiscovery
                ? Icons.restart_alt_rounded
                : Icons.auto_awesome_rounded,
            style: BingoActionStyle.secondary,
            onPressed: onSimulate,
          ),
      ],
    );
  }
}

class _WorldPainter extends CustomPainter {
  const _WorldPainter({required this.stormPhase});

  final double stormPhase;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF160B38), Color(0xFF102A55), Color(0xFF0B2449)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    final grid = Paint()
      ..color = const Color(0xFF5AC8FA).withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (var y = 40.0; y < size.height; y += 48) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (var x = 20.0; x < size.width; x += 48) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }

    final stars = Paint()..color = Colors.white.withValues(alpha: 0.34);
    for (var i = 0; i < 34; i++) {
      final x = ((i * 83) % 541).toDouble();
      final y = ((i * 137) % 1061).toDouble();
      final pulse = 0.8 + math.sin(stormPhase * math.pi * 2 + i) * 0.4;
      canvas.drawCircle(Offset(x, y), pulse, stars);
    }
  }

  @override
  bool shouldRepaint(covariant _WorldPainter oldDelegate) =>
      oldDelegate.stormPhase != stormPhase;
}

class _JourneyPathPainter extends CustomPainter {
  const _JourneyPathPainter({
    required this.reveal,
    required this.discovery,
    required this.stormPhase,
  });

  final double reveal;
  final double discovery;
  final double stormPhase;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(280, 760)
      ..cubicTo(430, 660, 128, 566, 292, 455);
    final metric = path.computeMetrics().first;
    final visible = metric.extractPath(0, metric.length * reveal);
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 18
      ..color = AppColors.green.withValues(alpha: 0.12 + discovery * 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 6
      ..shader = const LinearGradient(
        colors: [AppColors.green, AppColors.deepCyan, AppColors.blue],
      ).createShader(const Rect.fromLTWH(100, 360, 360, 420));
    canvas.drawPath(visible, glow);
    canvas.drawPath(visible, line);

    final spark = metric.getTangentForOffset(metric.length * reveal);
    if (spark != null) {
      final pulse = 6 + math.sin(stormPhase * math.pi * 2) * 2;
      canvas.drawCircle(
        spark.position,
        pulse,
        Paint()..color = Colors.white.withValues(alpha: 0.9),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _JourneyPathPainter oldDelegate) => true;
}

class _StormVeilPainter extends CustomPainter {
  const _StormVeilPainter({
    required this.reveal,
    required this.discovery,
    required this.phase,
  });

  final double reveal;
  final double discovery;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    final storm = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.35),
        radius: 1.1,
        colors: [
          const Color(0xFF45127A).withValues(alpha: 0.9),
          const Color(0xFF160426).withValues(alpha: 0.98),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, storm);

    final clear = Paint()
      ..blendMode = BlendMode.clear
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 42);
    final squareRadius = 70 + 190 * reveal;
    canvas.drawCircle(const Offset(266, 828), squareRadius, clear);
    canvas.drawCircle(
      const Offset(292, 460),
      54 + 161 * discovery,
      clear,
    );
    canvas.restore();

    final cloud = Paint()
      ..color = const Color(0xFF8E35D8).withValues(alpha: 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);
    for (var i = 0; i < 18; i++) {
      final angle = (i / 18) * math.pi * 2 + phase * 0.22;
      final radius = 205 + (i % 3) * 34;
      final center = Offset(
        280 + math.cos(angle) * radius,
        810 + math.sin(angle) * radius,
      );
      canvas.drawCircle(center, 48 + (i % 4) * 9, cloud);
    }
    if (discovery < 1) {
      final lightning = Paint()
        ..color = Colors.white.withValues(
          alpha: 0.18 + math.max(0, math.sin(phase * math.pi * 8)) * 0.45,
        )
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      final bolt = Path()
        ..moveTo(360, 290)
        ..lineTo(330, 350)
        ..lineTo(355, 346)
        ..lineTo(320, 410);
      canvas.drawPath(bolt, lightning);
    }
  }

  @override
  bool shouldRepaint(covariant _StormVeilPainter oldDelegate) => true;
}

class _NextRouteHint extends StatelessWidget {
  const _NextRouteHint({required this.stormPhase});

  final double stormPhase;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.3 + math.sin(stormPhase * math.pi * 2).abs() * 0.2,
      child: const Icon(
        Icons.more_vert_rounded,
        color: AppColors.scr4p,
        size: 72,
      ),
    );
  }
}

class _SimulatedDataBadge extends StatelessWidget {
  const _SimulatedDataBadge({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Tooltip(
        message: 'Dados simulados',
        child: Semantics(
          label: 'Dados simulados',
          child: const Padding(
            padding: EdgeInsets.all(10),
            child: Icon(
              Icons.info_outline_rounded,
              size: 20,
              color: Colors.white70,
            ),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white24),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 14, color: Colors.white70),
          SizedBox(width: 4),
          Text(
            'Dados simulados',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
