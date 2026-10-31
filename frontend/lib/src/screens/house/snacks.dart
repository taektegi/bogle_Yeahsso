import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/character_friend.dart';
import '../../theme/bogle_theme.dart';
import 'figure_motion.dart';

/// Snacks a child can hand to a friend, drawn in the room's flat style.
enum Snack {
  apple('사과'),
  acorn('도토리'),
  cookie('쿠키'),
  strawberry('딸기');

  const Snack(this.label);
  final String label;

  bool isFavouriteOf(CharacterFriend friend) =>
      friend.favoriteThings.any((f) => f.contains(label));
}

/// A snack, with [bites] (0–2) taken out of it.
class SnackArt extends StatelessWidget {
  const SnackArt({
    super.key,
    required this.snack,
    this.size = 64,
    this.bites = 0,
  });
  final Snack snack;
  final double size;
  final int bites;
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _SnackPainter(snack, bites),
  );
}

class _SnackPainter extends CustomPainter {
  _SnackPainter(this.snack, this.bites);
  final Snack snack;
  final int bites;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    // Bites are cut out of the finished drawing.
    canvas.saveLayer(Offset.zero & size, Paint());
    switch (snack) {
      case Snack.apple:
        canvas.drawCircle(
          Offset(s * .5, s * .56),
          s * .36,
          Paint()..color = const Color(0xFFFF6B6B),
        );
        canvas.drawCircle(
          Offset(s * .38, s * .44),
          s * .08,
          Paint()..color = Colors.white.withValues(alpha: .45),
        );
        canvas.drawLine(
          Offset(s * .5, s * .24),
          Offset(s * .54, s * .12),
          Paint()
            ..color = const Color(0xFF8A5A3B)
            ..strokeWidth = s * .05
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(s * .66, s * .16),
            width: s * .22,
            height: s * .11,
          ),
          Paint()..color = const Color(0xFF63C174),
        );
      case Snack.acorn:
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(s * .5, s * .6),
            width: s * .54,
            height: s * .6,
          ),
          Paint()..color = const Color(0xFFC98B4F),
        );
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(s * .5, s * .42),
            width: s * .66,
            height: s * .44,
          ),
          math.pi,
          math.pi,
          true,
          Paint()..color = const Color(0xFF7A5230),
        );
        canvas.drawLine(
          Offset(s * .5, s * .2),
          Offset(s * .54, s * .1),
          Paint()
            ..color = const Color(0xFF7A5230)
            ..strokeWidth = s * .05
            ..strokeCap = StrokeCap.round,
        );
      case Snack.cookie:
        canvas.drawCircle(
          Offset(s * .5, s * .52),
          s * .38,
          Paint()..color = const Color(0xFFE2B071),
        );
        canvas.drawCircle(
          Offset(s * .5, s * .52),
          s * .38,
          Paint()
            ..color = const Color(0xFFC9914F)
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * .04,
        );
        final chip = Paint()..color = const Color(0xFF6B4226);
        for (final (dx, dy) in const [
          (.38, .4),
          (.6, .38),
          (.46, .6),
          (.66, .6),
          (.32, .62),
        ]) {
          canvas.drawCircle(Offset(s * dx, s * dy), s * .045, chip);
        }
      case Snack.strawberry:
        final berry = Path()
          ..moveTo(s * .18, s * .36)
          ..quadraticBezierTo(s * .5, s * .22, s * .82, s * .36)
          ..quadraticBezierTo(s * .8, s * .72, s * .5, s * .9)
          ..quadraticBezierTo(s * .2, s * .72, s * .18, s * .36)
          ..close();
        canvas.drawPath(berry, Paint()..color = const Color(0xFFFF5C7A));
        final seed = Paint()..color = const Color(0xFFFFE08A);
        for (final (dx, dy) in const [
          (.36, .46),
          (.52, .44),
          (.66, .48),
          (.42, .62),
          (.58, .62),
          (.5, .76),
        ]) {
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(s * dx, s * dy),
              width: s * .04,
              height: s * .06,
            ),
            seed,
          );
        }
        final leaf = Paint()..color = const Color(0xFF63C174);
        for (final a in [-.9, 0.0, .9]) {
          canvas.save();
          canvas.translate(s * .5, s * .3);
          canvas.rotate(a);
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(0, -s * .06),
              width: s * .1,
              height: s * .2,
            ),
            leaf,
          );
          canvas.restore();
        }
    }
    final bite = Paint()..blendMode = BlendMode.clear;
    for (final (i, (dx, dy)) in const [(.86, .36), (.8, .66)].indexed) {
      if (i < bites) canvas.drawCircle(Offset(s * dx, s * dy), s * .17, bite);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SnackPainter old) =>
      old.snack != snack || old.bites != bites;
}

