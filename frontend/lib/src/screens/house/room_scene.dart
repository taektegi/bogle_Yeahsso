import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../data/window_view.dart';

enum DayTime { morning, day, evening, night }

DayTime dayTimeOf(DateTime t) => switch (t.hour) {
  >= 6 && < 11 => DayTime.morning,
  >= 11 && < 17 => DayTime.day,
  >= 17 && < 20 => DayTime.evening,
  _ => DayTime.night,
};

/// Where the room's pieces go on a screen, from the 1194 × 834 Figma frame
/// (568:2335). Sizes scale with [s]; across, things keep their place in
/// the width; down, the room hangs from the floor line, which stays at
/// Figma's 518 / 834 of the height.
class RoomLayout {
  RoomLayout(this.size, {this.company = 0})
    : sx = size.width / frame.width,
      s = math.min(size.width / frame.width, size.height / frame.height),
      floor = size.height * 518 / frame.height;

  static const frame = Size(1194, 834);

  final Size size;
  final double company;

  /// Horizontal scale, and the scale for sizes.
  final double sx, s;

  /// Top of the baseboard: the wall ends here.
  final double floor;

  /// The window drawing (frame, panes and sill), 1046 × 306, its sill
  /// 68 pt above the floor and centred.
  Rect get window => Rect.fromLTWH(
    size.width / 2 - 523 * s,
    floor - (68 + 306) * s,
    1046 * s,
    306 * s,
  );

  /// The rug's outer ellipse.
  Rect get rug => Rect.fromCenter(
    center: Offset(size.width / 2 - 1.5 * s, floor + (84 + 4 * company) * s),
    width: (357 + 200 * company) * s,
    height: (100 + 8 * company) * s,
  );

  /// Where the friend's feet touch the rug.
  double get feet => floor + 76 * s;

  /// The square the friend stands in.
  double get host => 250 * s;
}

/// Figma 568:2335 / 568:2533: a cream wall with an arched window, a wooden
/// floor, a round blue rug for the friend to stand on, a potted plant and
/// three little plants on the sill. Out of the window is the friend's own
/// [view]. When the friend is asleep the lights go out (Figma's 41 % dark
/// layer over the wall, window and floor); at night the window shows the
/// view's night picture.
class RoomScene extends StatelessWidget {
  const RoomScene({
    super.key,
    required this.view,
    required this.time,
    required this.lightsOff,
    this.company = 0,
    this.bottomOverflow = 0,
  });
  final WindowView view;
  final DayTime time;
  final bool lightsOff;
  final double company;
  final double bottomOverflow;

  static const _wallDay = Color(0xFFFFFEEE);
  static const _wallNight = Color(0xFFC7CCD9);
  static const _dark = Color(0x69000000);
  static const _fade = Duration(milliseconds: 700);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final room = RoomLayout(box.biggest, company: company);
      final s = room.s, window = room.window;
      final fade = MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : _fade;
      Widget svg(String name, double w, double h) => SvgPicture.asset(
        'assets/figma/$name.svg',
        width: w * s,
        height: h * s,
        fit: BoxFit.fill,
        excludeFromSemantics: true,
      );
      // Sill plants, from the window drawing's top-left (Figma 576:2799,
      // 576:2800, 576:2803), standing on the sill.
      Widget onSill(String name, double x, double y, double w, double h) =>
          Positioned(
            left: window.left + x * s,
            top: window.top + y * s,
            child: svg(name, w, h),
          );
      return Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: fade,
            color: lightsOff ? _wallNight : _wallDay,
          ),
          Positioned.fromRect(
            rect: window,
            child: _Window(
              source: view.pick(night: lightsOff || time == DayTime.night),
              dim: (lightsOff || time == DayTime.night) && view.night == null,
              fade: fade,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: room.floor,
            bottom: -bottomOverflow,
            child: CustomPaint(painter: _FloorPainter(s)),
          ),
          IgnorePointer(
            child: AnimatedContainer(
              duration: fade,
              color: lightsOff ? _dark : Colors.transparent,
            ),
          ),
          Positioned.fromRect(
            rect: room.rug,
            child: RepaintBoundary(
              child: CustomPaint(
                key: const ValueKey('house-rug'),
                painter: _RugPainter(s),
              ),
            ),
          ),
          Positioned(
            left: 108.26 * room.sx,
            top: room.floor + (102.2 - 184.46) * s,
            child: svg('house_plant', 142.741, 184.461),
          ),
          onSill('house_sill_plant_c', 866, 204, 39, 83),
          onSill('house_sill_plant_a', 925, 232, 52.5006, 55.0006),
          onSill('house_sill_plant_b', 984, 223, 39, 64),
        ],
      );
    },
  );
}

/// The arched window: the view, cut to the panes' shape, inside a brown
/// frame with a cross of bars and a sill. Drawn in the 1046 × 306 units of
/// Figma's window drawing.
class _Window extends StatelessWidget {
  const _Window({required this.source, required this.dim, required this.fade});
  final String source;

  /// A night with no night picture: the day one, dimmed blue.
  final bool dim;
  final Duration fade;

  static const wood = Color(0xFFB08361);

