import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/bogle_theme.dart';
import '../app_lifecycle.dart';

class StartupArtwork extends StatefulWidget {
  const StartupArtwork({super.key, this.exit, this.wordmarkKey});

  /// 0 → 1 while the app hands over to home: every bubble speeds up and
  /// floats out through the top, the cream paper fades to reveal home, and
  /// the wordmark is handed to the startup screen, which flies it to its
  /// place on home. Null while the start screen is simply showing.
  final Animation<double>? exit;

  /// Placed on the wordmark so its exact on-screen spot can be measured.
  final GlobalKey? wordmarkKey;

  static Future<void> precacheLayers(BuildContext context) async {
    final logo = const SvgAssetLoader('assets/figma/startup_wordmark.svg');
    Future<void> warmBubble(int index) async {
      Object? failure;
      StackTrace? failureStack;
      await precacheImage(
        AssetImage('assets/figma/startup_bubble_$index.png'),
        context,
        onError: (error, stack) {
          failure = error;
          failureStack = stack;
        },
      );
      if (failure != null) {
        Error.throwWithStackTrace(failure!, failureStack ?? StackTrace.current);
      }
    }

    await Future.wait([
      for (var i = 0; i < 5; i++) warmBubble(i),
      svg.cache.putIfAbsent(
        logo.cacheKey(context),
        () => logo.loadBytes(context),
      ),
    ]);
  }

  @override
  State<StartupArtwork> createState() => _StartupArtworkState();
}

class _StartupArtworkState extends State<StartupArtwork>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// The first frame is the wordmark alone (matching the native launch
  /// image). Then bubbles well up from below and keep rising until the page
  /// is full of them (Figma "로딩 될 때 버블 올라오기").
  /// x/size in the 1194 × 834 frame; delay in seconds; speed in pt/s.
  static final _risers = List.generate(30, (i) {
    final r = math.Random(11 + i * 7);
    return (
      asset: i % 5,
      x: -120 + r.nextDouble() * 1260,
      size: 140 + r.nextDouble() * 300,
      delay: i * .05 + r.nextDouble() * .08,
      speed: 260 + r.nextDouble() * 220,
      sway: 8 + r.nextDouble() * 18,
      phase: r.nextDouble() * math.pi * 2,
    );
  });

  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  );
  bool _warming = false;
  bool _ready = false;
  bool _reduced = false;
  bool _tickerEnabled = true;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = onScreen(state);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    if (!_warming && !_reduced) {
      _warming = true;
      _warmLayers();
    }
    _syncMotion();
  }

  Future<void> _warmLayers() async {
    try {
      await StartupArtwork.precacheLayers(
        context,
      ).timeout(const Duration(seconds: 4));
      if (!mounted) return;
      setState(() => _ready = true);
      _syncMotion();
    } catch (error) {
      // Keep the complete static launch artwork if a layer cannot be decoded.
      debugPrint('Startup motion warm-up skipped: $error');
    }
  }

  void _syncMotion() {
    if (_ready && !_reduced && _tickerEnabled && _foreground) {
      if (!_motion.isAnimating && !_motion.isCompleted) _motion.forward();
    } else {
      _motion.stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = onScreen(state);
    _syncMotion();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: '보글 시작 화면',
    image: true,
    child: SizedBox.expand(
      key: const ValueKey('startup-artwork'),
      child: !_ready || _reduced
          ? Image.asset(
              'assets/figma/startup_scene.png',
              fit: BoxFit.cover,
              excludeFromSemantics: true,
              gaplessPlayback: true,
            )
          : ExcludeSemantics(
              child: ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: 1194,
                    height: 834,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Fades away at the hand-over, revealing home.
                        Positioned.fill(
                          child: _exitBuilder(
                            (e) => ColoredBox(
                              color: BogleColors.cream.withValues(
                                alpha:
                                    1 -
                                    Curves.easeOut.transform(
                                      ((e - .05) / .4).clamp(0.0, 1.0),
                                    ),
                              ),
                            ),
                          ),
                        ),
                        for (var i = 0; i < _risers.length; i++) _riser(i),
                        _exitBuilder(
                          (e) => Positioned(
                            left: 447,
                            top: 324.629,
                            width: 300,
                            height: 185.644,
                            // The flying copy takes over the moment the
                            // hand-over starts.
                            child: Opacity(
                              opacity: widget.exit == null || e == 0 ? 1 : 0,
                              child: RepaintBoundary(
                                key: widget.wordmarkKey,
                                child: SvgPicture.asset(
                                  'assets/figma/startup_wordmark.svg',
                                  key: const ValueKey('startup-wordmark'),
                                ),
                              ),
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

  Widget _exitBuilder(Widget Function(double exit) build) {
    final exit = widget.exit;
    if (exit == null) return build(0);
    return AnimatedBuilder(
      animation: exit,
      builder: (context, _) => build(exit.value),
    );
  }

  /// How far the hand-over has pushed the bubbles up and out (frame pt).
  /// Unhurried, so the bubbles visibly drift up across home as its parts
  /// bloom in their wake.
  double _lift() {
    final t = (widget.exit?.value ?? 0).clamp(0.0, 1.0);
    return math.pow(t, 1.6) * 1250;
  }

  Listenable get _clock =>
      widget.exit == null ? _motion : Listenable.merge([_motion, widget.exit]);

  /// Shared by every bubble: fades them out as they leave at the hand-over.
  /// Applied by the images themselves, which is much cheaper than a layer
  /// per bubble.
  late final Animation<double> _bubbleFade = widget.exit == null
      ? kAlwaysCompleteAnimation
      : widget.exit!.drive(
          Tween(begin: 1.0, end: 0.0).chain(
            CurveTween(curve: const Interval(.45, .9, curve: Curves.easeIn)),
          ),
        );

  Widget _riser(int index) {
    final r = _risers[index];
    return Positioned(
      left: r.x,
      top: 834,
      width: r.size,
      height: r.size,
      child: AnimatedBuilder(
        animation: _clock,
        child: RepaintBoundary(
          child: Image.asset(
            'assets/figma/startup_bubble_${r.asset}.png',
            opacity: _bubbleFade,
          ),
        ),
        builder: (_, child) {
          final seconds =
              _motion.value * _motion.duration!.inMilliseconds / 1000;
          final age = math.max(0.0, seconds - r.delay);
          // Quick to well up, then an easy float.
          final risen = r.speed * age + 180 * (1 - math.exp(-age * 3));
          return Transform.translate(
            key: ValueKey('startup-riser-$index'),
            offset: Offset(
              math.sin(age * 1.4 + r.phase) * r.sway,
              -risen - _lift(),
            ),
            child: child,
          );
        },
      ),
    );
  }
}
