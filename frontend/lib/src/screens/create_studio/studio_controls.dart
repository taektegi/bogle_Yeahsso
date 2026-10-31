part of '../create_studio_screen.dart';

// The sketchbook's controls and paper: the mode switch, dock buttons, zoom and
// eraser chips, paper swatches and the painters for paper, eraser ring and
// pencil hover.

/// A calm iOS-style segmented control: a soft track with a white thumb
/// that slides under the chosen option. Used for the drawing/photo switch
/// and the eraser mode so both read as one family.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.height = 46,
    this.segmentWidth = 132,
    this.fontSize = 15,
  });

  final T value;
  final List<(T, IconData?, String)> options;
  final ValueChanged<T> onChanged;
  final double height;
  final double segmentWidth;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final index = options.indexWhere((o) => o.$1 == value);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: BogleColors.ink.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: SizedBox(
        width: segmentWidth * options.length,
        height: height - 6,
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              left: segmentWidth * index,
              top: 0,
              bottom: 0,
              width: segmentWidth,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: BogleColors.ink.withValues(alpha: 0.10),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: Row(
                children: [
                  for (final (option, icon, label) in options)
                    _segment(option, icon, label, option == value),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segment(T option, IconData? icon, String label, bool selected) {
    final color = selected ? BogleColors.ink : BogleColors.muted;
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(option),
        child: SizedBox(
          width: segmentWidth,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: fontSize + 3, color: color),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontFamily: bogleDisplayFont,
                  fontSize: fontSize,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
  });
  final String label;
  final Widget icon;
  final VoidCallback? onTap;
  final bool selected;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: IconButton(
      tooltip: label,
      isSelected: selected,
      onPressed: onTap,
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        backgroundColor: selected ? BogleColors.blueStrong : Colors.transparent,
        foregroundColor: selected ? Colors.white : BogleColors.ink,
      ),
      icon: icon,
    ),
  );
}