  /// The glass: half an ellipse over a rectangle, 1010 × 289 from (18, 7).
  static Path pane(double s) => Path()
    ..moveTo(18 * s, 191 * s)
    ..arcTo(
      Rect.fromCenter(
        center: Offset(523 * s, 191 * s),
        width: 1010 * s,
        height: 368 * s,
      ),
      math.pi,
      math.pi,
      false,
    )
    ..lineTo(1028 * s, 296 * s)
    ..lineTo(18 * s, 296 * s)
    ..close();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final s = box.maxWidth / 1046;
      final glass = Rect.fromLTWH(18 * s, 7 * s, 1010 * s, 289 * s);
      return Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _FramePainter(s))),
          Positioned.fill(
            child: ClipPath(
              clipper: _PaneClipper(s),
              child: Stack(
                children: [
                  Positioned.fromRect(
                    rect: glass,
                    child: AnimatedSwitcher(
                      duration: fade,
                      child: Image(
                        key: ValueKey(source),
                        image: WindowView.image(source),
                        fit: BoxFit.cover,
                        width: glass.width,
                        height: glass.height,
                        gaplessPlayback: true,
                        excludeFromSemantics: true,
                        // A picture that won't load: the aquarium instead.
                        errorBuilder: (_, _, _) => Image.asset(
                          WindowView.aquarium.day,
                          fit: BoxFit.cover,
                          width: glass.width,
                          height: glass.height,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fromRect(
                    rect: glass,
                    child: AnimatedContainer(
                      duration: fade,
                      color: dim
                          ? const Color(0x661C2350)
                          : const Color(0x001C2350),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(child: CustomPaint(painter: _BarsPainter(s))),
        ],
      );
    },
  );
}

class _PaneClipper extends CustomClipper<Path> {
  _PaneClipper(this.s);
  final double s;
  @override
  Path getClip(Size size) => _Window.pane(s);
  @override
  bool shouldReclip(_PaneClipper old) => old.s != s;
}

/// The frame: a 7 pt band of wood around the glass (Figma strokes it
/// outside the panes).
class _FramePainter extends CustomPainter {
  _FramePainter(this.s);
  final double s;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    _Window.pane(s),
    Paint()
      ..color = _Window.wood
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14 * s,
  );
  @override
  bool shouldRepaint(_FramePainter old) => old.s != s;
}

/// The cross of bars and the sill (Figma "Line 16", "Line 17" and
/// "Rectangle 34630527").
class _BarsPainter extends CustomPainter {
  _BarsPainter(this.s);
  final double s;
  @override
  void paint(Canvas canvas, Size size) {
    final wood = Paint()..color = _Window.wood;
    canvas.drawRect(Rect.fromLTRB(520 * s, 7 * s, 527 * s, 287 * s), wood);
    canvas.drawRect(Rect.fromLTRB(18 * s, 181 * s, 1028 * s, 188 * s), wood);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 287 * s, 1046 * s, 19 * s),
        Radius.circular(3 * s),
      ),
      wood,
    );
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.s != s;
}

/// Baseboard, boards and the lines between them (Figma 568:2392, 568:2384
/// and "Group 1261155766"), from the floor line down.
class _FloorPainter extends CustomPainter {
  _FloorPainter(this.s);
  final double s;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFCAA57F),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 17 * s),
      Paint()..color = const Color(0xFFE0CDB5),
    );
    final seam = Paint()
      ..color = const Color(0xFFC79969)
      ..strokeWidth = 2;
    for (final y in const [42.0, 79.0, 133.0, 224.0]) {
      if (y * s > size.height) break;
      canvas.drawLine(Offset(0, y * s), Offset(size.width, y * s), seam);
    }
  }

  @override
  bool shouldRepaint(_FloorPainter old) => old.s != s;
}

/// The rug (Figma "Ellipse 180–207"): a #8BA2FF oval with a pale centre
/// and a stitched ring of dots round its front, in 357 × 100 units.
class _RugPainter extends CustomPainter {
  const _RugPainter(this.scale);
  final double scale;
  static const _pale = Color(0xFFBFCCFB);

  @override
  void paint(Canvas canvas, Size size) {
    // 가로로 그림 전체를 늘리지 않고 방의 축척만 균등하게 적용한다.
    // 카펫이 넓어져도 테두리 두께와 장식 점의 크기는 일정하게 유지한다.
    canvas.save();
    canvas.scale(scale);
    final width = size.width / scale, height = size.height / scale;
    final outer = Rect.fromLTWH(0, 0, width, height);
    canvas.drawOval(outer, Paint()..color = const Color(0xFF8BA2FF));
    final pale = Paint()..color = _pale;
    canvas.drawOval(Rect.fromLTWH(20, 9, width - 40, height - 22), pale);
    final center = outer.center;
    final rx = width / 2 - 7, ry = height / 2 - 5;
    // 장식 개수도 고정해 움직이는 도중 점이 갑자기 생기거나 사라지지 않는다.
    for (var i = 0; i < 24; i++) {
      final angle = (i + .5) * 2 * math.pi / 24;
      final front = math.sin(angle) > 0;
      canvas.drawOval(
        Rect.fromCenter(
          center: center + Offset(rx * math.cos(angle), ry * math.sin(angle)),
          width: front ? 11 : 9,
          height: front ? 5 : 4,
        ),
        pale,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RugPainter old) => old.scale != scale;
}
