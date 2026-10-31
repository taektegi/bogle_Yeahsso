part of '../photo_capture.dart';

/// Where to fit the drawing: the space outside is dimmed a little, with
/// white corner marks like a document scanner.
class _Guide extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final inset = size.shortestSide * .07;
    final frame = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(inset),
      const Radius.circular(18),
    );
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRRect(frame),
      Paint()..color = Colors.black.withValues(alpha: .2),
    );
    final r = frame.outerRect, arm = size.shortestSide * .09;
    final mark = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final (corner, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomRight, -1.0, -1.0),
      (r.bottomLeft, 1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(corner.dx, corner.dy + dy * arm)
          ..lineTo(corner.dx, corner.dy + dy * 10)
          ..quadraticBezierTo(
            corner.dx,
            corner.dy,
            corner.dx + dx * 10,
            corner.dy,
          )
          ..lineTo(corner.dx + dx * arm, corner.dy),
        mark,
      );
    }
  }

  @override
  bool shouldRepaint(_Guide old) => false;
}

class _Hint extends StatelessWidget {
  const _Hint(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .9),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: BogleColors.text,
      ),
    ),
  );
}
