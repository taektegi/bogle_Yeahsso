/// Doll orders and where they go. The shop is not part of the service API
/// yet, so the app keeps them itself ([InMemoryOrderRepository]); a shop
/// API implements [OrderRepository] when there is one.
library;

import 'local_store.dart';
import 'order_catalog.dart';

enum ProfileOrderStatus {
  preparing('주문접수'),
  making('제작중'),
  shipping('배송중'),
  delivered('배송완료');

  const ProfileOrderStatus(this.label);
  final String label;

  bool get inProgress => this != delivered;
}

/// Delivery details shown in the Figma "배송 정보" column.
class ShippingInfo {
  const ShippingInfo({
    required this.recipient,
    required this.address,
    required this.courier,
  });
  final String recipient;
  final String address;
  final String courier;

  Map<String, Object?> toJson() => {
    'recipient': recipient,
    'address': address,
    'courier': courier,
  };

  factory ShippingInfo.fromJson(Map<String, Object?> json) => ShippingInfo(
    recipient: json['recipient'] as String? ?? '',
    address: json['address'] as String? ?? '',
    courier: json['courier'] as String? ?? '',
  );
}

class ProfileOrder {
  const ProfileOrder({
    required this.id,
    required this.product,
    required this.asset,
    required this.options,
    required this.date,
    required this.price,
    required this.status,
    this.shipping,
    this.deliveryNote = '',
    this.paymentMethod = '',
    this.paymentCompleted = false,
    this.simulatedPayment = false,
  });
  final String id;
  final String product;
  final String asset;
  final List<String> options;
  final String date;
  final int price;
  final ProfileOrderStatus status;
  final ShippingInfo? shipping;
  final String deliveryNote;
  final String paymentMethod;
  final bool paymentCompleted;

  /// Frontend demonstration, never a receipt from a payment provider.
  final bool simulatedPayment;

  ProfileOrder withShipping(ShippingInfo value) => ProfileOrder(
    id: id,
    product: product,
    asset: asset,
    options: options,
    date: date,
    price: price,
    status: status,
    shipping: value,
    deliveryNote: deliveryNote,
    paymentMethod: paymentMethod,
    paymentCompleted: paymentCompleted,
    simulatedPayment: simulatedPayment,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'product': product,
    'asset': asset,
    'options': options,
    'date': date,
    'price': price,
    'status': status.name,
    'shipping': shipping?.toJson(),
    'deliveryNote': deliveryNote,
    'paymentMethod': paymentMethod,
    'paymentCompleted': paymentCompleted,
    'simulatedPayment': simulatedPayment,
  };

  factory ProfileOrder.fromJson(Map<String, Object?> json) => ProfileOrder(
    id: json['id']! as String,
    product: json['product'] as String? ?? '',
    asset: json['asset'] as String? ?? '',
    options: [for (final o in json['options'] as List? ?? const []) '$o'],
    date: json['date'] as String? ?? '',
    price: (json['price'] as num?)?.toInt() ?? 0,
    status:
        ProfileOrderStatus.values.asNameMap()[json['status']] ??
        ProfileOrderStatus.preparing,
    shipping: json['shipping'] is Map
        ? ShippingInfo.fromJson((json['shipping'] as Map).cast())
        : null,
    deliveryNote: json['deliveryNote'] as String? ?? '',
    paymentMethod: json['paymentMethod'] as String? ?? '',
    paymentCompleted: json['paymentCompleted'] == true,
    simulatedPayment: json['simulatedPayment'] == true,
  );
}

/// A saved delivery address.
class DeliveryAddress {
  const DeliveryAddress({
    required this.label,
    required this.recipient,
    required this.phone,
    required this.zip,
    required this.street,
    this.detail = '',
    this.id = '',
    this.isDefault = false,
  });

  /// What the family calls it: "우리 집", "할머니 댁".
  final String label;
  final String recipient;
  final String phone;
  final String zip;
  final String street;
  final String detail;
  final String id;
  final bool isDefault;

  DeliveryAddress copyWith({String? id, bool? isDefault}) => DeliveryAddress(
    id: id ?? this.id,
    isDefault: isDefault ?? this.isDefault,
    label: label,
    recipient: recipient,
    phone: phone,
    zip: zip,
    street: street,
    detail: detail,
  );

  String get full => detail.isEmpty ? street : '$street $detail';

  Map<String, Object?> toJson() => {
    'label': label,
    'recipient': recipient,
    'phone': phone,
    'zip': zip,
    'street': street,
    'detail': detail,
    'id': id,
    'isDefault': isDefault,
  };

