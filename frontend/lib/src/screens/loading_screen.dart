import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../data/app_services.dart';
import '../data/character_generation.dart';
import '../data/character_repository.dart';
import '../drawing/studio_draft.dart';
import '../theme/bogle_theme.dart';
import '../widgets/bogle_widgets.dart';
import '../widgets/bubble_field.dart';
import '../widgets/top_bar.dart';
import 'setup_friend_screen.dart';
import '../app_lifecycle.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({
    super.key,
    required this.repository,
    this.input,
    this.generator,
    this.startGeneration,
    this.draft,
  });
  final CharacterRepository repository;
  final StudioDraft? draft;

  /// The child's drawing or photo, handed to [generator].
  final GenerationInput? input;

  /// Defaults to the app's ([AppServices]).
  final CharacterGenerator? generator;

  /// For animation-only test fixtures with no input: starts a job directly.
  final CharacterGenerationJob Function()? startGeneration;
  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _reveal;
  CharacterGenerationJob? _job;
  GeneratedArt? _art;
  final List<Timer> _timers = [];
  int _attempt = 0;
  int _waitStage = 0;
  bool _failed = false;

  /// Why it failed, when the generator said.
  GenerationError? _error;
  bool _ready = false;
  bool _leaving = false;
  bool _reducedMotion = false;
  bool _foreground = true;
  bool _assetsReady = false;
  bool _preparing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reveal =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 3600),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            if (mounted) setState(() {});
            _advanceIfReady();
          }
        });
    _start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (!_preparing) {
      _preparing = true;
      _prepareAssets();
    }
    // Defer controller notifications until after the dependency build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncMotion();
    });
  }

  Future<void> _prepareAssets() async {
    // Decode native Figma PNG exports before revealing so inner shadows stay
    // faithful and the animation only composites eight cached images.
    await Future.wait([
      for (final name in const ['loading_wordmark', 'character_friend'])
        if (SvgAssetLoader('assets/figma/$name.svg') case final loader)
          svg.cache.putIfAbsent(
            loader.cacheKey(context),
            () => loader.loadBytes(context),
          ),
      for (final asset in generationBubbleAssets)
        precacheImage(AssetImage(asset), context),
    ]);
    if (!mounted) return;
    setState(() => _assetsReady = true);
    _syncMotion();
  }

  void _syncMotion() {
    if (!_assetsReady) return;
    if (_reducedMotion || _failed) {
      _reveal.value = 1;
    } else if (_foreground) {
      if (!_reveal.isCompleted) _reveal.forward();
    } else {
      _reveal.stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _foreground = onScreen(state));
    _syncMotion();
    if (_foreground) _advanceIfReady();
  }

  void _clearTimers() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }

  void _start() {
    final attempt = ++_attempt;
    _clearTimers();
    _job?.cancel();
    _failed = false;
    _error = null;
    _ready = false;
    _waitStage = 0;
    _timers.addAll([
      Timer(const Duration(seconds: 30), () {
        if (mounted) setState(() => _waitStage = 1);
      }),
      Timer(const Duration(seconds: 75), () {
        if (mounted) setState(() => _waitStage = 2);
      }),
      Timer(const Duration(minutes: 5), () {
        if (mounted && !_ready) {
          ++_attempt;
          _job?.cancel();
          _showFailure();
        }
      }),
    ]);
    _run(attempt);
  }

  Future<void> _run(int attempt) async {
    try {
      final input = widget.input;
      final job =
          widget.startGeneration?.call() ??
          (widget.generator ?? AppServices.of(context).generator).start(
            input ?? (throw StateError('Nothing to make a friend from')),
          );
      _job = job;
      final art = await job.result;
      if (!mounted || attempt != _attempt || _leaving) return;
      _art = art;
      _ready = true;
      _clearTimers();
      _advanceIfReady();
    } catch (error) {
      if (!mounted || attempt != _attempt || _leaving) return;
      _error = error is GenerationError ? error : null;
      _showFailure();
    }
  }

  void _showFailure() {
    _clearTimers();
    setState(() => _failed = true);
    _syncMotion();
  }

  Future<void> _advanceIfReady() async {
    if (!mounted ||
        !_foreground ||
        !_ready ||
        !_reveal.isCompleted ||
        _leaving) {
      return;
    }
    _leaving = true;
    final attempt = _attempt;
    final revision =
        _art!.sketchRevision ??
        (widget.input?.source == GenerationSource.drawing
            ? widget.input?.sketchRevision
            : null);
    final draft =
        widget.draft ??
        context.getInheritedWidgetOfExactType<StudioDraftScope>()?.draft;
    if (revision != null && draft != null) {
      await draft.consumeGeneratedDrawing(revision);
      if (!mounted || attempt != _attempt) return;
    }
    Navigator.of(context).pushReplacement(
      bogleRoute(
        SetupFriendScreen(
          repository: widget.repository,
          art: _art!,
          input: widget.input,
        ),
        fromRight: false,
      ),
    );
  }

  void _cancel() {
    _leaving = true;
    ++_attempt;
    _clearTimers();
    _job?.cancel();
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    ++_attempt;
    _clearTimers();
    _job?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _reveal.dispose();
    super.dispose();
  }

  String? get _message => switch (_waitStage) {
    1 => '그림에 따라 시간이 조금 더 걸릴 수 있어요.\n완성되면 자동으로 다음 화면으로 이동해요.',
    2 => '아직 친구를 만들고 있어요.\n기다리거나, 그림으로 돌아가 다시 시도할 수 있어요.',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final message = _failed
        ? '${_error?.message ?? '잠시 후 다시 시도해 주세요.'}'
              '\n돌아가도 그리던 그림은 그대로 남아 있어요.'
        : _message;
    // The same picture won't work again (the service said so): no retry.
    final retry = _error?.retryable ?? true;
    // The wordmark sits on the exact centre of the screen with the message
    // below it; the bubbles float over both and only the controls stay above
    // the bubbles.
    return Scaffold(
      backgroundColor: BogleColors.cream,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Mirrors the copy and message below so the wordmark, not
                // the whole group, is what gets centred.
                const SizedBox(height: _belowWordmark),
                Semantics(
                  label: '보글',
                  image: true,
                  child: SizedBox(
                    width: 258,
                    height: 160,
                    child: ClipRect(
                      key: const ValueKey('wordmark-reveal'),
                      clipper: _BottomRevealClipper(_reveal),
                      child: SvgPicture.asset(
                        'assets/figma/loading_wordmark.svg',
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Semantics(
                  liveRegion: true,
                  child: SizedBox(
                    height: 40,
                    child: _failed
                        ? const Text(
                            '친구를 데려오지 못했어요',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: bogleDisplayFont,
                              fontSize: 36,
                              height: 40 / 36,
                              letterSpacing: -0.36,
                              color: BogleColors.logo,
                            ),
                          )
                        : AnimatedSwitcher(
                            key: const ValueKey('loading-copy-switcher'),
                            duration: Duration(
                              milliseconds: _reducedMotion ? 0 : 650,
                            ),
                            switchInCurve: Curves.easeInOutCubic,
                            switchOutCurve: Curves.easeInOutCubic,
                            // Both messages keep the same centre and
                            // line height throughout the dissolve.
                            child: _reveal.isCompleted
                                ? _ArrivingCopy(
                                    key: const ValueKey(
                                      'loading-copy-arriving',
                                    ),
                                    running: _foreground,
                                    reducedMotion: _reducedMotion,
                                  )
                                : _BogleCopyReveal(animation: _reveal),
                          ),
                  ),
                ),
                SizedBox(
                  height: 76,
                  child: AnimatedSwitcher(
                    duration: Duration(milliseconds: _reducedMotion ? 0 : 500),
                    child: message == null
                        ? const SizedBox.shrink()
                        : Padding(
                            key: ValueKey((_failed, _waitStage)),
                            padding: const EdgeInsets.only(top: 14),
                            child: Text(
                              message,
                              textAlign: TextAlign.center,
                              style: theme.bodyLarge?.copyWith(
                                color: BogleColors.muted,
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          if (_assetsReady)
            ExcludeSemantics(
              child: BubbleField(
                running: _foreground,
                still: _reducedMotion || _failed,
              ),
            ),
          // Keep navigation above interactive bubbles so the home logo
          // always receives taps, even when a bubble passes over it.
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            child: AppTopBar(repository: widget.repository),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 22 + MediaQuery.paddingOf(context).bottom,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_failed && retry) ...[
                  FilledButton.icon(
                    onPressed: () {
                      setState(_start);
                      _syncMotion();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: BogleColors.logo,
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('다시 시도'),
                  ),
                  const SizedBox(height: 8),
                ],
                TextButton(
                  key: const ValueKey('loading-return-button'),
                  onPressed: _cancel,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_rounded, size: 18),
                      SizedBox(width: 8),
                      Text(
                        widget.input?.source == GenerationSource.photo
                            ? '사진으로 돌아가기'
                            : '그림으로 돌아가기',
                      ),
                      // Balance the leading icon so the label shares the logo's axis.
                      SizedBox(width: 26),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Gap, copy line and message slot under the wordmark.
const double _belowWordmark = 28 + 40 + 76;

/// 로딩 화면의 로고가 다 드러난 뒤 모습: 로고, "친구가 찾아오는 중 · · ·", 떠오르는 거품.
/// 친구 설정을 마쳤는데 얼굴 좌표가 아직 오는 중일 때 설정 화면이 이 모습으로 기다린다.
class FriendArrivingView extends StatelessWidget {
  const FriendArrivingView({super.key});

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Stack(
      key: const ValueKey('friend-arriving'),
      fit: StackFit.expand,
      children: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 로딩 화면과 같이 로고가 화면 한가운데 오도록 아래 공간만큼 위를 띄운다.
              const SizedBox(height: _belowWordmark),
              Semantics(
                label: '보글',
                image: true,
                child: SvgPicture.asset(
                  'assets/figma/loading_wordmark.svg',
                  width: 258,
                  height: 160,
                  excludeFromSemantics: true,
                ),
              ),
              const SizedBox(height: 28),
              Semantics(
                liveRegion: true,
                child: SizedBox(
                  height: 40,
                  child: _ArrivingCopy(running: true, reducedMotion: still),
                ),
              ),
              const SizedBox(height: 76),
            ],
          ),
        ),
        ExcludeSemantics(child: BubbleField(running: true, still: still)),
      ],
    );
  }
}

// Live text follows the app's typeface instead of retaining SVG outlines.
const _loadingCopyStyle = TextStyle(
  fontFamily: bogleDisplayFont,
  fontSize: 36,
  height: 40 / 36,
  letterSpacing: -1.08,
  color: BogleColors.logo,
);

/// Only the dots animate; reserved glyph widths keep the message stationary.
class _ArrivingCopy extends StatefulWidget {
  const _ArrivingCopy({
    super.key,
    required this.running,
    required this.reducedMotion,
  });

  final bool running;
  final bool reducedMotion;

  @override
  State<_ArrivingCopy> createState() => _ArrivingCopyState();
}

class _ArrivingCopyState extends State<_ArrivingCopy>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dots = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_ArrivingCopy oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.running && !widget.reducedMotion) {
      if (!_dots.isAnimating) _dots.repeat();
    } else {
      _dots.stop();
    }
  }

  double _opacity(int index) {
    if (widget.reducedMotion) return 1;
    final t = _dots.value;
    final appear = Curves.easeOut.transform(
      ((t - (.04 + index * .18)) / .07).clamp(0.0, 1.0),
    );
    final disappear = Curves.easeInOut.transform(
      ((t - .78) / .12).clamp(0.0, 1.0),
    );
    return appear * (1 - disappear);
  }

  @override
  void dispose() {
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: '친구가 찾아오는 중',
    child: ExcludeSemantics(
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('친구가 찾아오는 중', style: _loadingCopyStyle),
            const SizedBox(width: 8),
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _dots,
                builder: (context, child) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Opacity(
                        key: ValueKey('arriving-dot-$i'),
                        opacity: _opacity(i),
                        child: const Text('· ', style: _loadingCopyStyle),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Reveal whole glyphs while reserving their width to avoid layout shifts.
/// Shares the logo's 3.6 s clock: no extra timer, ticker or simulated progress.
class _BogleCopyReveal extends StatelessWidget {
  const _BogleCopyReveal({required this.animation});
  final Animation<double> animation;
  static const _glyphs = ['보', '글', '보', '글', '  · ', '· ', '·'];

  @override
  Widget build(BuildContext context) => Semantics(
    label: '보글보글',
    child: ExcludeSemantics(
      child: Center(
        child: RepaintBoundary(
          child: Row(
            key: const ValueKey('loading-copy-reveal'),
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _glyphs.length; i++)
                FadeTransition(
                  key: ValueKey('loading-copy-glyph-$i'),
                  opacity: animation.drive(
                    CurveTween(
                      curve: Interval(
                        (.32 + i * .45) / 3.6,
                        (.62 + i * .45) / 3.6,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                  ),
                  child: Text(_glyphs[i], style: _loadingCopyStyle),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Figma 250:2780 → 299:4308 → 299:4343: a stationary logo revealed
/// bottom-to-top, without scaling letters or pretending to show AI progress.
class _BottomRevealClipper extends CustomClipper<Rect> {
  _BottomRevealClipper(this.animation) : super(reclip: animation);
  final Animation<double> animation;
  @override
  Rect getClip(Size size) {
    final amount = Curves.easeInOutCubic.transform(animation.value);
    return Rect.fromLTRB(
      0,
      size.height * (1 - amount),
      size.width,
      size.height,
    );
  }

  @override
  bool shouldReclip(_BottomRevealClipper oldClipper) =>
      oldClipper.animation != animation;
}
