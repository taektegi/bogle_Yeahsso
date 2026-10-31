import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme/bogle_theme.dart';

/// Interactive counterpart of the iPad Colors reference: grid, spectrum,
/// RGB/hex, opacity and a session palette. No platform picker dependency.
class StudioColorPicker extends StatefulWidget {
  const StudioColorPicker({
    super.key,
    required this.color,
    required this.opacity,
    required this.saved,
    required this.onChanged,
  });
  final Color color;
  final double opacity;
  final List<Color> saved;
  final void Function(Color, double) onChanged;

  @override
  State<StudioColorPicker> createState() => _StudioColorPickerState();
}

class _StudioColorPickerState extends State<StudioColorPicker> {
  late Color _color = widget.color;
  late double _opacity = widget.opacity;
  int _tab = 0;
  void _select(Color color, [double? opacity]) {
    setState(() {
      _color = color.withValues(alpha: 1);
      _opacity = opacity ?? _opacity;
    });
    widget.onChanged(_color, _opacity);
  }

  String get _hex =>
      _color.toARGB32().toRadixString(16).substring(2).toUpperCase();

  @override
  Widget build(BuildContext context) => Dialog(
    key: const ValueKey('studio-colors'),
    alignment: Alignment.centerRight,
    insetPadding: const EdgeInsets.fromLTRB(24, 24, 108, 24),
    backgroundColor: const Color(0xFFF4F4F5),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    child: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '그림에서 색상 추출',
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.colorize_rounded),
                ),
                const Expanded(
                  child: Text(
                    '색상',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: bogleDisplayFont,
                      fontSize: 24,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '색상 닫기',
                  onPressed: () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: const Color(0xFFE3E3E6),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  for (final (i, label) in const [
                    (0, '격자'),
                    (1, '스펙트럼'),
                    (2, '슬라이더'),
                  ])
                    Expanded(
                      child: Semantics(
                        selected: _tab == i,
                        child: TextButton(
                          onPressed: () => setState(() => _tab = i),
                          style: TextButton.styleFrom(
                            backgroundColor: _tab == i
                                ? Colors.white
                                : Colors.transparent,
                            foregroundColor: BogleColors.ink,
                            minimumSize: const Size(0, 42),
                            padding: EdgeInsets.zero,
                          ),
                          child: Text(
                            label,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 280,
              child: switch (_tab) {
                0 => _grid(),
                1 => _spectrum(),
                _ => _sliders(),
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text('불투명도', style: TextStyle(fontSize: 16)),
                ),
                Text(
                  '${(_opacity * 100).round()}%',
                  key: const ValueKey('color-opacity-value'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 38,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const CustomPaint(painter: CheckerPainter()),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [_color.withValues(alpha: 0), _color],
                        ),
                      ),
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 0,
                        activeTrackColor: Colors.transparent,
                        inactiveTrackColor: Colors.transparent,
                        thumbColor: Colors.white,
                        overlayColor: Colors.white24,
                      ),
                      child: Slider(
                        key: const ValueKey('color-opacity'),
                        value: _opacity,
                        semanticFormatterCallback: (v) =>
                            '${(v * 100).round()} 퍼센트',
                        onChanged: (v) => _select(_color, v),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(height: 1),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 76,
                    height: 94,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const CustomPaint(painter: CheckerPainter()),
                        ColoredBox(
                          key: const ValueKey('color-preview'),
                          color: _color.withValues(alpha: _opacity),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '저장한 색상',
                        style: TextStyle(
                          fontSize: 13,
                          color: BogleColors.muted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (var i = 0; i < widget.saved.length; i++)
                            Tooltip(
                              message: '저장 색상 ${i + 1}',
                              child: InkResponse(
                                onTap: () => _select(widget.saved[i]),
                                child: SizedBox(
                                  width: 42,
                                  height: 42,
                                  child: Center(
                                    child: Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        color: widget.saved[i],
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: widget.saved[i] == _color
                                              ? BogleColors.ink
                                              : Colors.black12,
                                          width: widget.saved[i] == _color
                                              ? 3
                                              : 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          IconButton(
                            tooltip: '현재 색상 저장',
                            onPressed: () => setState(() {
                              if (!widget.saved.contains(_color)) {
                                if (widget.saved.length >= 9) {
                                  widget.saved.removeAt(0);
                                }
                                widget.saved.add(_color);
                              }
                            }),
                            icon: const Icon(Icons.add_circle_outline_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _grid() => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: Column(
      children: [
        for (var row = 0; row < 10; row++)
          Expanded(
            child: Row(
              children: [
                for (var col = 0; col < 12; col++)
                  Expanded(child: _cell(gridColor(row, col), row, col)),
              ],
            ),
          ),
      ],
    ),
  );
  Widget _cell(Color color, int row, int col) => Semantics(
    button: true,
    label: '색상 ${color.toARGB32().toRadixString(16).substring(2)}',
    selected: _color == color,
    child: GestureDetector(
      onTap: () => _select(color),
      child: Container(
        key: ValueKey('color-cell-$row-$col'),
        decoration: BoxDecoration(
          color: color,
          border: _color == color
              ? Border.all(
                  color: color.computeLuminance() > .55
                      ? BogleColors.ink
                      : Colors.white,
                  width: 3,
                )
              : null,
        ),
      ),
    ),
  );

  Widget _spectrum() {
    final hsv = HSVColor.fromColor(_color);
    return LayoutBuilder(
      builder: (context, box) {
        void select(Offset p) => _select(
          HSVColor.fromAHSV(
            1,
            (p.dx / box.maxWidth).clamp(0.0, 1.0) * 359.9,
            (p.dy / box.maxHeight * 2).clamp(0.0, 1.0),
            ((1 - p.dy / box.maxHeight) * 2).clamp(0.0, 1.0),
          ).toColor(),
        );
        return Semantics(
          label: '스펙트럼 색상 선택, 정확한 값은 슬라이더 탭에서 조절',
          child: GestureDetector(
            key: const ValueKey('color-spectrum'),
            onTapDown: (d) => select(d.localPosition),
            onPanUpdate: (d) => select(d.localPosition),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFFFF0000),
                          Color(0xFFFFFF00),
                          Color(0xFF00FF00),
                          Color(0xFF00FFFF),
                          Color(0xFF0000FF),
                          Color(0xFFFF00FF),
                          Color(0xFFFF0000),
                        ],
                      ),
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white,
                          Colors.transparent,
                          Colors.black,
                        ],
                        stops: [0, .5, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: (hsv.hue / 360 * box.maxWidth - 10).clamp(
                      0,
                      box.maxWidth - 20,
                    ),
                    top:
                        ((hsv.value >= .999
                                        ? hsv.saturation / 2
                                        : 1 - hsv.value / 2) *
                                    box.maxHeight -
                                10)
                            .clamp(0, box.maxHeight - 20),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _color,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [BoxShadow(blurRadius: 3)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _sliders() => Column(
    children: [
      for (var i = 0; i < 3; i++) _channel(i),
      const SizedBox(height: 12),
      TextFormField(
        key: ValueKey('hex-$_hex'),
        initialValue: _hex,
        maxLength: 6,
        decoration: const InputDecoration(
          labelText: 'HEX',
          prefixText: '#',
          counterText: '',
          isDense: true,
        ),
        autocorrect: false,
        onFieldSubmitted: (value) {
          final raw = value.replaceAll('#', '').trim();
          if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(raw)) {
            _select(Color(0xFF000000 | int.parse(raw, radix: 16)));
          }
        },
        validator: (value) => RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(value ?? '')
            ? null
            : '6자리 색상 코드를 입력해 주세요',
        autovalidateMode: AutovalidateMode.onUserInteraction,
      ),
    ],
  );
  Widget _channel(int i) {
    final values = [_color.r, _color.g, _color.b];
    return Row(
      children: [
        SizedBox(width: 44, child: Text(const ['빨강', '초록', '파랑'][i])),
        Expanded(
          child: Slider(
            key: ValueKey('color-channel-$i'),
            value: values[i],
            activeColor: const [Colors.red, Colors.green, Colors.blue][i],
            semanticFormatterCallback: (v) => '${(v * 255).round()}',
            onChanged: (v) {
              values[i] = v;
              _select(
                Color.from(
                  alpha: 1,
                  red: values[0],
                  green: values[1],
                  blue: values[2],
                ),
              );
            },
          ),
        ),
        SizedBox(
          width: 36,
          child: Text('${(values[i] * 255).round()}', textAlign: TextAlign.end),
        ),
      ],
    );
  }
}

/// 12 hue columns, one greyscale row, then shades and tints like the reference.
Color gridColor(int row, int col) {
  if (row == 0) {
    final v = (255 * (1 - col / 11)).round();
    return Color.fromARGB(255, v, v, v);
  }
  const hues = [
    190.0,
    215.0,
    255.0,
    285.0,
    335.0,
    5.0,
    25.0,
    40.0,
    48.0,
    60.0,
    72.0,
    95.0,
  ];
  return HSVColor.fromAHSV(
    1,
    hues[col],
    row <= 5 ? .98 : 1 - (row - 5) * .2,
    row <= 5 ? .25 + row * .15 : 1,
  ).toColor();
}

class CheckerPainter extends CustomPainter {
  const CheckerPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(Colors.white, BlendMode.src);
    final paint = Paint()..color = const Color(0xFFD5D5DA);
    for (var y = 0.0; y < size.height; y += 10) {
      for (var x = 0.0; x < size.width; x += 10) {
        if (((x + y) / 10).round().isEven) {
          canvas.drawRect(
            Rect.fromLTWH(
              x,
              y,
              math.min(10, size.width - x),
              math.min(10, size.height - y),
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(CheckerPainter oldDelegate) => false;
}
