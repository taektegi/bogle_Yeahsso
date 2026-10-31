import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/character_repository.dart';
import '../screens/profile_screen.dart';
import '../theme/bogle_theme.dart';
import '../theme/bogle_viewport.dart';
import 'bogle_widgets.dart';
import 'bogle_news_dialog.dart';

/// The page the top bar sits on, when it is one its icons lead to.
enum TopBarPage { home, profile, other }

/// Figma 285:3691 (와이어 프레임): every page's top bar. The wordmark on the
/// left, the page's pill in the middle and the home / news / settings icons
/// on the right, 55 pt tall, 48 pt in from the sides and 28 pt below the
/// status bar of the 1194 × 834 frame. It sits exactly where home's does,
/// so it stays put when moving between pages.
///
/// Place it above the page's own [SafeArea]: it leaves the status bar
/// clear itself.
class AppTopBar extends StatelessWidget {
  const AppTopBar({
    super.key,
    required this.repository,
    this.title,
    this.center,
    this.current = TopBarPage.other,
    this.onNews,
  });

  /// For My Page, which the settings icon opens.
  final CharacterRepository repository;

  /// The page's pill ([TopBarPill]); [center] replaces it when given.
  final String? title;
  final Widget? center;
  final TopBarPage current;

  /// Replaces the news notice, as on My Page.
  final VoidCallback? onNews;

  /// Height of the bar on a screen [width] wide, as on home.
  static double heightFor(
    double width, {
    TextScaler textScaler = TextScaler.noScaling,
  }) => BogleViewport.headerHeight(width, textScaler);

  /// Gap between the status bar and the bar.
  static double _gap(MediaQueryData media) {
    // Home spreads its free height 28 : 125 : 468 : 126 (Figma) with the
    // bar after the first share; this lands on the same spot.
    final free =
        media.size.height -
        media.padding.top -
        media.padding.bottom -
        heightFor(media.size.width, textScaler: media.textScaler);
    return (free * 28 / 747).clamp(12.0, 60.0);
  }

  /// Where the bar ends, from the top of the screen.
  static double bottomFor(MediaQueryData media) =>
      media.padding.top +
      _gap(media) +
      heightFor(media.size.width, textScaler: media.textScaler);

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final height = heightFor(width, textScaler: media.textScaler);
    final top = _gap(media);
    final side = BogleViewport.horizontalInset(width);
    final pill = center ?? (title == null ? null : TopBarPill(title!));
    return Padding(
      key: const ValueKey('top-bar'),
      padding: EdgeInsets.fromLTRB(
        side + media.padding.left,
        media.padding.top + top,
        side + media.padding.right,
        0,
      ),
      child: SizedBox(
        height: height,
        child: BogleHeaderLayout(
          leading: const BogleLogo(),
          center: pill,
          trailing: TopBarIcons(
            current: current,
            onHome: () => goHome(context),
            onNews: onNews ?? () => showBogleNews(context),
            onSettings: () => openMyPage(context, repository),
          ),
        ),
      ),
    );
  }
}

/// 공통 헤더의 실제 내용 영역. 좁은 창에서 제목과 탐색 아이콘을 분리한다.
class BogleHeaderLayout extends StatelessWidget {
  const BogleHeaderLayout({
    super.key,
    required this.leading,
    required this.trailing,
    this.center,
  });
  final Widget leading, trailing;
  final Widget? center;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (MediaQuery.sizeOf(context).width < 640) {
        return Column(
          children: [
            Expanded(child: Row(children: [leading, const Spacer(), trailing])),
            const SizedBox(height: 10),
            if (center != null) Expanded(child: Center(child: center)),
          ],
        );
      }
      final room = (box.maxWidth - 2 * (TopBarIcons.size.width + 12)).clamp(
        0.0,
        box.maxWidth,
      );
      return Stack(
        alignment: Alignment.center,
        children: [
          if (center != null)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: room),
              child: center,
            ),
          Row(children: [leading, const Spacer(), trailing]),
        ],
      );
    },
  );
}

/// The wordmark at the top-left of every page (Figma "Group 3").
class BogleLogo extends StatelessWidget {
  const BogleLogo({super.key, this.artKey = const ValueKey('top-bar-logo')});

  /// Home keeps its own artwork key for the launch wordmark's landing target.
  final Key artKey;

