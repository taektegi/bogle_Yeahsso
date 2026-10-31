import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/art_source.dart';
import '../theme/bogle_theme.dart';
import 'home_return_route.dart';

class AmbientBackground extends StatelessWidget {
  const AmbientBackground({
    super.key,
    required this.child,
    this.compact = false,
  });

  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: BogleColors.cream),
        Positioned(
          left: -120,
          bottom: compact ? -180 : -110,
          child: const _Glow(size: 420, color: BogleColors.blueSoft),
        ),
        const Positioned(
          right: -80,
          top: -130,
          child: _Glow(size: 360, color: BogleColors.pink),
        ),
        const Positioned(
          right: 210,
          bottom: -210,
          child: _Glow(size: 390, color: BogleColors.mint),
        ),
        child,
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: 0.54), color.withValues(alpha: 0)],
            stops: const [0.25, 1],
          ),
        ),
      ),
    );
  }
}

/// Back to the home screen from anywhere, closing every page above it.
void goHome(BuildContext context) {
  if (!context.mounted) return;
  final route = ModalRoute.of(context);
  if (route is HomeReturnRoute) {
    route.returnHome();
  } else {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.secondary = false,
    this.expanded = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool secondary;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final foreground = secondary ? BogleColors.blueStrong : Colors.white;
    final button = SizedBox(
      height: 58,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 21),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: secondary
              ? Colors.white.withValues(alpha: 0.82)
              : BogleColors.blueStrong,
          foregroundColor: foreground,
          disabledBackgroundColor: BogleColors.blueSoft,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 28),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: secondary
                ? const BorderSide(color: BogleColors.blueSoft)
                : BorderSide.none,
          ),
          textStyle: Theme.of(context).textTheme.labelLarge,
        ),
      ),
    );
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class FriendArtwork extends StatelessWidget {
  const FriendArtwork({
    super.key,
    required this.assetPath,
    this.fit = BoxFit.contain,
    this.semanticsLabel,
    this.alignment = Alignment.center,
  });

  final String assetPath;
  final BoxFit fit;
  final String? semanticsLabel;
  final Alignment alignment;

  /// Shown when a friend's artwork can't be read (a broken link, a file
  /// gone): the new-friend drawing, so nothing is left blank.
  static const missing = 'assets/figma/character_friend.svg';

  /// [assetPath] may be a bundled asset, a file on the device or an
  /// http(s) URL (see [artOriginOf]), as SVG or as a raster image.
  @override
  Widget build(BuildContext context) {
    Widget stand(BuildContext context, Object error, StackTrace? stack) =>
        SvgPicture.asset(
          missing,
          fit: fit,
          alignment: alignment,
          semanticsLabel: semanticsLabel,
        );
    if (isSvgArt(assetPath)) {
      return SvgPicture(
        artSvgLoader(assetPath),
        fit: fit,
        alignment: alignment,
        semanticsLabel: semanticsLabel,
        errorBuilder: stand,
      );
    }
    return Image(
      image: artImage(assetPath),
      fit: fit,
      alignment: alignment,
      semanticLabel: semanticsLabel,
      errorBuilder: stand,
    );
  }
}

Route<T> bogleRoute<T>(Widget child, {bool fromRight = true}) {
  // Every app page shares the direct Home return. Popping the whole stack
  // at once would leave slower house transitions visible underneath it.
  return HomeReturnRoute<T>(
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    homeTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, animation, _) => RepaintBoundary(child: child),
    transitionsBuilder: (context, animation, _, child) {
      if (MediaQuery.disableAnimationsOf(context)) return child;
      return SlideTransition(
        position: Tween(
          begin: Offset(fromRight ? 0.035 : 0, 0),
          end: Offset.zero,
        ).animate(animation.drive(CurveTween(curve: Curves.easeOutCubic))),
        child: child,
      );
    },
  );
}