/// Material has no eraser icon; a tilted rubber with a filled cap.
class _EraserGlyph extends StatelessWidget {
  const _EraserGlyph({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 24,
    height: 24,
    child: Center(
      child: Transform.rotate(
        angle: 0.65,
        child: Container(
          width: 14,
          height: 22,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: color, width: 2),
          ),
          child: Column(
            children: [
              Expanded(
                child: ColoredBox(color: color, child: const SizedBox.expand()),
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ZoomChip extends StatelessWidget {
  const _ZoomChip({required this.percent, required this.onReset});
  final int percent;
  final VoidCallback onReset;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: 0.94),
    shape: const StadiumBorder(side: BorderSide(color: BogleColors.line)),
    elevation: 2,
    shadowColor: BogleColors.ink.withValues(alpha: 0.12),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onReset,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 14, 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$percent%',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: BogleColors.ink,
              ),
            ),
            Container(
              width: 1,
              height: 14,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: BogleColors.line,
            ),
            const Text(
              '원래 크기로',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: BogleColors.blueStrong,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A small page showing a paper pattern, for the paper menu.
class _PaperSwatch extends StatelessWidget {
  const _PaperSwatch(this.paper, {required this.selected, this.size = 30});
  final Paper paper;
  final bool selected;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(
        color: selected ? BogleColors.blueStrong : BogleColors.ink,
        width: selected ? 2 : 1.4,
      ),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: CustomPaint(painter: PaperPainter(paper, spacing: size / 4)),
    ),
  );
}

/// Goodnotes-like page patterns, drawn in page space so they zoom with it.
class PaperPainter extends CustomPainter {
  PaperPainter(this.paper, {this.spacing = 34});
  final Paper paper;
  final double spacing;

  static const _ink = Color(0xFFD7DDE8);

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = _ink
      ..strokeWidth = spacing < 12 ? 0.8 : 1;
    switch (paper) {
      case Paper.blank:
        return;
      case Paper.dots:
        final dot = Paint()..color = const Color(0xFFBCC5D5);
        final r = spacing < 12 ? 0.9 : 1.8;
        for (var x = spacing / 2; x < size.width; x += spacing) {
          for (var y = spacing / 2; y < size.height; y += spacing) {
            canvas.drawCircle(Offset(x, y), r, dot);
          }
        }
      case Paper.grid:
        for (var x = spacing / 2; x < size.width; x += spacing) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
        }
        for (var y = spacing / 2; y < size.height; y += spacing) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
      case Paper.lines:
        final gap = spacing * 1.3;
        for (var y = gap; y < size.height; y += gap) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
    }
  }

  @override
  bool shouldRepaint(PaperPainter old) =>
      old.paper != paper || old.spacing != spacing;
}

/// The eraser's footprint, so a child can see what it will rub out.
class _EraserRing extends CustomPainter {
  _EraserRing(this.at, this.radius, this.view, {this.fitScale = 1})
    : super(repaint: Listenable.merge([at, view]));
  final ValueNotifier<Offset?> at;
  final double radius, fitScale;
  final ValueNotifier<_View> view;

  @override
  void paint(Canvas canvas, Size size) {
    final p = at.value;
    if (p == null) return;
    canvas.drawCircle(
      p,
      radius,
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );
    canvas.drawCircle(
      p,
      radius,
      Paint()
        ..color = BogleColors.muted
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / (view.value.scale * fitScale),
    );
  }

  @override
  bool shouldRepaint(_EraserRing old) =>
      old.radius != radius ||
      old.fitScale != fitScale ||
      old.at != at ||
      old.view != view;
}

class _PencilHoverPreview extends CustomPainter {
  _PencilHoverPreview(
    this.at,
    this.radius,
    this.view,
    this.color,
    this.eraser, {
    this.fitScale = 1,
  }) : super(repaint: Listenable.merge([at, view]));
  final ValueNotifier<Offset?> at;
  final double radius, fitScale;
  final ValueNotifier<_View> view;
  final Color color;
  final bool eraser;
  @override
  void paint(Canvas canvas, Size size) {
    final point = at.value;
    if (point == null) return;
    final r = math.max(radius, 2 / (view.value.scale * fitScale));
    canvas.drawCircle(
      point,
      r,
      Paint()..color = color.withValues(alpha: eraser ? .7 : .3),
    );
    canvas.drawCircle(
      point,
      r,
      Paint()
        ..color = eraser ? BogleColors.muted : color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 / (view.value.scale * fitScale),
    );
  }

  @override
  bool shouldRepaint(_PencilHoverPreview old) =>
      old.radius != radius ||
      old.fitScale != fitScale ||
      old.color != color ||
      old.eraser != eraser ||
      old.at != at ||
      old.view != view;
}

class _EraserModeChip extends StatelessWidget {
  const _EraserModeChip({
    required this.label,
    required this.short,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String short;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: selected ? BogleColors.blueSoft : Colors.transparent,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 56,
              height: 40,
              child: Center(
                child: Text(
                  short,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? BogleColors.blueStrong
                        : BogleColors.muted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Figma 250:2339's round ✓ (64 pt, the logo's lavender): the drawing is
/// done, go make the friend. Faded until there is something to use, and it
/// pops gently when it becomes ready.
class _DoneButton extends StatelessWidget {
  const _DoneButton({
    required this.enabled,
    required this.onTap,
    this.caption = false,
  });
  final bool enabled;
  final VoidCallback onTap;

  /// "완성" under the button, so it reads as finishing, not as a tool.
  final bool caption;

  @override
  Widget build(BuildContext context) {
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 280);
    return Tooltip(
      message: '친구로 만들기',
      child: Semantics(
        button: true,
        enabled: enabled,
        label: '친구로 만들기',
        excludeSemantics: true,
        child: AnimatedScale(
          duration: motion,
          curve: Curves.easeOutBack,
          scale: enabled ? 1 : .9,
          child: AnimatedOpacity(
            duration: motion,
            opacity: enabled ? 1 : .4,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Lifted off the page with its own shadow, unlike the flat
                // tool buttons.
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: BogleColors.logo.withValues(alpha: .45),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Material(
                    key: const ValueKey('studio-create'),
                    type: MaterialType.transparency,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: enabled ? onTap : null,
                      child: SvgPicture.asset(
                        'assets/figma/studio_done.svg',
                        width: 64,
                        height: 64,
                      ),
                    ),
                  ),
                ),
                if (caption) ...[
                  const SizedBox(height: 6),
                  const Text(
                    '완성',
                    style: TextStyle(
                      fontFamily: bogleDisplayFont,
                      fontSize: 16,
                      color: BogleColors.logo,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