/// The snack tray above the action bar. Drag a snack to the friend, or
/// tap it to hand it over.
class SnackTray extends StatelessWidget {
  const SnackTray({
    super.key,
    required this.friend,
    required this.onGive,
    required this.onDrag,
    required this.onClose,
    this.together = false,
  });
  final CharacterFriend friend;
  final ValueChanged<Snack> onGive;

  /// Where the finger is while dragging (global), or null when released.
  final ValueChanged<Offset?> onDrag;
  final VoidCallback onClose;
  final bool together;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 14, 10, 14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .95),
      borderRadius: BorderRadius.circular(28),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1A3A4A8C),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          together ? '누르면 함께, 끌면 한 친구에게' : '끌어서 먹여 주세요',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: BogleColors.muted,
          ),
        ),
        const SizedBox(width: 14),
        for (final snack in Snack.values)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _TraySnack(
              snack: snack,
              favourite: snack.isFavouriteOf(friend),
              onGive: () => onGive(snack),
              onDrag: onDrag,
            ),
          ),
        IconButton(
          tooltip: '간식 닫기',
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded, color: BogleColors.muted),
        ),
      ],
    ),
  );
}

class _TraySnack extends StatelessWidget {
  const _TraySnack({
    required this.snack,
    required this.favourite,
    required this.onGive,
    required this.onDrag,
  });
  final Snack snack;
  final bool favourite;
  final VoidCallback onGive;
  final ValueChanged<Offset?> onDrag;

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      width: 84,
      height: 92,
      decoration: BoxDecoration(
        color: favourite ? const Color(0xFFFFF1F4) : const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: favourite ? const Color(0xFFFFB6C8) : BogleColors.line,
        ),
      ),
      child: Stack(
        children: [
          Align(
            alignment: const Alignment(0, -.35),
            child: SnackArt(snack: snack, size: 54),
          ),
          Align(
            alignment: const Alignment(0, .82),
            child: Text(
              snack.label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: BogleColors.text,
              ),
            ),
          ),
          if (favourite)
            const Positioned(
              top: 6,
              right: 6,
              child: Icon(
                Icons.favorite_rounded,
                size: 16,
                color: Color(0xFFFF7FA3),
              ),
            ),
        ],
      ),
    );
    return Semantics(
      button: true,
      label: '${snack.label} 주기${favourite ? ', 좋아하는 간식' : ''}',
      excludeSemantics: true,
      child: Draggable<Snack>(
        data: snack,
        onDragStarted: HapticFeedback.selectionClick,
        onDragUpdate: (d) => onDrag(d.globalPosition),
        onDragEnd: (_) => onDrag(null),
        feedback: Material(
          color: Colors.transparent,
          child: Transform.scale(scale: 1.3, child: SnackArt(snack: snack)),
        ),
        childWhenDragging: Opacity(opacity: .35, child: tile),
        child: GestureDetector(onTap: onGive, child: tile),
      ),
    );
  }
}

/// The snack being eaten, on the same beats as the friend's eating act
/// ([eatBites]): it pops up by the mouth, is pushed in and loses a chunk at
/// each chomp — crumbs flying — and is gone after the third. [onBite]
/// fires on every bite, [onDone] when the friend has finished (swallowed
/// and said "yum").
class Eating extends StatefulWidget {
  const Eating({
    super.key,
    required this.snack,
    required this.size,
    required this.onDone,
    this.mouthSide = -1,
    this.onBite,
  });
  final Snack snack;
  final double size;

