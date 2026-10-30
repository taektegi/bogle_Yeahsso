import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class MeasuredSize extends SingleChildRenderObjectWidget {
  const MeasuredSize({super.key, required this.onSize, required super.child});
  final ValueChanged<Size> onSize;
  @override
  RenderObject createRenderObject(BuildContext context) => _Measured(onSize);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) => (renderObject as _Measured).onSize = onSize;
}

class _Measured extends RenderProxyBox {
  _Measured(this.onSize);
  ValueChanged<Size> onSize;
  Size? _last;
  @override
  void performLayout() {
    super.performLayout();
    if (size == _last) return;
    _last = size;
    final measured = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onSize(measured);
    });
  }
}
