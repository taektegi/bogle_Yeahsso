part of '../house_widgets.dart';

// The comic speech balloon and its tails.

/// A comic speech balloon (Blambot's lettering rules): it sits just above
/// the speaker's head and its short tail points at the mouth, stopping
/// about halfway there instead of touching the face. The tail hangs
/// wherever along the bottom the balloon's placement needs ([tailRoot]).
///
/// [boxy] is Figma 576:2848's balloon in the house, drawn as one shape: a
/// white box (corners 2 pt) whose left edge runs straight on down to a
/// 40 × 40 pointed tail at its bottom-left corner, and 20 pt 양진체 lettering.
/// [tailRight] mirrors it, the point under the right edge. Its tail sits
/// where Figma has it, so [tailSkew] and [tailRoot] don't apply to it.
class SpeechBubble extends StatelessWidget {
  const SpeechBubble({
    super.key,
    required this.text,
    this.tailSkew = 0,
    this.tailRoot = defaultTailRoot,
    this.maxWidth = widest,
    this.boxy = false,
    this.tailRight = false,
    this.speaker,
    this.footer,
    this.sideTail = false,
  });
  final String text;

  /// Sideways run of the tail per point of drop; negative leans left.
  final double tailSkew;

  /// Where the tail meets the balloon, from its left edge.
  final double tailRoot;
  final double maxWidth;
  final bool boxy;
  final bool tailRight;
  final String? speaker, footer;
  final bool sideTail;

  static const tailHeight = 24.0;
  static const defaultTailRoot = 46.0;

  /// The tail keeps this far from the balloon's rounded ends.
  static const tailInset = 30.0;
  static const widest = 340.0;
  static const narrowest = 96.0;
  static const _padding = EdgeInsets.symmetric(horizontal: 20, vertical: 14);
  static const textStyle = TextStyle(
    fontSize: 18,
    height: 1.35,
    fontWeight: FontWeight.w700,
    color: BogleColors.text,
  );

  /// Figma's box: its tail is 40 pt tall and 40 wide where it meets it.
  static const boxyTailHeight = 40.0;
  static const _boxyPadding = EdgeInsets.symmetric(
    horizontal: 28,
    vertical: 26,
  );
  static const boxyTextStyle = TextStyle(
    fontFamily: bogleDisplayFont,
    fontSize: 20,
    height: 1.4,
    letterSpacing: -0.6,
    color: BogleColors.text,
  );

