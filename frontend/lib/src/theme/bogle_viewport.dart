import 'dart:math' as math;
import 'package:flutter/widgets.dart';

/// 기기 이름 대신 실제 논리 화면·안전 영역·키보드·글자 크기로 배치를 결정한다.
class BogleViewport {
  const BogleViewport(this.media);
  factory BogleViewport.of(BuildContext context) =>
      BogleViewport(MediaQuery.of(context));
  static const reference = Size(1194, 834);
  final MediaQueryData media;
  Size get size => media.size;
  double get textScale => media.textScaler.scale(1);
  Size get usable => Size(
    math.max(0, size.width - media.padding.horizontal),
    math.max(0, size.height - media.padding.vertical - media.viewInsets.bottom),
  );
  static double designScale(Size size) =>
      math.min(size.width / reference.width, size.height / reference.height);
  double get artScale => designScale(size);
  double get gutter => horizontalInset(size.width);
  static double horizontalInset(double width) =>
      (48 * width / reference.width).clamp(16, 80);
  bool stackPanels(double width) =>
      width < 900 || (textScale > 1.4 && width < 1180);
  bool scrollScene(Size bounds) =>
      bounds.width < 900 || bounds.height < 520 || textScale > 1.25;

  /// 평소의 헤더 높이는 유지하고 큰 글자·좁은 창일 때만 공간을 더 확보한다.
  static double pillHeight(TextScaler scaler) =>
      math.max(55, scaler.scale(24) * 40 / 24 + 15);
  static double headerLineHeight(double width, TextScaler scaler) => math.max(
    55 * (width / reference.width).clamp(1.0, 1.25),
    pillHeight(scaler),
  );
  static double headerHeight(double width, TextScaler scaler) =>
      headerLineHeight(width, scaler) * (width < 640 ? 2 : 1) +
      (width < 640 ? 10 : 0);
}
