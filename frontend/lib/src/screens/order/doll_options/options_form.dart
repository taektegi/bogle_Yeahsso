part of '../doll_options.dart';

class _OptionsForm extends StatelessWidget {
  const _OptionsForm({
    required this.order,
    required this.gift,
    required this.scale,
    required this.textScale,
    required this.onSize,
    required this.onPackaging,
    required this.onOrder,
  });
  final DollOrder order;
  final bool gift;
  final double scale;
  final double textScale;
  final ValueChanged<DollSize> onSize;
  final ValueChanged<bool> onPackaging;
  final VoidCallback onOrder;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Heading(
        number: 2,
        title: '사이즈 선택',
        note: '원하는 사이즈를 선택해 주세요.',
        scale: scale,
        textScale: textScale,
      ),
      SizedBox(height: 16 * scale),
      Expanded(
        flex: 117,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, size) in DollSize.values.indexed) ...[
              if (i > 0) SizedBox(width: 22 * scale),
              Expanded(
                child: _Option(
                  key: ValueKey('doll-size-${size.name}'),
                  selected: order.size == size,
                  title: size.letter,
                  note: '약 ${size.length}',
                  scale: scale,
                  textScale: textScale,
                  semanticsLabel: '${size.letter} 사이즈, 약 ${size.length}',
                  onTap: () => onSize(size),
                ),
              ),
            ],
          ],
        ),
      ),
      Padding(
        padding: EdgeInsets.only(top: 28 * scale, bottom: 13 * scale),
        child: SizedBox(
          height: .6 * scale,
          child: RotatedBox(
            quarterTurns: 1,
            child: SvgPicture.asset(
              'assets/figma/order_section_divider.svg',
              fit: BoxFit.fill,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
      _Heading(
        number: 3,
        title: '포장 선택',
        note: '원하는 포장 방법을 선택해 주세요.',
        scale: scale,
        textScale: textScale,
      ),
      SizedBox(height: 16 * scale),
      Expanded(
        flex: 117,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _Option(
                key: const ValueKey('doll-wrap-basic'),
                selected: !gift,
                title: '일반 포장',
                note: '기본 포장으로 배송됩니다.',
                scale: scale,
                textScale: textScale,
                onTap: () => onPackaging(false),
              ),
            ),
            SizedBox(width: 22 * scale),
            Expanded(
              child: _Option(
                key: const ValueKey('doll-wrap-gift'),
                selected: gift,
                title: '선물포장',
                note: '선물용 포장으로 배송됩니다.',
                scale: scale,
                textScale: textScale,
                onTap: () => onPackaging(true),
              ),
            ),
          ],
        ),
      ),
      SizedBox(height: 22 * scale),
      _Summary(order: order, gift: gift, scale: scale, textScale: textScale),
      SizedBox(height: 17 * scale),
      SizedBox(
        height: math.max(48, 52 * scale),
        child: FilledButton(
          onPressed: onOrder,
          style: FilledButton.styleFrom(
            backgroundColor: BogleColors.logo,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5.53 * scale),
            ),
          ),
          child: Text(
            '주문하기',
            style: TextStyle(
              fontFamily: bogleDisplayFont,
              fontSize: 17.69 * textScale,
            ),
          ),
        ),
      ),
    ],
  );
}
