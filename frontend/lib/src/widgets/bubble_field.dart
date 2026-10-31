import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Figma 299:4379 / 437:2603, updated eight-bubble composition (1194 × 834).
const _frame = Size(1194, 834);
const _lanes = [
  (cx: 25.0, cy: 580.735, d: 238.488, tint: Color(0xFFFFE08A)),
  (cx: 478.212, cy: 797.756, d: 238.488, tint: Color(0xFFD9CBA5)),
  (cx: 1104.745, cy: 410.956, d: 300.703, tint: Color(0xFFADEDF7)),
  (cx: 339.767, cy: 481.032, d: 372.489, tint: Color(0xFFB8C6FF)),
  (cx: 349.339, cy: 143.639, d: 179.465, tint: Color(0xFFBDF1F4)),
  (cx: 725.0, cy: 175.202, d: 170.805, tint: Color(0xFFE4FF9A)),
  (cx: 940.0, cy: 89.280, d: 214.560, tint: Color(0xFFFFC9C4)),
  (cx: 886.546, cy: 658.742, d: 300.703, tint: Color(0xFFB9ECCF)),
];

/// Kept separate from the old bubbles used by Home and the bubble minigame.
final generationBubbleAssets = List<String>.unmodifiable([
  for (var i = 0; i < _lanes.length; i++)
    'assets/figma/generation_bubble_$i.png',
]);

/// Logo reveal endpoint, when bubbles reach the spaced Figma composition.
const bubbleComposedAt = 3.6;

// Originals move as a spaced formation. A shared speed, wrap distance and
// horizontal drift preserve separation forever, including between cycles.
// Wrap only when even the largest, stretched bubble is fully off screen.
const _originalSpeed = 78.0;
const _wrapMargin = 214.0;
const _travel = 834.0 + 2 * _wrapMargin;

const _splitRatio = 0.66;
const _minSplitDiameter = 90.0;
const _maxDroplets = 32;

/// Pastel bubbles rising through the whole screen, drawn over the loading
/// message like the Figma frame. Tapping a bubble splits it in two; the
/// smallest ones pop.
class BubbleField extends StatefulWidget {
  const BubbleField({super.key, required this.running, required this.still});

  /// Advances time. False while backgrounded or waiting on assets.
  final bool running;

  /// Reduced motion / failure: a static composition, taps split instantly.
  final bool still;

  @override
  State<BubbleField> createState() => _BubbleFieldState();
}

class _Droplet {
  _Droplet(this.asset, this.x, this.y, this.d, this.dir, this.speed, this.born);
  final int asset;
  final double x, y, d, dir, speed, born;
}

class _Burst {
  _Burst(this.x, this.y, this.d, this.tint, this.born);
  final double x, y, d, born;
  final Color tint;
}

typedef _Pose = ({double x, double y, double d, double sx, double sy});

