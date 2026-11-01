import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 자식이 필요한 최소 높이가 주어진 높이보다 크면, 스크롤 대신 전체를 같은
/// 비율로 줄여 한 화면에 담는다. 줄인 만큼 자식의 배치 폭은 넓어져 화면
/// 폭을 그대로 채운다. 넉넉하면 그대로 둔다.
///
/// 자식은 고유 크기(intrinsic) 계산을 지원해야 한다. `LayoutBuilder`가
/// 들어 있으면 쓸 수 없다.
class FitToHeight extends SingleChildRenderObjectWidget {
  const FitToHeight({super.key, super.child});

  @override
  RenderFitToHeight createRenderObject(BuildContext context) =>
      RenderFitToHeight();
}

class RenderFitToHeight extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  /// 마지막 배치에서 자식을 줄인 비율. 1이면 줄이지 않았다.
  double get scale => _scale;
  double _scale = 1;

  Matrix4 get _transform => Matrix4.diagonal3Values(_scale, _scale, 1);

  @override
  void performLayout() {
    size = constraints.biggest;
    final child = this.child;
    if (child == null) return;
    // 지금 폭에서 필요한 높이로 비율을 정한다. 줄이면 폭이 넓어져 필요한
    // 높이는 같거나 줄어들므로, 이 비율이면 항상 들어간다.
    final need = child.getMinIntrinsicHeight(size.width);
    _scale = need <= size.height || need <= 0
        ? 1
        : math.max(.01, size.height / need);
    child.layout(BoxConstraints.tight(size / _scale));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (_scale == 1) {
      context.paintChild(child, offset);
      return;
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      _transform,
      (context, offset) => context.paintChild(child, offset),
      oldLayer: layer as TransformLayer?,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintTransform(
      transform: _transform,
      position: position,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.multiply(_transform);

  @override
  double computeMinIntrinsicHeight(double width) => 0;
  @override
  double computeMaxIntrinsicHeight(double width) => 0;
  @override
  double computeMinIntrinsicWidth(double height) => 0;
  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;
}
