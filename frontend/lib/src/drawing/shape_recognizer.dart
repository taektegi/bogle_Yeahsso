import 'dart:math' as math;
import 'dart:ui';

enum SketchShape { line, ellipse, triangle, rectangle }

/// Geometry only: no timers, widgets, network, or per-frame recognition.
class RecognizedShape {
  RecognizedShape(this.kind, this.points);
  final SketchShape kind;
  final List<Offset> points;
  bool get closed => kind != SketchShape.line;
  Path get path => Path()..addPolygon(points, closed);
}

class ShapeRecognizer {
  /// Resampling bounds the work and removes drawing-speed bias. Deliberately
  /// conservative: a child's freehand character must not become a polygon.
  static RecognizedShape? recognize(List<Offset> input, {double scale = 1}) {
    if (input.length < 2) return null;
    final length = _length(input);
    if (length * scale < 40) return null;
    final p = _resample(input, 96);
    final bounds = _bounds(p);
    final diagonal = Offset(bounds.width, bounds.height).distance;
    final chord = (p.last - p.first).distance;
    if (chord * scale >= 32 && length / chord < 1.12) {
      final maxError = p
          .map((v) => distanceToSegment(v, p.first, p.last))
          .reduce(math.max);
      if (maxError < math.max(2 / scale, chord * .045)) {
        return RecognizedShape(SketchShape.line, [p.first, p.last]);
      }
    }
    if (bounds.shortestSide * scale < 22 || chord > diagonal * .2) {
      return null;
    }
    // Split the closed stroke at its farthest pair so a start in the middle
    // of an edge is not mistaken for an extra corner.
    var a = 0;
    var b = 1;
    var farthest = 0.0;
    for (var i = 0; i < p.length; i++) {
      for (var j = i + 1; j < p.length; j++) {
        final d = (p[i] - p[j]).distanceSquared;
        if (d > farthest) {
          farthest = d;
          a = i;
          b = j;
        }
      }
    }
    final ring = [...p.sublist(a), ...p.sublist(0, a), p[a]];
    final split = b - a;
    final epsilon = diagonal * .045;
    final first = _simplify(ring.sublist(0, split + 1), epsilon);
    final second = _simplify(ring.sublist(split), epsilon);
    final vertices = [
      ...first.take(first.length - 1),
      ...second.take(second.length - 1),
    ];
    // Remove almost-straight joints introduced by a mid-edge start/end.
    var removed = true;
    while (removed && vertices.length > 3) {
      removed = false;
      for (var i = 0; i < vertices.length; i++) {
        if (distanceToSegment(
              vertices[i],
              vertices[(i - 1 + vertices.length) % vertices.length],
              vertices[(i + 1) % vertices.length],
            ) <
            epsilon) {
          vertices.removeAt(i);
          removed = true;
          break;
        }
      }
    }
    if (vertices.length == 3 || vertices.length == 4) {
      final polygon = [...vertices, vertices.first];
      final perimeter = _length(polygon);
      final errors = p
          .map(
            (v) => List.generate(
              vertices.length,
              (i) => distanceToSegment(v, polygon[i], polygon[i + 1]),
            ).reduce(math.min),
          )
          .toList();
      final mean = errors.reduce((a, b) => a + b) / errors.length;
      if (mean < diagonal * .018 &&
          errors.reduce(math.max) < diagonal * .06 &&
          length / perimeter > .84 &&
          length / perimeter < 1.16 &&
          _convex(vertices)) {
        if (vertices.length == 3) {
          return RecognizedShape(SketchShape.triangle, vertices);
        }
        final edges = List.generate(
          4,
          (i) => vertices[(i + 1) % 4] - vertices[i],
        );
        final rightAngles = List.generate(
          4,
          (i) =>
              _dot(edges[i], edges[(i + 1) % 4]).abs() /
              (edges[i].distance * edges[(i + 1) % 4].distance),
        );
        if (rightAngles.every((v) => v < .28)) {
          final axis = edges[0] - edges[2];
          final u = axis / axis.distance;
          final v = Offset(-u.dy, u.dx);
          final local = vertices
              .map((p) => Offset(_dot(p, u), _dot(p, v)))
              .toList();
          final r = _bounds(local);
          return RecognizedShape(
            SketchShape.rectangle,
            [
              r.topLeft,
              r.topRight,
              r.bottomRight,
              r.bottomLeft,
            ].map((p) => u * p.dx + v * p.dy).toList(),
          );
        }
      }
    }
    // Fit an oriented ellipse; axis-aligned circles remain circles. Testing
    // angular travel also rejects figure-eights, spirals and retraced loops.
    var center = bounds.center;
    var xx = 0.0, yy = 0.0, xy = 0.0;
    for (final v in p) {
      final d = v - center;
      xx += d.dx * d.dx;
      yy += d.dy * d.dy;
      xy += d.dx * d.dy;
    }
    final angle = .5 * math.atan2(2 * xy, xx - yy);
    final u = Offset(math.cos(angle), math.sin(angle));
    final v = Offset(-u.dy, u.dx);
    final local = p
        .map((p) => Offset(_dot(p - center, u), _dot(p - center, v)))
        .toList();
    final r = _bounds(local);
    center += u * r.center.dx + v * r.center.dy;
    var rx = r.width / 2, ry = r.height / 2;
    if (math.min(rx, ry) * scale < 11) return null;
    var error = 0.0, maxError = 0.0, travel = 0.0, signedTravel = 0.0;
    double? previous;
    for (final point in p) {
      final d = point - center;
      final x = _dot(d, u) / rx, y = _dot(d, v) / ry;
      final e = (math.sqrt(x * x + y * y) - 1).abs();
      error += e;
      maxError = math.max(maxError, e);
      final t = math.atan2(y, x);
      if (previous != null) {
        final delta = math.atan2(
          math.sin(t - previous),
          math.cos(t - previous),
        );
        travel += delta.abs();
        signedTravel += delta;
      }
      previous = t;
    }
    if (error / p.length > .075 ||
        maxError > .22 ||
        travel > 7.2 ||
        signedTravel.abs() < 5.5) {
      return null;
    }
    if ((rx - ry).abs() / math.max(rx, ry) < .12) {
      rx = ry = (rx + ry) / 2;
    }
    return RecognizedShape(
      SketchShape.ellipse,
      List.generate(128, (i) {
        final t = 2 * math.pi * i / 128;
        return center + u * (rx * math.cos(t)) + v * (ry * math.sin(t));
      }),
    );
  }

