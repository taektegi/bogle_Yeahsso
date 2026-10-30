import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A single shared timeline for the character and its two cloud banks.
/// The owning screen retains progress, so going back never replays the birth.
class FriendArrival extends StatelessWidget {
  const FriendArrival({super.key, required this.progress, required this.child});

  static const duration = Duration(milliseconds: 1900);
  final Animation<double> progress;
  final Widget child;

  static double _phase(double t, double start, double end, Curve curve) =>
      curve.transform(((t - start) / (end - start)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => AnimatedBuilder(
      animation: progress,
      child: RepaintBoundary(child: child),
      builder: (context, friend) {
        final t = MediaQuery.disableAnimationsOf(context)
            ? 1.0
            : progress.value;
        final travel = MediaQuery.sizeOf(context).height;
        final jump = math.min(76.0, box.maxHeight * .16);
        final double y;
        if (t < .49) {
          y =
              travel +
              (-jump - travel) * _phase(t, .14, .49, Curves.easeOutCubic);
        } else if (t < .66) {
          y = -jump + (jump + 10) * _phase(t, .49, .66, Curves.easeInQuad);
        } else if (t < .77) {
          y = 10 - 30 * _phase(t, .66, .77, Curves.easeOutQuad);
        } else {
          y = -20 + 20 * _phase(t, .77, .90, Curves.easeInOutCubic);
        }
        final stretch =
            math.sin(_phase(t, .14, .49, Curves.linear) * math.pi) * .055;
        final squash =
            math.sin(_phase(t, .60, .74, Curves.linear) * math.pi) * .07;
        final cloudW = box.maxWidth * .34;
        final rise = _phase(t, .18, .66, Curves.easeOutCubic);
        final part = _phase(t, .30, .88, Curves.easeInOutCubic);
        final cloudY = travel * (1 - rise) - math.sin(rise * math.pi) * 16;

        return IgnorePointer(
          child: Stack(
            key: const ValueKey('friend-arrival-stage'),
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              for (final side in [-1.0, 1.0])
                Positioned(
                  left:
                      box.maxWidth / 2 -
                      cloudW / 2 +
                      side * box.maxWidth * (.24 + .25 * part),
                  top: box.maxHeight / 2 - cloudW * .2 + cloudY,
                  width: cloudW,
                  height: cloudW * .45,
                  child: RepaintBoundary(
                    child: Transform.flip(
                      flipX: side > 0,
                      child: CustomPaint(
                        key: ValueKey(
                          side < 0
                              ? 'arrival-cloud-left'
                              : 'arrival-cloud-right',
                        ),
                        painter: const _CloudPainter(),
                      ),
                    ),
                  ),
                ),
              Center(
                child: Transform.translate(
                  offset: Offset(0, y),
                  child: Transform.scale(
                    alignment: Alignment.bottomCenter,
                    scaleX: 1 - stretch * .65 + squash,
                    scaleY: 1 + stretch - squash,
                    child: ExcludeSemantics(
                      excluding: t < .60,
                      child: SizedBox(
                        key: const ValueKey('arrival-character'),
                        child: friend,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Existing cloud artwork, cached independently from its movement.
class _CloudPainter extends CustomPainter {
  const _CloudPainter();
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final puffs = [
      Rect.fromLTWH(0, h * .28, w * .62, h * .5),
      Rect.fromLTWH(w * .1, h * .02, w * .26, h * .5),
      Rect.fromLTWH(w * .25, h * .18, w * .55, h * .5),
      Rect.fromLTWH(w * .12, h * .5, w * .5, h * .42),
      Rect.fromLTWH(w * .4, h * .62, w * .6, h * .36),
    ];
    final shadow = Paint()
      ..color = const Color(0x143A4A8C)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    for (final r in puffs) {
      canvas.drawOval(r.shift(const Offset(0, 6)), shadow);
    }
    final white = Paint()..color = Colors.white;
    for (final r in puffs) {
      canvas.drawOval(r, white);
    }
  }

  @override
  bool shouldRepaint(_CloudPainter old) => false;
}
