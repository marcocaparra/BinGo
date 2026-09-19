import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/demo_data.dart';
import '../theme/app_assets.dart';
import '../theme/app_theme.dart';
import '../widgets/bingo_action_button.dart';

double _intervalValue(double value, double begin, double end, Curve curve) {
  if (value <= begin) return 0;
  if (value >= end) return 1;
  return curve.transform((value - begin) / (end - begin));
}

Color _territoryTone(double progress) {
  if (progress >= 0.85) {
    return Color.lerp(
      AppColors.deepCyan,
      AppColors.green,
      (progress - 0.85) / 0.15,
    )!;
  }
  return Color.lerp(AppColors.scr4p, AppColors.deepCyan, progress / 0.85)!;
}

class CityMapScreen extends StatefulWidget {
  const CityMapScreen({
    required this.onOpenScenario,
    this.isPilot = false,
    this.dataAvailable = true,
    super.key,
  });

  final void Function(CityScenario scenario, double visualProgress)
  onOpenScenario;
  final bool isPilot;
  final bool dataAvailable;

  @override
  State<CityMapScreen> createState() => _CityMapScreenState();
}

class _CityMapScreenState extends State<CityMapScreen>
    with TickerProviderStateMixin {
  final TransformationController _transformation = TransformationController();
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1050),
  );
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  );
  late final AnimationController _progression = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..addListener(_updateProgressionCamera);
  late final AnimationController _resetFade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final AnimationController _guide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );

  Size _viewport = Size.zero;
  int _activeScenarioIndex = 0;
  CityScenario _selected = cityScenarios.first;
  bool _transitioning = false;
  bool _guideExpanded = true;
  bool _initialized = false;
  Timer? _guideTimer;
  Matrix4? _cameraBegin;
  Matrix4? _cameraEnd;
  bool _assetsPrecached = false;

  List<_ScenarioMapNode> get _nodes => [
    for (var index = 0; index < cityScenarios.length; index++)
      _ScenarioMapNode(
        scenario: cityScenarios[index],
        journeyIndex: index,
        lane: switch (index % 3) {
          0 => 0.5,
          1 => 0.44,
          _ => 0.56,
        },
      ),
  ];

  double get _worldHeight => 900 + math.max(3, _nodes.length) * 500;
  Size get _worldSize => Size(2400, _worldHeight);
  int get _stageIndex => _activeScenarioIndex.clamp(0, _nodes.length - 1);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_assetsPrecached) {
      for (final scenario in cityScenarios) {
        precacheImage(
          ResizeImage(AssetImage(scenario.mapLandmarkAsset), width: 384),
          context,
        );
        precacheImage(
          ResizeImage(AssetImage(scenario.corruptMapLandmarkAsset), width: 384),
          context,
        );
      }
      _assetsPrecached = true;
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _intro.value = 1;
      _guide.value = 1;
      _guideExpanded = false;
      _ambient.stop();
    } else {
      if (_intro.value == 0) _intro.forward();
      if (!_ambient.isAnimating) _ambient.repeat();
      if (!_initialized) {
        _guide.forward();
        _guideTimer = Timer(const Duration(milliseconds: 2400), _hideGuide);
      }
    }
    _initialized = true;
  }

  @override
  void dispose() {
    _guideTimer?.cancel();
    _transformation.dispose();
    _intro.dispose();
    _ambient.dispose();
    _progression.dispose();
    _resetFade.dispose();
    _guide.dispose();
    super.dispose();
  }

  Offset _nodeCenter(int index) {
    final node = _nodes[index];
    return Offset(
      node.lane * _worldSize.width,
      _worldHeight - 390 - node.journeyIndex * 500,
    );
  }

  Matrix4 _matrixForStage(int index, Size size) {
    final scale = (size.width / 760).clamp(0.48, 0.66);
    final focus = _nodeCenter(index);
    return Matrix4.identity()
      ..translateByDouble(
        size.width / 2 - focus.dx * scale,
        size.height / 2 - focus.dy * scale,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, scale, 1);
  }

  void _centerStage({int? index, Size? viewport}) {
    final size = viewport ?? _viewport;
    if (size.isEmpty) return;
    final targetIndex = index ?? _stageIndex;
    _transformation.value = _matrixForStage(targetIndex, size);
  }

  void _updateProgressionCamera() {
    if (!_transitioning || _cameraBegin == null || _cameraEnd == null) return;
    final t = _intervalValue(
      _progression.value,
      0.68,
      1,
      Curves.easeInOutCubic,
    );
    _transformation.value = Matrix4Tween(
      begin: _cameraBegin,
      end: _cameraEnd,
    ).transform(t);
  }

  Future<void> _advanceJourney() async {
    if (_transitioning) return;
    if (_stageIndex >= _nodes.length - 1) {
      if (MediaQuery.disableAnimationsOf(context)) {
        setState(() {
          _activeScenarioIndex = 0;
          _selected = cityScenarios.first;
        });
        _centerStage(index: 0);
      } else {
        setState(() => _transitioning = true);
        await _resetFade.forward(from: 0);
        if (!mounted) return;
        setState(() {
          _activeScenarioIndex = 0;
          _selected = cityScenarios.first;
        });
        _progression.value = 0;
        _centerStage(index: 0);
        await _resetFade.reverse();
        if (mounted) setState(() => _transitioning = false);
      }
      return;
    }
    setState(() => _transitioning = true);
    final nextIndex = _stageIndex + 1;
    if (MediaQuery.disableAnimationsOf(context)) {
      _progression.value = 1;
    } else {
      _cameraBegin = Matrix4.copy(_transformation.value);
      _cameraEnd = _matrixForStage(nextIndex, _viewport);
      await _progression.forward(from: 0);
    }
    if (!mounted) return;
    setState(() {
      _activeScenarioIndex = nextIndex;
      _selected = cityScenarios[nextIndex];
      _transitioning = false;
    });
    _progression.value = 0;
    _cameraBegin = null;
    _cameraEnd = null;
    _centerStage(index: nextIndex);
  }

  void _hideGuide() {
    if (!mounted || !_guideExpanded) return;
    setState(() => _guideExpanded = false);
  }

  void _showGuide() {
    _guideTimer?.cancel();
    setState(() => _guideExpanded = true);
    if (!MediaQuery.disableAnimationsOf(context)) {
      _guide.forward(from: 0);
    }
  }

  double _progressFor(int index) {
    if (index < _stageIndex) return 1;
    if (index > _stageIndex) return 0;
    final base = cityScenarios[index].progress;
    final cleanup = _intervalValue(
      _progression.value,
      0.08,
      0.52,
      Curves.easeInOutCubic,
    );
    return _transitioning ? base + (1 - base) * cleanup : base;
  }

  bool _isDiscovered(int index) => index <= _stageIndex;

  @override
  Widget build(BuildContext context) {
    if (!widget.dataAvailable) {
      return _UnavailableCityMap();
    }
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final selectedIndex = cityScenarios.indexWhere(
      (scenario) => scenario.id == _selected.id,
    );
    return Scaffold(
      backgroundColor: const Color(0xFF9ADE3D),
      appBar: AppBar(
        backgroundColor: const Color(0xF20B234A),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('BinGópolis'),
            if (!largeText)
              const Text(
                'Jornada coletiva de restauração',
                style: TextStyle(fontSize: 12, color: Color(0xFFD6E8FF)),
              ),
          ],
        ),
        actions: [
          _SimulatedDataBadge(compact: largeText),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                key: const ValueKey('bingopolis-world-backdrop'),
                color: const Color(0xFF9ADE3D),
                child: Image.asset(
                  AppAssets.bingopolisTerrainTile,
                  fit: BoxFit.cover,
                  opacity: const AlwaysStoppedAnimation(0.68),
                ),
              ),
            ),
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewport = constraints.biggest;
                  if (_viewport != viewport) {
                    _viewport = viewport;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _centerStage(viewport: viewport);
                    });
                  }
                  return AnimatedBuilder(
                    animation: _resetFade,
                    builder: (context, _) => Opacity(
                      opacity: 1 - _resetFade.value,
                      child: IgnorePointer(
                        key: const ValueKey('bingopolis-map-interaction-lock'),
                        ignoring: _transitioning,
                        child: ClipRect(
                          child: InteractiveViewer(
                            key: const ValueKey('bingopolis-interactive-map'),
                            transformationController: _transformation,
                            constrained: false,
                            boundaryMargin: EdgeInsets.zero,
                            minScale: 0.42,
                            maxScale: 1.75,
                            child: SizedBox.fromSize(
                              size: _worldSize,
                              child: AnimatedBuilder(
                                animation: Listenable.merge([
                                  _intro,
                                  _ambient,
                                  _progression,
                                ]),
                                builder: (context, _) => _ExpandableMapCanvas(
                                  size: _worldSize,
                                  nodes: _nodes,
                                  intro: Curves.easeOutCubic.transform(
                                    _intro.value,
                                  ),
                                  ambient: _ambient.value,
                                  stageIndex: _stageIndex,
                                  discovery: _progression.value,
                                  transitioning: _transitioning,
                                  selectedId: _selected.id,
                                  nodeCenter: _nodeCenter,
                                  onSelect: (scenario) =>
                                      setState(() => _selected = scenario),
                                ),
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
            if (!_guideExpanded)
              Positioned(
                right: 14,
                top: 14,
                child: Tooltip(
                  message: 'Voltar ao setor atual',
                  child: IconButton.filled(
                    key: const ValueKey('recenter-bingopolis-map'),
                    onPressed: _centerStage,
                    icon: const Icon(Icons.my_location_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.blue,
                      elevation: 5,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 14,
              top: 14,
              child: _guideExpanded
                  ? _B1nMapGuide(animation: _guide, onClose: _hideGuide)
                  : Tooltip(
                      message: 'Ajuda do B1N',
                      child: IconButton.filled(
                        key: const ValueKey('show-b1n-map-guide'),
                        onPressed: _showGuide,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.blue,
                          elevation: 4,
                        ),
                        icon: ClipOval(
                          child: Image.asset(
                            AppAssets.b1nMapGuide,
                            width: 34,
                            height: 34,
                            fit: BoxFit.cover,
                            alignment: const Alignment(0, -0.65),
                          ),
                        ),
                      ),
                    ),
            ),
            AnimatedBuilder(
              animation: _progression,
              builder: (context, _) => _ScenarioSheet(
                scenario: _selected,
                progress: _progressFor(selectedIndex),
                discovered: _isDiscovered(selectedIndex),
                isPilot: widget.isPilot,
                stageIndex: _stageIndex,
                lastStage: _nodes.length - 1,
                transitioning: _transitioning,
                onOpen: () => widget.onOpenScenario(
                  _selected,
                  _progressFor(selectedIndex),
                ),
                onAdvance: _advanceJourney,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnavailableCityMap extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF9ADE3D),
      appBar: AppBar(
        backgroundColor: const Color(0xF20B234A),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('BinGópolis'),
            Text(
              'Jornada coletiva de restauração',
              style: TextStyle(fontSize: 12, color: Color(0xFFD6E8FF)),
            ),
          ],
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            AppAssets.bingopolisTerrainTile,
            fit: BoxFit.cover,
            opacity: const AlwaysStoppedAnimation(0.68),
          ),
          Container(color: const Color(0x660B234A)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Spacer(),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 24,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Image.asset(
                          AppAssets.b1nMapGuide,
                          height: 110,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Ainda não há dados',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'O mapa está pronto para receber cenários e progresso da campanha autenticada.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScenarioMapNode {
  const _ScenarioMapNode({
    required this.scenario,
    required this.journeyIndex,
    required this.lane,
  });

  final CityScenario scenario;
  final int journeyIndex;
  final double lane;
}

class _ExpandableMapCanvas extends StatelessWidget {
  const _ExpandableMapCanvas({
    required this.size,
    required this.nodes,
    required this.intro,
    required this.ambient,
    required this.stageIndex,
    required this.discovery,
    required this.transitioning,
    required this.selectedId,
    required this.nodeCenter,
    required this.onSelect,
  });

  final Size size;
  final List<_ScenarioMapNode> nodes;
  final double intro;
  final double ambient;
  final int stageIndex;
  final double discovery;
  final bool transitioning;
  final String selectedId;
  final Offset Function(int index) nodeCenter;
  final ValueChanged<CityScenario> onSelect;

  @override
  Widget build(BuildContext context) {
    final cleanup = _intervalValue(
      discovery,
      0.08,
      0.52,
      Curves.easeInOutCubic,
    );
    final celebration = _intervalValue(
      discovery,
      0.4,
      0.66,
      Curves.easeOutBack,
    );
    final fogReveal = _intervalValue(
      discovery,
      0.28,
      0.74,
      Curves.easeInOutCubic,
    );
    final pathReveal = _intervalValue(
      discovery,
      0.54,
      0.84,
      Curves.easeInOutCubic,
    );
    final nextReveal = _intervalValue(discovery, 0.72, 1, Curves.easeOutBack);
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: _ExpandableTerrain(size: size)),
        RepaintBoundary(
          child: CustomPaint(
            painter: _TerrainFeaturesPainter(
              centers: [for (var i = 0; i < nodes.length; i++) nodeCenter(i)],
            ),
          ),
        ),
        CustomPaint(
          painter: _JourneyPathPainter(
            centers: [for (var i = 0; i < nodes.length; i++) nodeCenter(i)],
            stageIndex: stageIndex,
            discovery: pathReveal,
            ambient: ambient,
          ),
        ),
        for (var index = 0; index < nodes.length; index++)
          if (_visibilityFor(index, nextReveal) > 0)
            Positioned(
              left: nodeCenter(index).dx - 118,
              top: nodeCenter(index).dy - 118,
              child: _TerritoryNode(
                key: ValueKey('scenario-marker-${nodes[index].scenario.id}'),
                scenario: nodes[index].scenario,
                progress: _progressFor(index, cleanup),
                reveal: _visibilityFor(index, nextReveal) * intro,
                obscured:
                    index > stageIndex ||
                    (transitioning && index == stageIndex + 1),
                selected: selectedId == nodes[index].scenario.id,
                ambient: ambient,
                restorationPulse: transitioning && index == stageIndex
                    ? celebration
                    : 0,
                onTap: index <= stageIndex
                    ? () => onSelect(nodes[index].scenario)
                    : null,
              ),
            ),
        Positioned.fill(
          child: IgnorePointer(
            child: _StormField(
              size: size,
              centers: [for (var i = 0; i < nodes.length; i++) nodeCenter(i)],
              stageIndex: stageIndex,
              discovery: fogReveal,
              intro: intro,
              ambient: ambient,
            ),
          ),
        ),
      ],
    );
  }

  double _visibilityFor(int index, double nextReveal) {
    if (index <= stageIndex) return 1;
    if (index == stageIndex + 1 && (stageIndex > 0 || index == 1)) {
      return 0.18 + nextReveal * 0.82;
    }
    return 0;
  }

  double _progressFor(int index, double cleanup) {
    if (index < stageIndex) return 1;
    if (index > stageIndex) return 0;
    final base = nodes[index].scenario.progress;
    return transitioning ? base + (1 - base) * cleanup : base;
  }
}

class _ExpandableTerrain extends StatelessWidget {
  const _ExpandableTerrain({required this.size});

  final Size size;

  @override
  Widget build(BuildContext context) {
    const tileHeight = 700.0;
    const stride = 560.0;
    final count = ((size.height + 140) / stride).ceil();
    final columns = (size.width / 620).ceil();
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF9ADE3D)),
      child: Stack(
        children: [
          for (var index = 0; index < count; index++)
            Positioned(
              left: 0,
              right: 0,
              top: index * stride - 70,
              height: tileHeight,
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black,
                    Colors.black,
                    Colors.transparent,
                  ],
                  stops: [0, 0.18, 0.82, 1],
                ).createShader(bounds),
                child: Row(
                  children: [
                    for (var column = 0; column < columns; column++)
                      Expanded(
                        child: Transform.flip(
                          flipX: (index + column).isOdd,
                          flipY: index.isOdd,
                          child: Image.asset(
                            AppAssets.bingopolisTerrainTile,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TerritoryNode extends StatelessWidget {
  const _TerritoryNode({
    required this.scenario,
    required this.progress,
    required this.reveal,
    required this.obscured,
    required this.selected,
    required this.ambient,
    required this.restorationPulse,
    required this.onTap,
    super.key,
  });

  final CityScenario scenario;
  final double progress;
  final double reveal;
  final bool obscured;
  final bool selected;
  final double ambient;
  final double restorationPulse;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tone = _territoryTone(progress);
    final surfaceStart = Color.lerp(
      const Color(0xFF36144F),
      const Color(0xFFF8FFE8),
      progress,
    )!;
    final surfaceEnd = Color.lerp(
      const Color(0xFF180B2A),
      const Color(0xFFBDEB7A),
      progress,
    )!;
    final drift = math.sin(ambient * math.pi * 2 + scenario.order) * 2.5;
    return Transform.translate(
      offset: Offset(0, drift),
      child: Transform.scale(
        scale: (0.78 + reveal * 0.22) * (selected ? 1.035 : 1),
        child: Opacity(
          opacity: (0.16 + reveal * 0.84).clamp(0, 1),
          child: Semantics(
            button: onTap != null,
            label: '${scenario.name}, ${(progress * 100).round()}% restaurado',
            child: GestureDetector(
              onTap: onTap,
              child: RepaintBoundary(
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
                            colors: [surfaceStart, surfaceEnd],
                          ),
                          border: Border.all(
                            color: selected ? Colors.white : tone,
                            width: selected ? 6 : 4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: tone.withValues(
                                alpha: selected ? 0.65 : 0.35,
                              ),
                              blurRadius: selected ? 30 : 18,
                              spreadRadius: selected ? 4 : 0,
                            ),
                            const BoxShadow(
                              color: Color(0x55044A35),
                              blurRadius: 0,
                              offset: Offset(0, 12),
                              spreadRadius: -2,
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
                                  phase: ambient,
                                  selected: selected,
                                  celebration: restorationPulse,
                                ),
                              ),
                            ),
                            _TransformingLandmark(
                              cleanAsset: scenario.mapLandmarkAsset,
                              corruptAsset: scenario.corruptMapLandmarkAsset,
                              progress: progress,
                              ambient: ambient,
                              celebration: restorationPulse,
                              selected: selected,
                              width: 172,
                              height: 172,
                              opacity: obscured ? 0.28 : 1,
                            ),
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _LandmarkAccentPainter(
                                  icon: scenario.landmarkIcon,
                                  phase: ambient,
                                  color: tone,
                                  hidden: obscured,
                                  progress: progress,
                                  celebration: restorationPulse,
                                ),
                              ),
                            ),
                            if (obscured)
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.scr4p.withValues(alpha: 0.3),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Positioned(
                        bottom: 2,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 210),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Color.lerp(
                              const Color(0xF238124F),
                              const Color(0xF20B234A),
                              progress,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: tone, width: 1.5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                scenario.landmarkIcon,
                                size: 17,
                                color: tone,
                              ),
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
        ),
      ),
    );
  }
}

class _TransformingLandmark extends StatelessWidget {
  const _TransformingLandmark({
    required this.cleanAsset,
    required this.corruptAsset,
    required this.progress,
    required this.ambient,
    required this.celebration,
    required this.selected,
    required this.width,
    required this.height,
    required this.opacity,
  });

  final String cleanAsset;
  final String corruptAsset;
  final double progress;
  final double ambient;
  final double celebration;
  final bool selected;
  final double width;
  final double height;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              cleanAsset,
              fit: BoxFit.contain,
              cacheWidth: 384,
              filterQuality: FilterQuality.high,
            ),
            Opacity(
              opacity: math.pow(1 - progress, 0.72).toDouble(),
              child: Image.asset(
                corruptAsset,
                fit: BoxFit.contain,
                cacheWidth: 384,
                filterQuality: FilterQuality.high,
              ),
            ),
            if (progress > 0.01 && progress < 0.99)
              CustomPaint(
                painter: _CorruptionDissolvePainter(
                  progress: progress,
                  phase: ambient,
                ),
              ),
            if (selected || celebration > 0)
              CustomPaint(
                painter: _LandmarkShimmerPainter(
                  phase: ambient,
                  celebration: celebration,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CorruptionDissolvePainter extends CustomPainter {
  const _CorruptionDissolvePainter({
    required this.progress,
    required this.phase,
  });

  final double progress;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final activity = math.sin(progress * math.pi);
    final paint = Paint()..style = PaintingStyle.fill;
    const seeds = <Offset>[
      Offset(.18, .34),
      Offset(.30, .62),
      Offset(.43, .25),
      Offset(.58, .72),
      Offset(.70, .40),
      Offset(.82, .57),
      Offset(.54, .48),
    ];
    for (var index = 0; index < seeds.length; index++) {
      final seed = seeds[index];
      final drift = math.sin(phase * math.pi * 2 + index * 1.7) * 3;
      final side = 3.0 + (index % 3) * 1.5;
      paint.color = Color.lerp(
        const Color(0xFF8B21D1),
        const Color(0xFF22D3EE),
        progress,
      )!.withValues(alpha: activity * (.24 + (index % 2) * .10));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(seed.dx * size.width + drift, seed.dy * size.height),
            width: side,
            height: side,
          ),
          const Radius.circular(1.2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CorruptionDissolvePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.phase != phase;
}

class _LandmarkShimmerPainter extends CustomPainter {
  const _LandmarkShimmerPainter({
    required this.phase,
    required this.celebration,
  });

  final double phase;
  final double celebration;

  @override
  void paint(Canvas canvas, Size size) {
    final travel = (phase * 1.35) % 1;
    final x = -size.width * 0.45 + size.width * 1.9 * travel;
    final rect = Rect.fromLTWH(x, -size.height * 0.2, 34, size.height * 1.4);
    canvas.save();
    canvas.rotate(-0.22);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: 0.2 + celebration * 0.38),
            AppColors.deepCyan.withValues(alpha: celebration * 0.32),
            Colors.transparent,
          ],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LandmarkShimmerPainter oldDelegate) => true;
}

class _StormField extends StatelessWidget {
  const _StormField({
    required this.size,
    required this.centers,
    required this.stageIndex,
    required this.discovery,
    required this.intro,
    required this.ambient,
  });

  final Size size;
  final List<Offset> centers;
  final int stageIndex;
  final double discovery;
  final double intro;
  final double ambient;

  @override
  Widget build(BuildContext context) {
    final shift = math.sin(ambient * math.pi * 2) * 18;
    final current = centers[stageIndex];
    final hasNext = stageIndex + 1 < centers.length;
    final currentFrontier = hasNext
        ? (current.dy + centers[stageIndex + 1].dy) / 2
        : current.dy - 330;
    final nextFrontier = stageIndex + 2 < centers.length
        ? (centers[stageIndex + 1].dy + centers[stageIndex + 2].dy) / 2
        : hasNext
        ? centers[stageIndex + 1].dy - 330
        : currentFrontier;
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: _StormMaskPainter(
            centers: centers,
            stageIndex: stageIndex,
            discovery: discovery,
            intro: intro,
            phase: ambient,
          ),
        ),
        if (discovery <= 0.001)
          _StormCloudBank(
            key: ValueKey('storm-bank-stage-$stageIndex'),
            bankId: 'storm-bank-stage-$stageIndex',
            size: size,
            frontier: currentFrontier,
            shift: shift,
            intro: intro,
          )
        else ...[
          _StormCloudBank(
            key: ValueKey('storm-bank-stage-${stageIndex + 1}'),
            bankId: 'storm-bank-stage-${stageIndex + 1}',
            size: size,
            frontier: nextFrontier,
            shift: shift,
            intro: intro,
          ),
          _StormCloudBank(
            key: ValueKey('storm-bank-retreat-$stageIndex'),
            bankId: 'storm-bank-retreat-$stageIndex',
            size: size,
            frontier: currentFrontier,
            shift: shift,
            intro: intro,
            retreatProgress: discovery,
            retreating: true,
          ),
        ],
      ],
    );
  }
}

class _StormCloudBank extends StatelessWidget {
  const _StormCloudBank({
    required this.bankId,
    required this.size,
    required this.frontier,
    required this.shift,
    required this.intro,
    this.retreatProgress = 0,
    this.retreating = false,
    super.key,
  });

  final String bankId;
  final Size size;
  final double frontier;
  final double shift;
  final double intro;
  final double retreatProgress;
  final bool retreating;

  @override
  Widget build(BuildContext context) {
    final rowCount = retreating
        ? 3
        : math.max(4, ((frontier + 360) / 235).ceil());
    final columnCount = (size.width / 500).ceil() + 1;
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var row = 0; row < rowCount; row++)
          for (var column = 0; column < columnCount; column++)
            Positioned(
              key: ValueKey('$bankId-cloud-$row-$column'),
              left:
                  column * 500 -
                  330 +
                  (row.isEven ? shift : -shift * 0.7) +
                  (retreating
                      ? (column < columnCount / 2 ? -1 : 1) *
                            retreatProgress *
                            (260 + (2 - row) * 95)
                      : 0),
              top:
                  frontier -
                  245 -
                  row * 235 +
                  (column.isEven ? -35 : 28) -
                  (retreating ? retreatProgress * (115 + (2 - row) * 35) : 0),
              width: 860 + (row % 3) * 90,
              child: Opacity(
                opacity:
                    ((0.72 + (row % 3) * 0.08) *
                            (0.9 + intro * 0.1) *
                            (retreating ? 1 - retreatProgress * 0.92 : 1))
                        .clamp(0, 1),
                child: Image.asset(switch ((row + column) % 3) {
                  0 => AppAssets.corruptionFogNear,
                  1 => AppAssets.corruptionFogMid,
                  _ => AppAssets.corruptionFogFar,
                }),
              ),
            ),
        Positioned(
          key: ValueKey('$bankId-left-edge'),
          left: -280 - shift * 0.35 - (retreating ? retreatProgress * 260 : 0),
          top: frontier + 120 - (retreating ? retreatProgress * 100 : 0),
          width: 760,
          child: Opacity(
            opacity: 0.56 * (retreating ? 1 - retreatProgress : 1),
            child: Image.asset(AppAssets.corruptionFogMid),
          ),
        ),
        Positioned(
          key: ValueKey('$bankId-right-edge'),
          right: -280 + shift * 0.3 - (retreating ? retreatProgress * 260 : 0),
          top: frontier + 80 - (retreating ? retreatProgress * 120 : 0),
          width: 760,
          child: Opacity(
            opacity: 0.52 * (retreating ? 1 - retreatProgress : 1),
            child: Image.asset(AppAssets.corruptionFogNear),
          ),
        ),
      ],
    );
  }
}

class _ScenarioSheet extends StatelessWidget {
  const _ScenarioSheet({
    required this.scenario,
    required this.progress,
    required this.discovered,
    required this.isPilot,
    required this.stageIndex,
    required this.lastStage,
    required this.transitioning,
    required this.onOpen,
    required this.onAdvance,
  });

  final CityScenario scenario;
  final double progress;
  final bool discovered;
  final bool isPilot;
  final int stageIndex;
  final int lastStage;
  final bool transitioning;
  final VoidCallback onOpen;
  final VoidCallback onAdvance;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    return DraggableScrollableSheet(
      key: const ValueKey('bingopolis-scenario-panel'),
      initialChildSize: largeText ? 0.31 : 0.25,
      minChildSize: largeText ? 0.28 : 0.22,
      maxChildSize: largeText ? 0.78 : 0.62,
      snap: true,
      snapSizes: largeText ? const [0.31, 0.78] : const [0.25, 0.62],
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF8FBFF),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 28,
              offset: Offset(0, -8),
            ),
          ],
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 9, 20, 26),
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: (progress > 0 ? AppColors.green : AppColors.scr4p)
                        .withValues(alpha: 0.14),
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
                        maxLines: largeText ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        discovered
                            ? progress >= 1
                                  ? 'Setor restaurado'
                                  : progress > 0
                                  ? '${(progress * 100).round()}% restaurada'
                                  : 'Sob corrupção'
                            : scenario.unlockRequirement,
                        maxLines: largeText ? 3 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (discovered && progress > 0)
                  Text(
                    '${(progress * 100).round()}%',
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(color: AppColors.green),
                  ),
              ],
            ),
            if (discovered && progress > 0) ...[
              const SizedBox(height: 9),
              LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                borderRadius: BorderRadius.circular(99),
                backgroundColor: AppColors.scr4p.withValues(alpha: 0.15),
                valueColor: const AlwaysStoppedAnimation(AppColors.green),
              ),
            ],
            const SizedBox(height: 13),
            Row(
              children: [
                if (discovered)
                  Expanded(
                    child: BingoActionButton(
                      label: 'Ver cenário',
                      icon: Icons.arrow_forward_rounded,
                      tone: BingoActionTone.green,
                      onPressed: onOpen,
                    ),
                  ),
                if (isPilot && discovered) const SizedBox(width: 10),
                if (isPilot && discovered)
                  Expanded(
                    child: BingoActionButton(
                      key: const ValueKey('advance-bingopolis-journey'),
                      label: stageIndex >= lastStage
                          ? 'Reiniciar demonstração'
                          : stageIndex == 0
                          ? 'Demonstrar Parque'
                          : 'Demonstrar Escola',
                      icon: stageIndex >= lastStage
                          ? Icons.restart_alt_rounded
                          : Icons.auto_awesome_rounded,
                      style: BingoActionStyle.secondary,
                      onPressed: transitioning ? null : onAdvance,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            _SheetInfoLine(
              icon: Icons.recycling_rounded,
              title: 'Como a cidade avança',
              text: 'Cada descarte validado ajuda a restaurar este setor.',
              color: AppColors.deepCyan,
            ),
            const SizedBox(height: 12),
            _SheetInfoLine(
              icon: Icons.route_rounded,
              title: 'Uma jornada que continua',
              text:
                  'Novos setores poderão surgir em ciclos futuros de BinGópolis.',
              color: AppColors.blue,
            ),
            if (!discovered) ...[
              const SizedBox(height: 12),
              _SheetInfoLine(
                icon: Icons.lock_outline_rounded,
                title: 'Condição de descoberta',
                text: scenario.unlockRequirement,
                color: AppColors.scr4p,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SheetInfoLine extends StatelessWidget {
  const _SheetInfoLine({
    required this.icon,
    required this.title,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 21),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(text, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _B1nMapGuide extends StatelessWidget {
  const _B1nMapGuide({required this.animation, required this.onClose});

  final Animation<double> animation;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: SlideTransition(
        position: Tween(begin: const Offset(-0.16, 0), end: Offset.zero)
            .animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
            ),
        child: Container(
          key: const ValueKey('b1n-map-guide'),
          width: (MediaQuery.sizeOf(context).width - 28).clamp(260, 330),
          height: 146,
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.deepCyan.withValues(alpha: 0.5),
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 18,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            children: [
              SizedBox(
                width: 110,
                child: Image.asset(AppAssets.b1nMapGuide, fit: BoxFit.contain),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'B1N',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppColors.blue,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Eu mostro o caminho. Cada descarte validado ajuda BinGópolis a avançar.',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  tooltip: 'Fechar ajuda',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TerrainFeaturesPainter extends CustomPainter {
  const _TerrainFeaturesPainter({required this.centers});

  final List<Offset> centers;

  @override
  void paint(Canvas canvas, Size size) {
    for (final center in centers) {
      canvas.drawCircle(
        center,
        145,
        Paint()..color = const Color(0xFFE8F9BA).withValues(alpha: 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TerrainFeaturesPainter oldDelegate) => false;
}

class _JourneyPathPainter extends CustomPainter {
  const _JourneyPathPainter({
    required this.centers,
    required this.stageIndex,
    required this.discovery,
    required this.ambient,
  });

  final List<Offset> centers;
  final int stageIndex;
  final double discovery;
  final double ambient;

  @override
  void paint(Canvas canvas, Size size) {
    for (var index = 0; index < centers.length - 1; index++) {
      final start = centers[index];
      final end = centers[index + 1];
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(
          (start.dx + end.dx) / 2 + (index.isEven ? -70 : 70),
          (start.dy + end.dy) / 2,
          end.dx,
          end.dy,
        );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 22
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFE7D19E).withValues(alpha: 0.82),
      );
      final active = index < stageIndex || index == stageIndex;
      if (!active) continue;
      final metric = path.computeMetrics().first;
      final reveal = index < stageIndex ? 1.0 : (0.28 + discovery * 0.72);
      final visible = metric.extractPath(0, metric.length * reveal);
      canvas.drawPath(
        visible,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round
          ..shader = const LinearGradient(
            colors: [AppColors.green, AppColors.deepCyan, AppColors.blue],
          ).createShader(Rect.fromPoints(start, end)),
      );
      final tangent = metric.getTangentForOffset(metric.length * reveal);
      if (tangent != null) {
        canvas.drawCircle(
          tangent.position,
          7 + math.sin(ambient * math.pi * 2) * 2,
          Paint()..color = Colors.white,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _JourneyPathPainter oldDelegate) => true;
}

class _StormMaskPainter extends CustomPainter {
  const _StormMaskPainter({
    required this.centers,
    required this.stageIndex,
    required this.discovery,
    required this.intro,
    required this.phase,
  });

  final List<Offset> centers;
  final int stageIndex;
  final double discovery;
  final double intro;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xA51C0538), Color(0x80581688), Color(0x5932105F)],
        ).createShader(Offset.zero & size),
    );
    final clear = Paint()
      ..blendMode = BlendMode.clear
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 52);
    for (var index = 0; index <= stageIndex; index++) {
      final radius = index == stageIndex
          ? (index == 0 ? 170.0 + 70 * intro : 190.0)
          : 245.0;
      canvas.drawCircle(centers[index], radius, clear);
    }
    if (stageIndex + 1 < centers.length) {
      canvas.drawCircle(centers[stageIndex + 1], 42 + 170 * discovery, clear);
    }
    canvas.restore();

    final particles = Paint()
      ..color = const Color(0xFFB35BFF).withValues(alpha: 0.55);
    for (var index = 0; index < 32; index++) {
      final x = ((index * 97) % size.width.toInt()).toDouble();
      final y = ((index * 173 + phase * 90) % size.height).toDouble();
      canvas.drawCircle(Offset(x, y), 2 + index % 3, particles);
    }
  }

  @override
  bool shouldRepaint(covariant _StormMaskPainter oldDelegate) => true;
}

class _TerritoryProgressPainter extends CustomPainter {
  const _TerritoryProgressPainter({
    required this.progress,
    required this.tone,
    required this.phase,
    required this.selected,
    required this.celebration,
  });

  final double progress;
  final Color tone;
  final double phase;
  final bool selected;
  final double celebration;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 10;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = Colors.white.withValues(alpha: 0.26),
    );
    if (progress <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 7
        ..shader = SweepGradient(
          transform: GradientRotation(phase * math.pi * 2),
          colors: [tone, AppColors.green, AppColors.deepCyan],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    if (selected) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        phase * math.pi * 2 - math.pi / 2,
        math.pi * 0.28,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 3
          ..color = Colors.white.withValues(alpha: 0.78),
      );
    }
    if (celebration > 0) {
      final burst = math.sin(celebration.clamp(0, 1) * math.pi);
      canvas.drawCircle(
        center,
        radius + 7 + burst * 13,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = AppColors.deepCyan.withValues(alpha: burst * 0.72),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TerritoryProgressPainter oldDelegate) => true;
}

class _LandmarkAccentPainter extends CustomPainter {
  const _LandmarkAccentPainter({
    required this.icon,
    required this.phase,
    required this.color,
    required this.hidden,
    required this.progress,
    required this.celebration,
  });

  final IconData icon;
  final double phase;
  final Color color;
  final bool hidden;
  final double progress;
  final double celebration;

  @override
  void paint(Canvas canvas, Size size) {
    if (hidden) return;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.45 + progress * 0.35);
    final center = size.center(Offset.zero);
    final count = celebration > 0 ? 8 : 4;
    for (var index = 0; index < count; index++) {
      final angle = phase * math.pi * 2 + index * math.pi * 2 / count;
      final radius =
          82 +
          math.sin(angle * 1.7) * 7 +
          celebration * (index.isEven ? 16 : 9);
      final point = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      if (icon == Icons.water_drop_rounded) {
        canvas.drawOval(
          Rect.fromCenter(center: point, width: 5, height: 9),
          paint,
        );
      } else if (icon == Icons.park_rounded) {
        canvas.save();
        canvas.translate(point.dx, point.dy);
        canvas.rotate(angle + math.pi / 4);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: 10, height: 5),
          paint,
        );
        canvas.restore();
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: point, width: 7, height: 7),
            const Radius.circular(2),
          ),
          paint,
        );
        canvas.drawLine(
          point - const Offset(5, 0),
          point + const Offset(5, 0),
          paint..strokeWidth = 1.5,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LandmarkAccentPainter oldDelegate) => true;
}

class _SimulatedDataBadge extends StatelessWidget {
  const _SimulatedDataBadge({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white30),
      ),
      child: compact
          ? const Tooltip(
              message: 'Dados simulados',
              child: Icon(Icons.info_outline_rounded, size: 18),
            )
          : const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline_rounded, size: 16),
                SizedBox(width: 5),
                Text(
                  'Dados simulados',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ],
            ),
    );
  }
}
