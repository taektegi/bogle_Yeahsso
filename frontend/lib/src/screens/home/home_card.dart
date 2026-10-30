part of '../home_screen.dart';

class _HomeCard extends StatefulWidget {
  const _HomeCard({
    super.key,
    required this.appear,
    required this.label,
    required this.semantics,
    required this.colors,
    required this.onTap,
    required this.art,
  });
  final Animation<double> appear;
  final String label;
  final String semantics;
  final List<Color> colors;
  final VoidCallback onTap;
  final Widget art;

  @override
  State<_HomeCard> createState() => _HomeCardState();
}

class _HomeCardState extends State<_HomeCard> {
  bool _pressed = false;

  void _press(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final deep = widget.colors.last;
    final radius = BorderRadius.circular(50);
    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: widget.colors,
        ),
        boxShadow: [
          BoxShadow(
            color: deep.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            const _CardBubbles(),
            Positioned.fill(
              // The label keeps about a quarter of the card and shrinks to
              // fit it, so short cards (and large system text) never
              // overflow; the art takes the rest.
              child: LayoutBuilder(
                builder: (context, box) => Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    box.maxHeight * .08,
                    20,
                    box.maxHeight * .08,
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: widget.art,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: (box.maxHeight * .24).clamp(28.0, 56.0),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            widget.label,
                            style: TextStyle(
                              fontFamily: bogleDisplayFont,
                              fontSize: 40,
                              height: 1.2,
                              letterSpacing: -1.2,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  color: Color.lerp(
                                    deep,
                                    Colors.black,
                                    0.25,
                                  )!.withValues(alpha: 0.45),
                                  offset: const Offset(0, 3),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Bloom(
      appear: widget.appear,
      seed: widget.label.length,
      child: Semantics(
        button: true,
        label: widget.semantics,
        excludeSemantics: true,
        child: GestureDetector(
          onTapDown: (_) => _press(true),
          onTapCancel: () => _press(false),
          onTapUp: (_) => _press(false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _pressed ? 0.95 : 1,
            duration: Duration(milliseconds: _pressed ? 110 : 420),
            curve: _pressed ? Curves.easeOut : Curves.elasticOut,
            child: card,
          ),
        ),
      ),
    );
  }
}
