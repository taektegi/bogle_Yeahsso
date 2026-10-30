part of '../doll_options.dart';

class _Heading extends StatelessWidget {
  const _Heading({
    required this.number,
    required this.title,
    required this.note,
    required this.scale,
    required this.textScale,
  });
  final int number;
  final String title;
  final String note;
  final double scale;
  final double textScale;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox.square(
        dimension: 28.5 * scale,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SvgPicture.asset(
              'assets/figma/order_step_circle.svg',
              excludeFromSemantics: true,
            ),
            Text(
              '$number',
              style: TextStyle(
                fontSize: 17.45 * textScale,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
      SizedBox(width: 11 * scale),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16.28 * textScale,
                  fontWeight: FontWeight.w700,
                  color: BogleColors.text,
                  height: 1.43,
                ),
              ),
            ),
            SizedBox(height: 2 * scale),
            Text(
              note,
              style: TextStyle(
                fontSize: 11.63 * textScale,
                fontWeight: FontWeight.w700,
                color: BogleColors.text.withValues(alpha: .5),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _Option extends StatelessWidget {
  const _Option({
    super.key,
    required this.selected,
    required this.title,
    required this.note,
    required this.scale,
    required this.textScale,
    required this.onTap,
    this.semanticsLabel,
  });
  final bool selected;
  final String title;
  final String note;
  final double scale;
  final double textScale;
  final VoidCallback onTap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: semanticsLabel,
    excludeSemantics: semanticsLabel != null,
    child: Material(
      color: selected ? BogleColors.logo : Colors.white,
      animationDuration: Duration(
        milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 180,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(3.49 * scale),
        side: BorderSide(color: BogleColors.logo, width: .6 * scale),
      ),
      elevation: .6,
      shadowColor: const Color(0x26000000),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(8 * scale),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17.45 * textScale,
                  fontWeight: FontWeight.w700,
                  height: 1.34,
                  color: selected ? Colors.white : BogleColors.text,
                ),
              ),
              SizedBox(height: 6 * scale),
              Text(
                note,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.63 * textScale,
                  fontWeight: FontWeight.w700,
                  height: 1.5,
                  color: selected
                      ? Colors.white
                      : BogleColors.text.withValues(alpha: .5),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.order,
    required this.gift,
    required this.scale,
    required this.textScale,
  });
  final DollOrder order;
  final bool gift;
  final double scale;
  final double textScale;

  @override
  Widget build(BuildContext context) {
    final wrapping = gift ? DollExtra.giftWrap.extra * order.quantity : 0;
    final label = TextStyle(
      fontSize: 11.06 * textScale,
      fontWeight: FontWeight.w700,
      height: 1.3,
      color: BogleColors.text.withValues(alpha: .7),
    );
    final price = TextStyle(
      fontSize: 16.59 * textScale,
      fontWeight: FontWeight.w700,
      height: 1.3,
      color: BogleColors.text.withValues(alpha: .8),
    );
    return Container(
      height: math.max(
        83 * scale,
        32 * scale + 42 * textScale * MediaQuery.textScalerOf(context).scale(1),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: 30 * scale,
        vertical: 12 * scale,
      ),
      decoration: BoxDecoration(
        color: BogleColors.logo.withValues(alpha: .2),
        borderRadius: BorderRadius.circular(5.53 * scale),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${order.size.letter} 사이즈  +  ${gift ? '선물포장' : '일반 포장'}',
                  style: label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 8 * scale),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Text(
                        formatWon(
                          order.itemsTotal - wrapping,
                        ).replaceAll('원', ''),
                        style: price,
                      ),
                      SizedBox(width: 22 * scale),
                      Text('+', style: price),
                      SizedBox(width: 22 * scale),
                      Text(
                        formatWon(wrapping).replaceAll('원', ''),
                        style: price,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12 * scale),
          SvgPicture.asset(
            'assets/figma/order_summary_divider.svg',
            height: 61.92 * scale,
            excludeFromSemantics: true,
          ),
          SizedBox(width: 30 * scale),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('총 상품 금액', style: label),
                SizedBox(height: 5 * scale),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formatWon(order.itemsTotal),
                    key: const ValueKey('order-total'),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 22.11 * textScale,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: const Color(0xFF2A54FF),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
