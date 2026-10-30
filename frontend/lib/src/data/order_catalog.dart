/// The doll shop's options and prices, set by the app until a shop API
/// supplies them. Orders and addresses live in `order_repository.dart`.
library;

enum DollSize {
  small('S', '20cm', 0, .62),
  medium('M', '30cm', 9000, .8),
  large('L', '45cm', 19000, 1);

  const DollSize(this.letter, this.length, this.extra, this.previewScale);
  final String letter;
  final String length;
  final int extra;

  /// How large the preview drawing stands in its frame.
  final double previewScale;
}

enum DollMaterial {
  minky('보들 극세사', '가볍고 포근해요', 0, 0xFFDCD3FF),
  fur('몽글 퍼', '결이 길고 폭신해요', 4000, 0xFFFFCBD8),
  cotton('유기농 코튼', '순한 천연 소재예요', 6000, 0xFFCDE7C2);

  const DollMaterial(this.label, this.note, this.extra, this.swatch);
  final String label;
  final String note;
  final int extra;
  final int swatch;
}

enum DollExtra {
  giftWrap('선물 포장', 3000),
  nameStitch('이름 자수', 5000),
  keyring('키링 고리', 2000);

  const DollExtra(this.label, this.extra);
  final String label;
  final int extra;
}

enum PaymentMethod {
  easyPay('간편결제', '선택한 간편결제로'),
  card('신용·체크카드', '선택한 카드로'),
  transfer('계좌이체', '선택한 계좌로');

  const PaymentMethod(this.label, this.note);
  final String label;
  final String note;
}

class DollOrder {
  const DollOrder({
    this.size = DollSize.medium,
    this.material = DollMaterial.minky,
    this.extras = const {},
    this.quantity = 1,
  });

  static const basePrice = 29000;
  static const shippingFee = 3000;
  static const freeShippingFrom = 50000;
  static const maxQuantity = 5;

  final DollSize size;
  final DollMaterial material;
  final Set<DollExtra> extras;
  final int quantity;

  int get unitPrice =>
      basePrice +
      size.extra +
      material.extra +
      extras.fold(0, (sum, e) => sum + e.extra);
  int get itemsTotal => unitPrice * quantity;
  int get shipping => itemsTotal >= freeShippingFrom ? 0 : shippingFee;
  int get total => itemsTotal + shipping;

  /// For the order summary and My Page, in a fixed order.
  List<String> get labels => [
    '${size.letter} 사이즈 (${size.length})',
    material.label,
    for (final e in DollExtra.values)
      if (extras.contains(e)) e.label,
  ];

  DollOrder copyWith({
    DollSize? size,
    DollMaterial? material,
    Set<DollExtra>? extras,
    int? quantity,
  }) => DollOrder(
    size: size ?? this.size,
    material: material ?? this.material,
    extras: extras ?? this.extras,
    quantity: quantity ?? this.quantity,
  );
}

const deliveryNotes = ['문 앞에 놓아 주세요', '경비실에 맡겨 주세요', '배송 전에 연락 주세요'];

/// Doll making takes 7–10 days and delivery 2–3 more.
DateTime estimatedArrival(DateTime ordered) =>
    DateTime(ordered.year, ordered.month, ordered.day + 12);

/// "BG260927-4821": date plus a short tail, readable over the phone.
String orderNumber(DateTime at) {
  String two(int n) => n.toString().padLeft(2, '0');
  final tail = (at.millisecondsSinceEpoch % 10000).toString().padLeft(4, '0');
  return 'BG${two(at.year % 100)}${two(at.month)}${two(at.day)}-$tail';
}

/// "10월 9일 (금)".
String koreanDate(DateTime d) {
  const days = ['월', '화', '수', '목', '금', '토', '일'];
  return '${d.month}월 ${d.day}일 (${days[d.weekday - 1]})';
}