  /// Which side of the snack the mouth is on: -1 left, 1 right. Bites are
  /// taken from that side.
  final double mouthSide;
  final VoidCallback? onBite;
  final VoidCallback onDone;
  @override
  State<Eating> createState() => _EatingState();
}

class _EatingState extends State<Eating> with SingleTickerProviderStateMixin {
  static final _biteAt = [for (final b in eatBites) b / eatLength];
  late final AnimationController _controller;
  int _bites = 0;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
            vsync: this,
            duration: Duration(milliseconds: (eatLength * 1000).round()),
          )
          ..addListener(_tick)
          ..addStatusListener((s) {
            if (s == AnimationStatus.completed) widget.onDone();
          })
          ..forward();
  }

  void _tick() {
    final due = _biteAt.where((t) => _controller.value >= t).length;
    if (due > _bites) {
      setState(() => _bites = due);
      if (!MediaQuery.disableAnimationsOf(context)) {
        HapticFeedback.lightImpact();
      }
      widget.onBite?.call();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 0..1 around each bite: pushed toward the mouth just before, springing
  /// back just after.
  double _push(double t) {
    var push = 0.0;
    for (final at in _biteAt) {
      final u = (t - at) / .05;
      if (u > -1.4 && u < 2) {
        push = math.max(
          push,
          u < 0
              ? Curves.easeIn.transform(1 + u / 1.4)
              : 1 - Curves.easeOut.transform(u / 2),
        );
      }
    }
    return push;
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (MediaQuery.disableAnimationsOf(context)) {
          return SizedBox.square(
            dimension: widget.size * 1.8,
            child: Center(
              child: SnackArt(
                snack: widget.snack,
                size: widget.size,
                bites: math.min(_bites, 2),
              ),
            ),
          );
        }
        final t = _controller.value;
        final last = _biteAt.last;
        // Pops up beside the mouth, then vanishes into it with the last bite.
        final arrive = Curves.easeOutBack.transform((t / .12).clamp(0.0, 1.0));
        final leave = ((t - last) / .05).clamp(0.0, 1.0);
        final push = _push(t);
        final side = widget.mouthSide;
        return SizedBox.square(
          dimension: widget.size * 1.8,
          child: CustomPaint(
            painter: _CrumbPainter(t, _biteAt, widget.snack, side),
            child: Center(
              child: Opacity(
                opacity: 1 - leave,
                child: Transform.translate(
                  offset: Offset(side * widget.size * .16 * push, 0),
                  child: Transform.scale(
                    scale: arrive * (1 - leave * .6) * (1 - push * .08),
                    child: Transform.flip(
                      // Bitten from the mouth's side.
                      flipX: side < 0,
                      child: SnackArt(
                        snack: widget.snack,
                        size: widget.size,
                        bites: math.min(_bites, 2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// Little crumbs thrown out from the bitten side, falling and fading.
class _CrumbPainter extends CustomPainter {
  _CrumbPainter(this.t, this.biteAt, this.snack, this.side);
  final double t;
  final List<double> biteAt;
  final Snack snack;

  /// The mouth's side: crumbs fly from there.
  final double side;

  Color get _colour => switch (snack) {
    Snack.apple => const Color(0xFFFFE3A3),
    Snack.acorn => const Color(0xFFC98B4F),
    Snack.cookie => const Color(0xFFC9914F),
    Snack.strawberry => const Color(0xFFFF8FA3),
  };

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero) + Offset(side * size.width * .18, 0);
    final random = math.Random(3);
    for (final at in biteAt) {
      final local = (t - at) / .16;
      if (local <= 0 || local >= 1) continue;
      for (var i = 0; i < 7; i++) {
        final angle =
            -math.pi / 2 + side * (random.nextDouble() - .2) * math.pi;
        final speed = size.width * (.18 + random.nextDouble() * .16);
        final p =
            c +
            Offset(math.cos(angle), math.sin(angle)) * speed * local +
            Offset(0, size.width * .35 * local * local);
        canvas.drawCircle(
          p,
          2.2 + random.nextDouble() * 2,
          Paint()..color = _colour.withValues(alpha: 1 - local),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CrumbPainter old) => old.t != t || old.side != side;
}