  static double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;
  static double distanceToSegment(Offset p, Offset a, Offset b) {
    final d = b - a;
    if (d.distanceSquared == 0) return (p - a).distance;
    return (p - (a + d * (_dot(p - a, d) / d.distanceSquared).clamp(0, 1)))
        .distance;
  }

  static double _length(List<Offset> p) {
    var length = 0.0;
    for (var i = 1; i < p.length; i++) {
      length += (p[i] - p[i - 1]).distance;
    }
    return length;
  }

  static Rect _bounds(List<Offset> p) => Rect.fromLTRB(
    p.map((p) => p.dx).reduce(math.min),
    p.map((p) => p.dy).reduce(math.min),
    p.map((p) => p.dx).reduce(math.max),
    p.map((p) => p.dy).reduce(math.max),
  );

  static List<Offset> _resample(List<Offset> points, int count) {
    final step = _length(points) / (count - 1);
    final result = <Offset>[points.first];
    var walked = 0.0, target = step;
    for (var i = 1; i < points.length; i++) {
      final distance = (points[i] - points[i - 1]).distance;
      if (distance == 0) continue;
      while (target <= walked + distance && result.length < count - 1) {
        result.add(
          Offset.lerp(points[i - 1], points[i], (target - walked) / distance)!,
        );
        target += step;
      }
      walked += distance;
    }
    return [...result, points.last];
  }

  static List<Offset> _simplify(List<Offset> p, double epsilon) {
    if (p.length < 3) return p;
    var maxDistance = 0.0, index = 0;
    for (var i = 1; i < p.length - 1; i++) {
      final d = distanceToSegment(p[i], p.first, p.last);
      if (d > maxDistance) {
        maxDistance = d;
        index = i;
      }
    }
    if (maxDistance <= epsilon) return [p.first, p.last];
    final left = _simplify(p.sublist(0, index + 1), epsilon);
    return [
      ...left.take(left.length - 1),
      ..._simplify(p.sublist(index), epsilon),
    ];
  }

  static bool _convex(List<Offset> vertices) {
    double? sign;
    for (var i = 0; i < vertices.length; i++) {
      final a = vertices[(i + 1) % vertices.length] - vertices[i];
      final b =
          vertices[(i + 2) % vertices.length] -
          vertices[(i + 1) % vertices.length];
      final cross = a.dx * b.dy - a.dy * b.dx;
      if (cross.abs() < 1 || (sign != null && cross * sign < 0)) return false;
      sign = cross;
    }
    return true;
  }
}
