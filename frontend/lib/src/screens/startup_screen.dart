import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/character_repository.dart';
import '../widgets/startup_artwork.dart';
import 'home_screen.dart';
import '../app_lifecycle.dart';

/// App launch only, separate from the 18-second character-generation demo.
/// Figma 124:131 supplies the first frame (it matches the native launch
/// image). Then bubbles well up and fill the page; once home is ready the
/// bubbles float away, the wordmark flies to home's top-left corner and
/// home's cards and buttons bloom in. Home is built underneath beforehand
/// and simply stays when the start screen steps aside, so nothing reloads.
class StartupScreen extends StatefulWidget {
  const StartupScreen({
    super.key,
    required this.repository,
    this.prepare,
    this.displayDuration = const Duration(milliseconds: 1400),
  });

  final CharacterRepository repository;
  final Future<void> Function(BuildContext)? prepare;
  final Duration displayDuration;

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  /// Long enough for the bubbles to drift up past home and its parts to
  /// bloom in their wake; the wordmark's flight keeps its own pace (see
  /// [_FlyingWordmark]).
  static const _handOver = Duration(milliseconds: 2600);
  // Created up front: made lazily, it could first be built during dispose.
  late final AnimationController _exit;
  final _wordmark = GlobalKey(debugLabel: 'startup-wordmark');
  final _brand = GlobalKey(debugLabel: 'home-brand');

  /// Home is built (hidden under the start screen) as soon as it's ready,
  /// so the hand-over never waits on its first, heaviest frame.
  bool _homeBuilt = false;

  /// The start screen has stepped aside for good.
  bool _gone = false;

  /// Where the wordmark starts and lands, measured when the hand-over starts.
  Rect? _from, _to;

  final _visibleTime = Stopwatch();
  Timer? _hold;
  late Duration _remaining = widget.displayDuration;
  bool _started = false;
  bool _prepared = false;
  bool _foreground = true;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _exit = AnimationController(vsync: this, duration: _handOver);
    WidgetsBinding.instance.addObserver(this);
    _foreground = onScreen(WidgetsBinding.instance.lifecycleState);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _remaining = Duration.zero;
    }
    _prepare();
    _resumeHold();
  }

  Future<void> _prepare() async {
    try {
      // Local artwork warming only. A missing/corrupt asset must not trap
      // the user at launch; no network or AI job is started here.
      await Future<void>.sync(
        () => (widget.prepare ?? _warmArtwork)(context),
      ).timeout(const Duration(seconds: 4));
    } catch (error) {
      debugPrint('Startup artwork warm-up skipped: $error');
    }
    if (!mounted) return;
    _prepared = true;
    setState(() => _homeBuilt = true);
    // Leave on the next frame, once home has been laid out underneath.
    WidgetsBinding.instance.addPostFrameCallback((_) => _advance());
  }

  Future<void> _warmArtwork(BuildContext context) => Future.wait<void>([
    StartupArtwork.precacheLayers(context),
    for (final name in const [
      'startup_scene.png',
      'home_play_character.png',
      'home_draw_palette.png',
      'home_order_cart.png',
    ])
      precacheImage(AssetImage('assets/figma/$name'), context),
    for (final name in const ['logo.svg', 'home_photo_circle.svg'])
      if (SvgAssetLoader('assets/figma/$name') case final loader)
        svg.cache
            .putIfAbsent(
              loader.cacheKey(context),
              () => loader.loadBytes(context),
            )
            .then<void>((_) {}),
  ]);

  void _resumeHold() {
    if (!_foreground || _leaving) return;
    _visibleTime.start();
    _hold = Timer(_remaining, () {
      _visibleTime.stop();
      _remaining = Duration.zero;
      _advance();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = onScreen(state);
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (foreground) {
      _resumeHold();
      _advance();
    } else {
      _hold?.cancel();
      _visibleTime.stop();
      _remaining -= _visibleTime.elapsed;
      if (_remaining.isNegative) _remaining = Duration.zero;
      _visibleTime.reset();
    }
  }

  void _advance() {
    if (!mounted ||
        !_foreground ||
        !_prepared ||
        _remaining > Duration.zero ||
        _leaving) {
      return;
    }
    _leaving = true;
    _hold?.cancel();
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() {
        _homeBuilt = true;
        _gone = true;
      });
      return;
    }
    // Home is already laid out underneath: measure both logos and go.
    setState(() {
      _homeBuilt = true;
      _from = _rectOf(_wordmark);
      _to = _rectOf(_brand);
    });
    _exit
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _gone = true);
        }
      })
      ..forward();
  }

  Rect? _rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    final surface = context.findRenderObject();
    if (box is! RenderBox || surface is! RenderBox || !box.hasSize) {
      return null;
    }
    // Through every transform on the way, including the start screen's
    // scale-to-fit: its size on screen, not its unscaled layout size.
    return MatrixUtils.transformRect(
      box.getTransformTo(surface),
      Offset.zero & box.size,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hold?.cancel();
    _visibleTime.stop();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The same Stack before and after, so home keeps its state (and its
    // finished bloom) when the start screen steps aside.
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_homeBuilt)
          HomeScreen(
            key: const ValueKey('launched-home'),
            repository: widget.repository,
            intro: reduced ? null : _exit,
            brandKey: _brand,
          ),
        if (!_gone) ...[
          // Taps go straight to home once it starts blooming.
          IgnorePointer(
            ignoring: _leaving,
            child: ExcludeSemantics(
              excluding: _leaving,
              child: Scaffold(
                key: const ValueKey('startup-overlay'),
                backgroundColor: Colors.transparent,
                body: StartupArtwork(exit: _exit, wordmarkKey: _wordmark),
              ),
            ),
          ),
          if (_from != null && _to != null)
            _FlyingWordmark(progress: _exit, from: _from!, to: _to!),
        ],
      ],
    );
  }
}

