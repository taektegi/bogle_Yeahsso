part of '../photo_capture.dart';

/// A photo print with a hand-torn edge, lifted off the page by a shadow
/// (the wireframe's photo frames).
class TornPaper extends StatelessWidget {
  const TornPaper({super.key, required this.child, this.seed = 1});
  final Widget child;
  final int seed;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _TornShadow(seed),
    child: ClipPath(clipper: _TornEdge(seed), child: child),
  );
}

/// Every edge wanders in and out a few points, in small steps, the same way
/// each time for the same [seed].
Path _tornPath(Size s, int seed) {
  final random = math.Random(seed);
  const step = 7.0, depth = 3.6;
  double nip() => random.nextDouble() * depth;
  final path = Path()..moveTo(nip(), nip());
  for (var x = step; x < s.width; x += step) {
    path.lineTo(x, nip());
  }
  for (var y = step; y < s.height; y += step) {
    path.lineTo(s.width - nip(), y);
  }
  for (var x = s.width - step; x > 0; x -= step) {
    path.lineTo(x, s.height - nip());
  }
  for (var y = s.height - step; y > 0; y -= step) {
    path.lineTo(nip(), y);
  }
  return path..close();
}

class _TornEdge extends CustomClipper<Path> {
  _TornEdge(this.seed);
  final int seed;
  @override
  Path getClip(Size size) => _tornPath(size, seed);
  @override
  bool shouldReclip(_TornEdge old) => old.seed != seed;
}

class _TornShadow extends CustomPainter {
  _TornShadow(this.seed);
  final int seed;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawShadow(
    _tornPath(size, seed),
    const Color(0xFF3A4A8C),
    10,
    false,
  );
  @override
  bool shouldRepaint(_TornShadow old) => old.seed != seed;
}
