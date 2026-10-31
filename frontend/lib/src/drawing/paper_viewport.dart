import 'dart:math' as math;
import 'package:flutter/widgets.dart';

/// Fit the logical paper without changing ink, undo history or exported pixels.
class PaperViewport {
  const PaperViewport({required this.paper, required this.viewport});
  final Size paper, viewport;
  double get scale => paper.isEmpty || viewport.isEmpty
      ? 1
      : math.min(viewport.width / paper.width, viewport.height / paper.height);
  Offset get origin => Offset(
    (viewport.width - paper.width * scale) / 2,
    (viewport.height - paper.height * scale) / 2,
  );
  Offset toPaper(Offset point, {double zoom = 1, Offset pan = Offset.zero}) =>
      ((point - pan) / zoom - origin) / scale;
  Matrix4 transform({double zoom = 1, Offset pan = Offset.zero}) {
    final offset = origin * zoom + pan;
    return Matrix4.diagonal3Values(scale * zoom, scale * zoom, 1)
      ..setTranslationRaw(offset.dx, offset.dy, 0);
  }
}
