import 'package:flutter/material.dart';
import '../theme/bogle_viewport.dart';

/// 넓을 때는 기존 두 칸, 좁을 때는 같은 패널을 위아래로 배치한다.
/// 재배치 중 입력 컨트롤·스크롤 상태도 유지한다.
class BoglePanelFlow extends StatefulWidget {
  const BoglePanelFlow({
    super.key,
    required this.leading,
    required this.trailing,
    this.leadingFlex = 422,
    this.trailingFlex = 607,
    this.gap = 24,
    this.compactLeadingHeight = 240,
    this.compactTrailingHeight = 600,
  });
  final Widget leading, trailing;
  final int leadingFlex, trailingFlex;
  final double gap, compactLeadingHeight, compactTrailingHeight;
  @override
  State<BoglePanelFlow> createState() => _BoglePanelFlowState();
}

class _BoglePanelFlowState extends State<BoglePanelFlow> {
  final _leading = GlobalKey(), _trailing = GlobalKey();
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final left = KeyedSubtree(key: _leading, child: widget.leading);
      final right = KeyedSubtree(key: _trailing, child: widget.trailing);
      if (BogleViewport.of(context).stackPanels(box.maxWidth)) {
        return Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scroll,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: widget.compactLeadingHeight, child: left),
                SizedBox(height: widget.gap),
                SizedBox(height: widget.compactTrailingHeight, child: right),
              ],
            ),
          ),
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: widget.leadingFlex, child: left),
          SizedBox(width: widget.gap),
          Expanded(flex: widget.trailingFlex, child: right),
        ],
      );
    },
  );
}