  /// Figma 576:2848's outline at [size] (tail included): corners 2 pt, the
  /// left edge carrying straight on to the tail's point at the bottom-left,
  /// the tail's top 40 pt wide; [tailRight] mirrors it.
  static Path boxyOutline(Size size, {bool tailRight = false}) {
    const tail = boxyTailHeight, r = 2.0, corner = Radius.circular(r);
    final w = size.width, b = size.height - tail;
    final path = Path()
      ..moveTo(r, 0)
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: corner)
      ..lineTo(w, b - r)
      ..arcToPoint(Offset(w - r, b), radius: corner)
      ..lineTo(tail, b)
      ..lineTo(0, b + tail)
      ..lineTo(0, r)
      ..arcToPoint(const Offset(r, 0), radius: corner)
      ..close();
    if (!tailRight) return path;
    return path.transform(
      Float64List.fromList([-1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, w, 0, 0, 1]),
    );
  }

  /// The side-facing variant shares the bottom edge with its tail. One
  /// continuous outline keeps the corner aligned, like the default balloon.
  static Path sideOutline(Size size, {bool tailRight = false}) {
    final body = size.width - boxyTailHeight;
    final root = math.max(2.0, size.height - boxyTailHeight);
    final path = Path()
      ..moveTo(2, 0)
      ..lineTo(body - 2, 0)
      ..arcToPoint(Offset(body, 2), radius: const Radius.circular(2))
      ..lineTo(body, root)
      ..lineTo(size.width, size.height)
      ..lineTo(2, size.height)
      ..arcToPoint(Offset(0, size.height - 2), radius: const Radius.circular(2))
      ..lineTo(0, 2)
      ..arcToPoint(const Offset(2, 0), radius: const Radius.circular(2))
      ..close();
    if (tailRight) return path;
    return path.transform(
      Float64List.fromList([
        -1,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
        0,
        size.width,
        0,
        0,
        1,
      ]),
    );
  }

  static double tailHeightOf({required bool boxy}) =>
      boxy ? boxyTailHeight : tailHeight;

  /// The balloon's size (tail included) before it is laid out, for
  /// deciding where it fits.
  static Size estimate(
    BuildContext context,
    String text, {
    double maxWidth = widest,
    bool boxy = false,
    String? speaker,
    String? footer,
    bool sideTail = false,
  }) {
    final basePadding = boxy ? _boxyPadding : _padding;
    final padding = sideTail
        ? basePadding.copyWith(right: basePadding.right + boxyTailHeight)
        : basePadding;
    final painter = TextPainter(
      text: TextSpan(
        text: keepWords(text),
        style: boxy
            ? boxyTextStyle
            : DefaultTextStyle.of(context).style
                  .merge(const TextStyle(fontFamily: bogleBodyFont))
                  .merge(textStyle),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: maxWidth - padding.horizontal);
    final size = Size(
      math.max(narrowest, painter.width + padding.horizontal),
      painter.height +
          padding.vertical +
          (sideTail ? 0 : tailHeightOf(boxy: boxy)) +
          (speaker == null ? 0 : 22) +
          (footer == null ? 0 : 20),
    );
    painter.dispose();
    return size;
  }

  @override
  Widget build(BuildContext context) {
    final words = Text(
      keepWords(text),
      key: const ValueKey('house-bubble'),
      textAlign: TextAlign.center,
      style: boxy ? boxyTextStyle : textStyle,
    );
    if (boxy) {
      return Semantics(
        liveRegion: true,
        child: CustomPaint(
          painter: _BoxyBalloon(tailRight: tailRight, sideTail: sideTail),
          child: Padding(
            padding: sideTail
                ? EdgeInsets.only(
                    left: tailRight ? 0 : boxyTailHeight,
                    right: tailRight ? boxyTailHeight : 0,
                  )
                : const EdgeInsets.only(bottom: boxyTailHeight),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: narrowest,
                maxWidth: maxWidth,
              ),
              child: Padding(
                padding: _boxyPadding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (speaker != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          speaker!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: bogleUiFont,
                            fontSize: 13,
                            height: 18 / 13,
                            color: BogleColors.logo,
                          ),
                        ),
                      ),
                    words,
                    if (footer != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          footer!,
                          style: const TextStyle(
                            fontFamily: bogleUiFont,
                            fontSize: 12,
                            height: 16 / 12,
                            color: BogleColors.muted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Semantics(
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              minWidth: narrowest,
              maxWidth: maxWidth,
            ),
            padding: _padding,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x223A4A8C),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: words,
          ),
          // Only as wide as the tail's root: it paints past its box, and must
          // not make the column wider than the balloon.
          CustomPaint(
            size: Size(tailRoot, tailHeight),
            painter: _Tail(tailRoot, tailRoot + tailSkew * tailHeight),
          ),
        ],
      ),
    );
  }
}

/// Korean wraps between any two syllables by default ("기쁘지 / 요!");
/// word joiners keep each word whole so lines break only at spaces.
String keepWords(String text) =>
    text.split(' ').map((w) => w.characters.join('\u2060')).join(' ');

/// A tapered, slightly curved tail from the balloon's bottom to [tip].
class _Tail extends CustomPainter {
  _Tail(this.root, this.tip);
  final double root;
  final double tip;

  @override
  void paint(Canvas canvas, Size s) {
    const half = 13.0;
    final h = s.height;
    // Starts inside the balloon so no seam shows where they meet.
    canvas.drawPath(
      Path()
        ..moveTo(root - half, -2)
        ..quadraticBezierTo(
          root - half * .4 + (tip - root) * .3,
          h * .55,
          tip,
          h,
        )
        ..quadraticBezierTo(
          root + half * .6 + (tip - root) * .4,
          h * .45,
          root + half,
          -2,
        )
        ..close(),
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_Tail old) => old.tip != tip || old.root != root;
}

/// Figma 576:2848 ("Union") as one path, so the tail meets the box without
/// a seam: box corners 2 pt, the left edge carrying straight on to the
/// tail's point, the tail's top 40 pt wide. A soft 15 % shadow (the house
/// cards') follows the whole outline.
class _BoxyBalloon extends CustomPainter {
  _BoxyBalloon({required this.tailRight, this.sideTail = false});
  final bool tailRight;
  final bool sideTail;

  @override
  void paint(Canvas canvas, Size size) {
    final Path balloon;
    if (sideTail) {
      balloon = SpeechBubble.sideOutline(size, tailRight: tailRight);
    } else {
      balloon = SpeechBubble.boxyOutline(size, tailRight: tailRight);
    }
    canvas.drawPath(
      balloon,
      Paint()
        ..color = const Color(0x26000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawPath(balloon, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_BoxyBalloon old) =>
      old.tailRight != tailRight || old.sideTail != sideTail;
}