class _BubbleFieldState extends State<BubbleField>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late double _t = widget.still ? bubbleComposedAt : 0;
  Duration _last = Duration.zero;
  final _droplets = <_Droplet>[];
  final _bursts = <_Burst>[];

  /// Lane bubbles popped during a given rise cycle stay hidden until the next.
  final _poppedCycle = List<int?>.filled(_lanes.length, null);

  bool get _animating => widget.running && !widget.still;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    if (_animating) _ticker.start();
  }

  @override
  void didUpdateWidget(BubbleField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.still != widget.still) {
      _droplets.clear();
      _bursts.clear();
    }
    if (_animating && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!_animating && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    setState(() {
      _t += dt;
      _droplets.removeWhere((b) => _dropletPose(b).y + b.d < 0);
      _bursts.removeWhere((b) => _t - b.born > 0.6);
    });
  }

  /// Shared circular vertical track; different diameters must not change its
  /// period, otherwise an original would eventually catch another original.
  (double, int) _progress(int i) {
    final lane = _lanes[i];
    final start =
        _frame.height +
        _wrapMargin -
        lane.cy -
        _originalSpeed * bubbleComposedAt;
    final s = start + _originalSpeed * _t;
    final cycle = (s / _travel).floor();
    return (s - cycle * _travel, cycle);
  }

  _Pose? _lanePose(int i) {
    final lane = _lanes[i];
    if (widget.still) {
      if (_poppedCycle[i] == _progress(i).$2) return null;
      return (x: lane.cx, y: lane.cy, d: lane.d, sx: 1, sy: 1);
    }
    final (s, cycle) = _progress(i);
    if (cycle < 0 || _poppedCycle[i] == cycle) return null;
    // Gentle shared drift cannot close the gap between neighbours. Individual
    // jelly distortion stays within the clearance reserved in the layout.
    final sway = math.sin((_t - bubbleComposedAt) * 2 * math.pi / 6.4) * 8;
    final jelly = math.sin((_t - bubbleComposedAt) * 2 * math.pi / 2.8) * 0.018;
    return (
      x: lane.cx + sway,
      y: _frame.height + _wrapMargin - s,
      d: lane.d,
      sx: 1 + jelly,
      sy: 1 - jelly,
    );
  }

  _Pose _dropletPose(_Droplet b) {
    final age = widget.still ? 10.0 : _t - b.born;
    final push = Curves.easeOutBack.transform(math.min(age / 0.6, 1));
    final grow = Curves.elasticOut.transform(math.min(age / 0.8, 1));
    final rise = widget.still ? 0.0 : b.speed * age;
    final sway = math.sin(age * 2 * math.pi / 3.2 + b.dir) * 8;
    final wobble = math.sin(age * 2 * math.pi / 1.4 + b.dir) * 0.03;
    final scale = 0.6 + 0.4 * grow;
    return (
      x: b.x + b.dir * b.d * 0.62 * push + sway,
      y: b.y - rise,
      d: b.d * scale,
      sx: 1 + wobble,
      sy: 1 - wobble,
    );
  }

  void _split(int asset, _Pose pose, double speed, Color tint) {
    final childD = pose.d * _splitRatio;
    if (!widget.still) _bursts.add(_Burst(pose.x, pose.y, pose.d, tint, _t));
    if (childD < _minSplitDiameter || _droplets.length >= _maxDroplets) return;
    for (final dir in const [-1.0, 1.0]) {
      _droplets.add(
        _Droplet(asset, pose.x, pose.y, childD, dir, speed * 1.2 + 12, _t),
      );
    }
  }

  void _tapLane(int i) {
    final pose = _lanePose(i);
    if (pose == null) return;
    setState(() {
      _poppedCycle[i] = _progress(i).$2;
      _split(i, pose, _originalSpeed, _lanes[i].tint);
    });
  }

  void _tapDroplet(_Droplet b) {
    setState(() {
      final pose = _dropletPose(b);
      _droplets.remove(b);
      _split(b.asset, pose, b.speed, _lanes[b.asset].tint);
    });
  }

  @override
  Widget build(BuildContext context) {
    final fadeIn = widget.still ? 1.0 : (_t / 0.6).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final sx = constraints.maxWidth / _frame.width;
        final sy = constraints.maxHeight / _frame.height;
        final sd = math.min(sx, sy);
        Widget bubble(Key key, int asset, _Pose pose, VoidCallback onTap) {
          final d = pose.d * sd;
          return Positioned(
            key: key,
            left: pose.x * sx - d / 2,
            top: pose.y * sy - d / 2,
            width: d,
            height: d,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(pose.sx, pose.sy, 1),
              child: GestureDetector(
                onTapDown: (_) => onTap(),
                child: ClipOval(
                  child: Image.asset(
                    generationBubbleAssets[asset],
                    width: d,
                    height: d,
                    opacity: fadeIn < 1 ? AlwaysStoppedAnimation(fadeIn) : null,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          );
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < _lanes.length; i++)
              if (_lanePose(i) case final pose?)
                bubble(ValueKey('bubble-$i'), i, pose, () => _tapLane(i)),
            for (final b in _droplets)
              bubble(
                ObjectKey(b),
                b.asset,
                _dropletPose(b),
                () => _tapDroplet(b),
              ),
            if (_bursts.isNotEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _BurstPainter(List.of(_bursts), _t, sx, sy, sd),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A soft ring and a few sparkles where a bubble split or popped.
class _BurstPainter extends CustomPainter {
  _BurstPainter(this.bursts, this.t, this.sx, this.sy, this.sd);
  final List<_Burst> bursts;
  final double t, sx, sy, sd;

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in bursts) {
      final p = ((t - b.born) / 0.6).clamp(0.0, 1.0);
      final ease = Curves.easeOutCubic.transform(p);
      final fade = 1 - p;
      final center = Offset(b.x * sx, b.y * sy);
      final r = b.d * sd / 2;
      canvas.drawCircle(
        center,
        r * (0.85 + 0.35 * ease),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5 * fade
          ..color = Colors.white.withValues(alpha: 0.9 * fade),
      );
      final dot = Paint()..color = b.tint.withValues(alpha: fade);
      for (var k = 0; k < 8; k++) {
        final a = k * math.pi / 4 + b.born;
        canvas.drawCircle(
          center + Offset(math.cos(a), math.sin(a)) * r * (0.9 + 0.5 * ease),
          (k.isEven ? 7.0 : 4.5) * sd * fade,
          dot,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => true;
}