/// When, in the hand-over, the wordmark lands on home's logo.
const logoLands = .526;

/// The wordmark on its way from the middle of the start screen to home's
/// top-left corner. It is drawn once at its starting size and only moved
/// and scaled (both on one eased clock), so it glides and shrinks in a
/// single motion without being redrawn each frame. The two logos are the
/// same drawing, so home's own takes over on landing without a swap.

class _FlyingWordmark extends StatelessWidget {
  const _FlyingWordmark({
    required this.progress,
    required this.from,
    required this.to,
  });
  final Animation<double> progress;
  final Rect from, to;

  // 0.15 s → 1.37 s into the 2.6 s hand-over.
  static const _start = .058, _land = logoLands;
  static const _glide = Cubic(.37, 0, .63, 1);

  @override
  Widget build(BuildContext context) => Positioned.fromRect(
    rect: from,
    child: IgnorePointer(
      child: AnimatedBuilder(
        animation: progress,
        builder: (context, child) {
          final value = progress.value;
          if (value >= _land) return const SizedBox.shrink();
          // A soft sine ease, so it sets off and settles without a lurch.
          final t = _glide.transform(
            ((value - _start) / (_land - _start)).clamp(0.0, 1.0),
          );
          // Shrinks at an even rate to the eye (a steady zoom) rather than
          // slowly and then all at once, while its centre glides straight.
          final scale = math.pow(to.width / from.width, t).toDouble();
          final shift = (to.center - from.center) * t;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.translationValues(shift.dx, shift.dy, 0)
              ..scaleByDouble(scale, scale, 1, 1),
            child: child,
          );
        },
        child: RepaintBoundary(
          child: SvgPicture.asset(
            'assets/figma/startup_wordmark.svg',
            key: const ValueKey('flying-wordmark'),
            excludeFromSemantics: true,
          ),
        ),
      ),
    ),
  );
}