  factory DeliveryAddress.fromJson(Map<String, Object?> json) =>
      DeliveryAddress(
        label: json['label'] as String? ?? '',
        recipient: json['recipient'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        zip: json['zip'] as String? ?? '',
        street: json['street'] as String? ?? '',
        detail: json['detail'] as String? ?? '',
        id: json['id'] as String? ?? '',
        isDefault: json['isDefault'] == true,
      );
}

/// Display information only: no PAN, CVC, expiry, bank credentials or token.
class SavedPaymentMethod {
  const SavedPaymentMethod({
    required this.id,
    required this.kind,
    required this.provider,
    required this.nickname,
    this.last4 = '',
    this.isDefault = false,
  });
  final String id, provider, nickname, last4;
  final PaymentMethod kind;
  final bool isDefault;
  String get summary => last4.isEmpty ? provider : '$provider · $last4';
  SavedPaymentMethod copyWith({bool? isDefault}) => SavedPaymentMethod(
    id: id,
    kind: kind,
    provider: provider,
    nickname: nickname,
    last4: last4,
    isDefault: isDefault ?? this.isDefault,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'provider': provider,
    'nickname': nickname,
    'last4': last4,
    'isDefault': isDefault,
  };
  factory SavedPaymentMethod.fromJson(
    Map<String, Object?> json,
  ) => SavedPaymentMethod(
    id: json['id'] as String? ?? '',
    kind: PaymentMethod.values.asNameMap()[json['kind']] ?? PaymentMethod.card,
    provider: json['provider'] as String? ?? '',
    nickname: json['nickname'] as String? ?? '',
    last4: json['last4'] as String? ?? '',
    isDefault: json['isDefault'] == true,
  );
}

abstract interface class OrderRepository {
  /// Newest first.
  Future<List<ProfileOrder>> fetchOrders();

  /// Records a new order at the top of the list. Placing the same order
  /// twice keeps one.
  Future<void> placeOrder(ProfileOrder order);
  Future<void> updateOrderShipping(String id, DeliveryAddress address);

  /// In the order they were added.
  Future<List<DeliveryAddress>> fetchAddresses();
  Future<void> saveAddress(DeliveryAddress address);
  Future<void> deleteAddress(String id);
  Future<void> setDefaultAddress(String id);
  Future<List<SavedPaymentMethod>> fetchPaymentMethods();
  Future<void> savePaymentMethod(SavedPaymentMethod method);
  Future<void> deletePaymentMethod(String id);
  Future<void> setDefaultPaymentMethod(String id);
}

/// Orders and addresses on the device: for this session, or with a
/// [store] across launches.
class InMemoryOrderRepository implements OrderRepository {
  InMemoryOrderRepository({
    List<ProfileOrder> orders = const [],
    List<DeliveryAddress> addresses = const [],
    List<SavedPaymentMethod> paymentMethods = const [],
    LocalStore? store,
  }) : _orders = List.of(orders),
       _addresses = _normalizeAddresses(addresses),
       _payments = _normalizePayments(paymentMethods),
       _store = store;

  final List<ProfileOrder> _orders;
  final List<DeliveryAddress> _addresses;
  final List<SavedPaymentMethod> _payments;
  final LocalStore? _store;
  static const _name = 'orders';
  Future<void> _queue = Future<void>.value();

  static List<DeliveryAddress> _normalizeAddresses(
    List<DeliveryAddress> items,
  ) {
    final defaultAt = items.indexWhere((a) => a.isDefault);
    return [
      for (final (i, a) in items.indexed)
        a.copyWith(
          id: a.id.isEmpty ? 'address-legacy-$i' : a.id,
          isDefault: i == (defaultAt < 0 ? 0 : defaultAt),
        ),
    ];
  }

  static List<SavedPaymentMethod> _normalizePayments(
    List<SavedPaymentMethod> items,
  ) {
    final defaultAt = items.indexWhere((a) => a.isDefault);
    return [
      for (final (i, a) in items.indexed)
        a.copyWith(isDefault: i == (defaultAt < 0 ? 0 : defaultAt)),
    ];
  }

  Future<void>? _restoring;
  Future<void> get _ready =>
      _restoring ??= _restore().catchError((Object error, StackTrace stack) {
        _restoring = null;
        Error.throwWithStackTrace(error, stack);
      });

  Future<void> _restore() async {
    final restored = await readDocument(_store, _name, (value) {
      final saved = value as Map;
      final orders = [
        for (final row in saved['orders'] as List? ?? const [])
          ProfileOrder.fromJson((row as Map).cast()),
      ];
      final addresses = _normalizeAddresses([
        for (final row in saved['addresses'] as List? ?? const [])
          DeliveryAddress.fromJson((row as Map).cast()),
      ]);
      final payments = _normalizePayments([
        for (final row in saved['paymentMethods'] as List? ?? const [])
          SavedPaymentMethod.fromJson((row as Map).cast()),
      ]);
      return (orders, addresses, payments);
    });
    if (restored == null) return;
    _orders
      ..clear()
      ..addAll(restored.$1);
    _addresses
      ..clear()
      ..addAll(restored.$2);
    _payments
      ..clear()
      ..addAll(restored.$3);
  }

  Future<void> _save() async => _store?.write(_name, {
    'orders': [for (final o in _orders) o.toJson()],
    'addresses': [for (final a in _addresses) a.toJson()],
    'paymentMethods': [for (final p in _payments) p.toJson()],
  });

