part of '../home_screen.dart';

/// "뭉게뭉게 피어나기": as the start screen's bubbles drift up past it, a
/// part of home appears through a cluster of round, bubble-shaped openings
/// that swell up from below and merge until the whole part shows, so its
/// edge billows softly instead of fading in flat. Only a clip, opacity and
/// transforms, so it stays smooth on iPad. Once fully shown it is a plain
/// child.
class Bloom extends StatelessWidget {
  const Bloom({
    super.key,
    required this.appear,
    required this.child,
    this.seed = 0,
  });
  final Animation<double> appear;
  final Widget child;

  /// Gives each part its own bubble pattern.
  final int seed;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: appear,
    child: child,
    builder: (context, child) {
      final t = appear.value;
      if (t >= 1) return child!;
      if (t <= 0) return Opacity(opacity: 0, child: child);
      final soft = Curves.easeOut.transform(t);
      return ClipPath(
        clipper: _BubbleReveal(t, seed),
        child: Opacity(
          opacity: Curves.easeOut.transform((t / .5).clamp(0.0, 1.0)),
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - soft)),
            child: Transform.scale(scale: .96 + .04 * soft, child: child),
          ),
        ),
      );
    },
  );
}

/// Round openings that well up from the bottom edge and swell until their
/// union covers the whole part.
class _BubbleReveal extends CustomClipper<Path> {
  _BubbleReveal(this.t, this.seed);
  final double t;
  final int seed;

  @override
  Path getClip(Size size) {
    final r = math.Random(seed * 17 + 3);
    final diagonal = math.sqrt(
      size.width * size.width + size.height * size.height,
    );
    final count = size.width > 300 ? 7 : 5;
    final path = Path();
    for (var i = 0; i < count; i++) {
      final delay = r.nextDouble() * .25;
      final grow = Curves.easeOutCubic.transform(
        ((t - delay) / (1 - delay)).clamp(0.0, 1.0),
      );
      if (grow <= 0) continue;
      // Rising from the bottom, as the bubbles did.
      final centre = Offset(
        size.width * (i + .2 + r.nextDouble() * .6) / count,
        size.height * (1.05 - .5 * grow + (r.nextDouble() - .5) * .15),
      );
      final radius = diagonal * (.85 + r.nextDouble() * .25) * grow;
      path.addOval(Rect.fromCircle(center: centre, radius: radius));
    }
    return path;
  }

  @override
  bool shouldReclip(_BubbleReveal old) => old.t != t || old.seed != seed;
}
