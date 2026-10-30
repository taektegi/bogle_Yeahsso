import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/app_services.dart';
import '../data/character_generation.dart';
import '../data/character_repository.dart';
import '../data/profile_repository.dart';
import '../theme/bogle_theme.dart';
import '../theme/bogle_viewport.dart';
import '../widgets/bogle_widgets.dart';
import '../widgets/top_bar.dart';
import 'archive_screen.dart';
import 'create_studio_screen.dart';
import 'loading_screen.dart';
import 'order_screen.dart';
import 'profile_screen.dart';

part 'home/home_card.dart';
part 'home/bloom.dart';
part 'home/decorations.dart';

/// Figma 243:2201 "메인 화면": the shared top bar (see [AppTopBar]:
/// wordmark, "Welcome!" pill, home / news / settings icons); one tall card on the
/// left and two stacked cards on the right, over a few large soft bubbles.
/// Positions scale from the Figma 1194 × 834 frame. The grey wireframe
/// fills become the app's pastel cards with their illustrations.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    this.intro,
    this.brandKey,
  });
  final CharacterRepository repository;

  /// The start screen's hand-over (0 → 1). When given, home blooms in on
  /// that clock: its logo appears where the flying wordmark lands, and the
  /// cards and buttons well up one after another. Without it, home plays
  /// its own entrance.
  final Animation<double>? intro;

  /// On the logo, so the start screen can fly its wordmark exactly there.
  final GlobalKey? brandKey;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late final ProfileRepository _profileRepository = AppServices.of(
    context,
  ).profile;

  late final _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  /// Gentle idle float for the illustrations; paused off-screen.
  late final _idle = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  /// Looked for once per launch: a friend the app was closed while making.
  static bool _lookedForUnfinished = false;

  Future<void> _offerUnfinished() async {
    if (_lookedForUnfinished) return;
    _lookedForUnfinished = true;
    final CharacterGenerationJob? job;
    try {
      job = await AppServices.of(context).generator.unfinished();
    } catch (_) {
      return; // offline: maybe next launch
    }
    if (job == null || !mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 12),
        content: const Text('만들던 친구가 아직 기다리고 있어요.'),
        action: SnackBarAction(
          label: '이어서 만들기',
          onPressed: () => Navigator.of(context).push(
            bogleRoute(
              LoadingScreen(
                repository: widget.repository,
                startGeneration: () => job!,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _offerUnfinished();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    final visible = ModalRoute.of(context)?.isCurrent ?? true;
    if (still) {
      _entrance.value = 1;
    } else if (_entrance.isDismissed) {
      _entrance.forward();
    }
    if (!still && visible) {
      if (!_idle.isAnimating) _idle.repeat();
    } else {
      _idle.stop();
    }
  }

  Future<void> _openProfile() async {
    await Navigator.of(context).push(
      bogleRoute(
        ProfileScreen(
          repository: widget.repository,
          profileRepository: _profileRepository,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _entrance.dispose();
    _idle.dispose();
    super.dispose();
  }

  void _open(Widget page) => Navigator.of(context).push(bogleRoute(page));

  /// When each part blooms: 0 the header, 1–3 the cards.
  Animation<double> _stagger(int index) {
    final intro = widget.intro;
    if (intro != null) {
      // In the wake of the bubbles, which rise from the bottom: the lower
      // cards first, then the upper card, then the header.
      final start = const [.44, .24, .32, .22][index];
      return CurvedAnimation(
        parent: intro,
        curve: Interval(start, math.min(1, start + .46)),
      );
    }
    return CurvedAnimation(
      parent: _entrance,
      curve: Interval(index * 0.12, 0.64 + index * 0.12),
    );
  }

  /// The home logo shows once the flying wordmark has landed on it.
  Widget _brand(Widget logo) {
    final intro = widget.intro;
    if (intro == null) return logo;
    return AnimatedBuilder(
      animation: intro,
      child: logo,
      builder: (_, child) =>
          Opacity(opacity: intro.value >= _logoLands ? 1 : 0, child: child),
    );
  }

  /// Must match the start screen's `logoLands`.
  static const _logoLands = .526;

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    return Scaffold(
      backgroundColor: BogleColors.cream,
      body: LayoutBuilder(
        builder: (context, box) {
          // Horizontal measures follow the frame's width; the Figma frame
          // includes a 32 pt status bar, which SafeArea already leaves out.
          final side = BogleViewport.horizontalInset(box.maxWidth);
          return Stack(
            fit: StackFit.expand,
            children: [
              ExcludeSemantics(
                child: widget.intro == null
                    ? _BackdropBubbles(idle: _idle)
                    : FadeTransition(
                        opacity: CurvedAnimation(
                          parent: widget.intro!,
                          curve: const Interval(.3, .8),
                        ),
                        child: _BackdropBubbles(idle: _idle),
                      ),
              ),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(side, 0, side, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Figma: header y 60–115 in the frame (28 below the
                      // status bar), 55 pt tall.
                      const Spacer(flex: 28),
                      SizedBox(
                        height: AppTopBar.heightFor(
                          box.maxWidth,
                          textScaler: MediaQuery.textScalerOf(context),
                        ),
                        child: _header(),
                      ),
                      // Cards y 240–708: 125 above, 468 tall, 126 below.
                      const Spacer(flex: 125),
                      Expanded(
                        flex: 468,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 536,
                              child: _HomeCard(
                                key: const ValueKey('home-play-card'),
                                appear: _stagger(1),
                                label: '친구들 보러가기',
                                semantics: '친구들 보러 놀러가기',
                                colors: const [
                                  Color(0xFFA9BBFF),
                                  Color(0xFF8199FF),
                                ],
                                onTap: () => _open(
                                  ArchiveScreen(repository: repository),
                                ),
                                art: _Floating(
                                  idle: _idle,
                                  lift: 10,
                                  // The tail widens the image to the left;
                                  // centre the head (x 644 of 987 px) instead.
                                  child: FractionalTranslation(
                                    translation: const Offset(-0.152, 0),
                                    child: Image.asset(
                                      'assets/figma/home_play_character.png',
                                      width: 297,
                                      height: 361,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const Spacer(flex: 48),
                            Expanded(
                              flex: 514,
                              child: Column(
                                children: [
                                  Expanded(
                                    flex: 210,
                                    child: _HomeCard(
                                      appear: _stagger(2),
                                      label: '친구 그리기 / 사진찍기',
                                      semantics: '친구 그리기 또는 사진찍기',
                                      colors: const [
                                        Color(0xFFFFC9A6),
                                        Color(0xFFFFA784),
                                      ],
                                      onTap: () => _open(
                                        CreateStudioScreen(
                                          repository: repository,
                                        ),
                                      ),
                                      art: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _Floating(
                                            idle: _idle,
                                            lift: 5,
                                            tilt: 0.06,
                                            child: Image.asset(
                                              'assets/figma/home_draw_palette.png',
                                              width: 138,
                                              height: 138,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          _Floating(
                                            idle: _idle,
                                            lift: 5,
                                            offset: 0.5,
                                            child: const _PhotoBadge(),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const Spacer(flex: 48),
                                  Expanded(
                                    flex: 210,
                                    child: _HomeCard(
                                      appear: _stagger(3),
                                      label: '주문하기',
                                      semantics: '굿즈 주문하기',
                                      colors: const [
                                        Color(0xFF9FE3C4),
                                        Color(0xFF6CCDA2),
                                      ],
                                      onTap: () => _open(
                                        OrderScreen(repository: repository),
                                      ),
                                      art: _Floating(
                                        idle: _idle,
                                        lift: 5,
                                        tilt: -0.05,
                                        offset: 0.25,
                                        child: Image.asset(
                                          'assets/figma/home_order_cart.png',
                                          width: 168,
                                          height: 168,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(flex: 126),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Wordmark left, welcome pill centred on the page, icons right.
  Widget _header() => BogleHeaderLayout(
    center: Bloom(
      appear: _stagger(0),
      seed: 1,
      child: const TopBarPill('Welcome!', key: ValueKey('home-welcome')),
    ),
    leading: _brand(
      SizedBox(
        key: widget.brandKey,
        child: const BogleLogo(artKey: ValueKey('home-brand')),
      ),
    ),
    trailing: Bloom(
      appear: _stagger(0),
      seed: 2,
      child: TopBarIcons(
        current: TopBarPage.home,
        onHome: () {},
        onNews: () => showBogleNews(context),
        onSettings: _openProfile,
      ),
    ),
  );
}