  @override
  Widget build(BuildContext context) {
    void openHome() => goHome(context);
    return Semantics(
      label: '보글 홈',
      button: true,
      onTap: openHome,
      excludeSemantics: true,
      child: Tooltip(
        message: '보글 홈으로',
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: const ValueKey('bogle-home-button'),
            borderRadius: BorderRadius.circular(16),
            onTap: openHome,
            excludeFromSemantics: true,
            child: SvgPicture.asset(
              'assets/figma/logo.svg',
              key: artKey,
              height: 55,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
    );
  }
}

/// Figma's page pill: 55 pt tall, at least 178 wide, white 24 pt Pretendard
/// Bold lettering.
/// Unselected (a tab not showing) it turns Figma's "미선택버튼" grey, and
/// with [onTap] it is a button.
class TopBarPill extends StatelessWidget {
  const TopBarPill(
    this.label, {
    super.key,
    this.selected = true,
    this.onTap,
    this.compact = false,
  });

  final bool compact;

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  static const unselected = Color(0xFFDAD9CD);

  @override
  Widget build(BuildContext context) {
    final pill = Material(
      color: selected ? BogleColors.logo : unselected,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: compact ? 100 : 178,
            minHeight: 55,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 34),
            child: Center(
              widthFactor: 1,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    fontFamily: bogleUiFont,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    height: 40 / 24,
                    letterSpacing: -0.24,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Semantics(
      header: onTap == null,
      button: onTap != null,
      selected: onTap != null && selected,
      child: SizedBox(
        height: BogleViewport.pillHeight(MediaQuery.textScalerOf(context)),
        child: pill,
      ),
    );
  }
}

/// Figma's three icons (one drawing, "Group 1261155734"): home, news and
/// settings, each with its own touch target laid over it.
class TopBarIcons extends StatelessWidget {
  const TopBarIcons({
    super.key,
    this.current = TopBarPage.other,
    required this.onHome,
    required this.onNews,
    required this.onSettings,
  });

  final TopBarPage current;
  final VoidCallback onHome;
  final VoidCallback onNews;
  final VoidCallback onSettings;

  static const size = Size(188.62, 49.5902);

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    key: const ValueKey('top-bar-icons'),
    size: size,
    child: Stack(
      children: [
        SvgPicture.asset(
          'assets/figma/header_icons.svg',
          width: size.width,
          height: size.height,
          excludeFromSemantics: true,
        ),
        // Over the house (x 0–50), the bubble (70–121) and the gear
        // (139–189), 56 wide so small fingers find them.
        _target(0, '홈', current == TopBarPage.home ? null : onHome),
        _target(67.6, '알림', onNews),
        _target(
          size.width - 56,
          '마이페이지',
          current == TopBarPage.profile ? null : onSettings,
        ),
      ],
    ),
  );

  Widget _target(double left, String label, VoidCallback? onTap) {
    final here = onTap == null;
    return Positioned(
      left: left,
      top: 0,
      width: 56,
      height: size.height,
      child: Tooltip(
        message: here ? '지금 여기예요' : label,
        child: Semantics(
          button: !here,
          selected: here,
          label: label,
          excludeSemantics: true,
          child: Material(
            key: ValueKey('top-action-$label'),
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: onTap,
            ),
          ),
        ),
      ),
    );
  }
}

/// Figma 568:2385 (and every page's back button): a solid white #FFFFFC
/// circle, 68 pt, with a soft 15 % shadow and the dark arrow, under the
/// wordmark. Figma's order frame (568:2488) draws its circle at 20 %; the
/// app keeps it solid like the rest so it reads as a button everywhere.
class BogleBackButton extends StatelessWidget {
  const BogleBackButton({
    super.key,
    required this.onTap,
    this.size = 68,
    this.inkKey = const ValueKey('back-button'),
  });
  final VoidCallback onTap;
  final double size;

  /// The tappable part, for finding it in tests.
  final Key inkKey;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '뒤로',
    child: Semantics(
      button: true,
      label: '뒤로',
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Color(0xFFFFFFFC),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 7.4,
              spreadRadius: .74,
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: inkKey,
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SvgPicture.asset(
              'assets/figma/house_back_arrow.svg',
              width: size,
              height: size,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The news icon's notice.
void showBogleNews(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => const BogleNewsDialog(),
);

/// The settings icon: My Page.
Future<void> openMyPage(BuildContext context, CharacterRepository repository) =>
    Navigator.of(
      context,
    ).push(bogleRoute(ProfileScreen(repository: repository)));
