part of '../home_screen.dart';

/// Translucent circles echoing the loading bubbles inside each card.
class _CardBubbles extends StatelessWidget {
  const _CardBubbles();
  @override
  Widget build(BuildContext context) {
    Widget circle(double size, double alpha) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [
            Colors.white.withValues(alpha: alpha),
            Colors.white.withValues(alpha: alpha * 0.25),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: alpha * 1.2),
          width: 2,
        ),
      ),
    );
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(right: -46, top: -40, child: circle(170, 0.22)),
            Positioned(left: -30, bottom: -54, child: circle(140, 0.16)),
            Positioned(left: 30, top: 28, child: circle(34, 0.3)),
            Positioned(right: 44, bottom: 90, child: circle(20, 0.34)),
          ],
        ),
      ),
    );
  }
}

/// Figma's beige circle next to the palette, marking the photo option.
class _PhotoBadge extends StatelessWidget {
  const _PhotoBadge();
  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      SvgPicture.asset(
        'assets/figma/home_photo_circle.svg',
        width: 100,
        height: 100,
      ),
      const Icon(
        Icons.photo_camera_rounded,
        size: 44,
        color: Color(0xFFE59A5C),
      ),
    ],
  );
}

class _Floating extends StatelessWidget {
  const _Floating({
    required this.idle,
    required this.child,
    this.lift = 6,
    this.tilt = 0,
    this.offset = 0,
  });
  final Animation<double> idle;
  final Widget child;
  final double lift;
  final double tilt;
  final double offset;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: idle,
    child: RepaintBoundary(child: child),
    builder: (context, child) {
      // Two bobs per 6 s loop.
      final wave = math.sin((idle.value * 2 + offset) * 2 * math.pi);
      return Transform.translate(
        offset: Offset(0, -lift * wave),
        child: Transform.rotate(angle: tilt * wave, child: child),
      );
    },
  );
}

/// Figma's large, faint bubbles behind the header and the cards, drifting
/// slowly. Centres and diameters are in the 1194 × 834 frame.
class _BackdropBubbles extends StatelessWidget {
  const _BackdropBubbles({required this.idle});
  final Animation<double> idle;

  static const _spots = [
    (asset: 0, x: 60.0, y: 95.0, d: 230.0, alpha: .75),
    (asset: 2, x: 340.0, y: -20.0, d: 380.0, alpha: .6),
    (asset: 0, x: 480.0, y: 305.0, d: 236.0, alpha: .45),
    (asset: 1, x: 885.0, y: 165.0, d: 300.0, alpha: .6),
    (asset: 3, x: 1100.0, y: -40.0, d: 270.0, alpha: .7),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final sx = constraints.maxWidth / 1194;
      final sy = constraints.maxHeight / 834;
      return Stack(
        children: [
          for (final (i, s) in _spots.indexed)
            AnimatedBuilder(
              animation: idle,
              child: Image.asset(
                'assets/figma/loading_bubble_${s.asset}.png',
                width: s.d * sx,
                height: s.d * sx,
                opacity: AlwaysStoppedAnimation(s.alpha),
              ),
              builder: (context, child) {
                final a = (idle.value + i * 0.21) * 2 * math.pi;
                return Positioned(
                  left: s.x * sx - s.d * sx / 2 + math.cos(a) * 6,
                  top: s.y * sy - s.d * sx / 2 + math.sin(a) * 10,
                  child: child!,
                );
              },
            ),
        ],
      );
    },
  );
}