  /// Serialize edits and roll back failed writes, so retry never pretends a
  /// failed order/address was saved or overwrites a concurrent management edit.
  Future<void> _write(void Function() edit) {
    final task = _queue.then((_) async {
      await _ready;
      final oldOrders = List.of(_orders);
      final oldAddresses = List.of(_addresses);
      final oldPayments = List.of(_payments);
      try {
        edit();
        await _save();
      } catch (_) {
        _orders
          ..clear()
          ..addAll(oldOrders);
        _addresses
          ..clear()
          ..addAll(oldAddresses);
        _payments
          ..clear()
          ..addAll(oldPayments);
        rethrow;
      }
    });
    _queue = task.catchError((Object _) {});
    return task;
  }

  @override
  Future<List<ProfileOrder>> fetchOrders() async {
    await _ready;
    await _queue;
    return List.unmodifiable(_orders);
  }

  @override
  Future<void> placeOrder(ProfileOrder order) => _write(() {
    if (_orders.any((existing) => existing.id == order.id)) return;
    _orders.insert(0, order);
  });

  @override
  Future<void> updateOrderShipping(String id, DeliveryAddress address) =>
      _write(() {
        final at = _orders.indexWhere((o) => o.id == id);
        if (at < 0 || _orders[at].status != ProfileOrderStatus.preparing) {
          throw StateError(
            'Only a newly received order can change its address.',
          );
        }
        _orders[at] = _orders[at].withShipping(
          ShippingInfo(
            recipient: address.recipient,
            address: address.full,
            courier: _orders[at].shipping?.courier ?? '제작이 끝나면 보내 드려요',
          ),
        );
      });

  @override
  Future<List<DeliveryAddress>> fetchAddresses() async {
    await _ready;
    await _queue;
    return List.unmodifiable(_addresses);
  }

  @override
  Future<void> saveAddress(DeliveryAddress address) => _write(() {
    final value = address.id.isEmpty
        ? address.copyWith(
            id: 'address-${DateTime.now().microsecondsSinceEpoch}',
          )
        : address;
    final at = _addresses.indexWhere((a) => a.id == value.id);
    if (at >= 0 && _addresses[at].isDefault && !value.isDefault) {
      final next = _addresses.indexWhere((a) => a.id != value.id);
      if (next >= 0) {
        _addresses[next] = _addresses[next].copyWith(isDefault: true);
      }
    }
    if (value.isDefault) {
      for (var i = 0; i < _addresses.length; i++) {
        _addresses[i] = _addresses[i].copyWith(isDefault: false);
      }
    }
    if (at < 0) {
      _addresses.add(value);
    } else {
      _addresses[at] = value;
    }
    final normalized = _normalizeAddresses(_addresses);
    _addresses
      ..clear()
      ..addAll(normalized);
  });

  @override
  Future<void> deleteAddress(String id) => _write(() {
    _addresses.removeWhere((a) => a.id == id);
    final normalized = _normalizeAddresses(_addresses);
    _addresses
      ..clear()
      ..addAll(normalized);
  });

  @override
  Future<void> setDefaultAddress(String id) => _write(() {
    if (!_addresses.any((a) => a.id == id)) return;
    for (var i = 0; i < _addresses.length; i++) {
      _addresses[i] = _addresses[i].copyWith(isDefault: _addresses[i].id == id);
    }
  });

  @override
  Future<List<SavedPaymentMethod>> fetchPaymentMethods() async {
    await _ready;
    await _queue;
    return List.unmodifiable(_payments);
  }

  @override
  Future<void> savePaymentMethod(SavedPaymentMethod method) => _write(() {
    final at = _payments.indexWhere((p) => p.id == method.id);
    if (at >= 0 && _payments[at].isDefault && !method.isDefault) {
      final next = _payments.indexWhere((p) => p.id != method.id);
      if (next >= 0) {
        _payments[next] = _payments[next].copyWith(isDefault: true);
      }
    }
    if (method.isDefault) {
      for (var i = 0; i < _payments.length; i++) {
        _payments[i] = _payments[i].copyWith(isDefault: false);
      }
    }
    if (at < 0) {
      _payments.add(method);
    } else {
      _payments[at] = method;
    }
    final normalized = _normalizePayments(_payments);
    _payments
      ..clear()
      ..addAll(normalized);
  });

  @override
  Future<void> deletePaymentMethod(String id) => _write(() {
    _payments.removeWhere((p) => p.id == id);
    final normalized = _normalizePayments(_payments);
    _payments
      ..clear()
      ..addAll(normalized);
  });

  @override
  Future<void> setDefaultPaymentMethod(String id) => _write(() {
    if (!_payments.any((p) => p.id == id)) return;
    for (var i = 0; i < _payments.length; i++) {
      _payments[i] = _payments[i].copyWith(isDefault: _payments[i].id == id);
    }
  });
}
