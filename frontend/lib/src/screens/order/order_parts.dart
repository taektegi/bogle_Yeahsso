part of '../order_screen.dart';

// The order steps' shared pieces: the delivery journey, type styles, panels,
// tags, choice cards and price rows.

/// The doll's way to the child, with dates: ordered, made, sent, arrives.
class _Journey extends StatelessWidget {
  const _Journey({required this.ordered});
  final DateTime ordered;
  @override
  Widget build(BuildContext context) {
    final arrival = estimatedArrival(ordered);
    final sent = arrival.subtract(const Duration(days: 2));
    final steps = [
      (Icons.receipt_long_rounded, '주문 접수', koreanDate(ordered)),
      (Icons.brush_rounded, '보글 공방에서 제작', '7~10일'),
      (Icons.local_shipping_outlined, '배송 출발', koreanDate(sent)),
      (Icons.redeem_rounded, '도착 예정', koreanDate(arrival)),
    ];
    final last = steps.length - 1;
    return Column(
      children: [
        for (final (i, (icon, label, date)) in steps.indexed)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == last
                            ? BogleColors.logo
                            : const Color(0xFFEEF1FF),
                      ),
                      child: Icon(
                        icon,
                        size: 18,
                        color: i == last ? Colors.white : BogleColors.logo,
                      ),
                    ),
                    if (i < last)
                      Expanded(
                        child: Container(
                          width: 2,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          color: const Color(0xFFE3E6EE),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Row(
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: BogleColors.text,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          date,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: i == last
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: i == last
                                ? BogleColors.blueStrong
                                : BogleColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

abstract final class _Type {
  static const question = TextStyle(
    fontFamily: bogleQuestionFont,
    fontSize: 40,
    height: 1.15,
    letterSpacing: -0.4,
    color: BogleColors.text,
  );
  static const panelTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: BogleColors.text,
  );
  static const muted = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: BogleColors.muted,
  );
  static const total = TextStyle(
    fontFamily: bogleDisplayFont,
    fontSize: 28,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    color: BogleColors.blueStrong,
  );
}

/// White card used across the order steps (same as the house cards).
class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(24)});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .94),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: Colors.white),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1A3A4A8C),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: child,
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.strong = false});
  final String text;
  final bool strong;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: strong ? BogleColors.logo : Colors.white.withValues(alpha: .9),
      borderRadius: BorderRadius.circular(999),
      border: strong ? null : Border.all(color: BogleColors.line),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: strong ? Colors.white : BogleColors.text,
      ),
    ),
  );
}

/// One option among a few, shown as a card with a small visual.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.selected,
    required this.onTap,
    required this.leading,
    required this.title,
    required this.note,
  });
  final bool selected;
  final VoidCallback onTap;
  final Widget leading;
  final String title;
  final String note;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? const Color(0xFFEEF1FF) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? BogleColors.logo : BogleColors.line,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: BogleColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      note,
                      maxLines: 2,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: BogleColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PriceRow extends StatelessWidget {
  const _PriceRow(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Text(label, style: _Type.muted.copyWith(fontSize: 15)),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: BogleColors.text,
          ),
        ),
      ],
    ),
  );
}
