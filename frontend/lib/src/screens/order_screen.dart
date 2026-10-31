import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/app_services.dart';
import '../data/character_repository.dart';
import '../data/failures.dart';
import '../data/korean.dart';
import '../data/order_catalog.dart';
import '../data/order_repository.dart';
import '../models/character_friend.dart';
import '../theme/bogle_theme.dart';
import '../theme/bogle_viewport.dart';
import '../widgets/adaptive_panels.dart';
import '../widgets/bogle_widgets.dart';
import '../widgets/fireworks.dart';
import '../widgets/top_bar.dart';
import 'order/doll_options.dart';
import 'order/address_book_screen.dart';
import 'order/delivery_address_form.dart';
import 'order/payment_methods_screen.dart';
import 'order/postcode_search.dart';
import 'create_studio_screen.dart';
import 'profile/orders_section.dart';
import 'profile/profile_widgets.dart';

part 'order/order_parts.dart';
part 'order/order_address.dart';
part 'order/order_done.dart';

enum _Step { pick, options, checkout, done }

/// Turning a friend into a real doll, after the order draft: pick the
/// friend, choose size, material and extras, check delivery and payment,
/// then a celebration with the order number and delivery status.
/// Prices come from the catalog (order_catalog.dart); addresses and placed
/// orders from the order store, so My Page lists them too.
class OrderScreen extends StatefulWidget {
  const OrderScreen({
    super.key,
    required this.repository,
    this.initialFriend,
    this.orderRepository,
    this.now,
    this.confirmPayment,
    this.searchAddress,
  });

  final CharacterRepository repository;
  final CharacterFriend? initialFriend;

  /// Defaults to the app's ([AppServices]).
  final OrderRepository? orderRepository;

  /// Clock for the order date and arrival estimate; injectable for tests.
  final DateTime Function()? now;

  /// Payment, before the order is placed; tests can complete or fail it
  /// deterministically. Without one, completion is simulated locally.
  final Future<void> Function()? confirmPayment;
  final AddressSearch? searchAddress;

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  late final OrderRepository _orders =
      widget.orderRepository ?? AppServices.of(context).orders;

  List<CharacterFriend>? _friends;
  int _index = 0;
  _Step _step = _Step.pick;
  DollOrder _doll = const DollOrder(size: DollSize.small);
  List<DeliveryAddress> _addresses = const [];
  int _address = 0;
  DeliveryAddress? get _deliverTo =>
      _address < _addresses.length ? _addresses[_address] : null;
  String _note = deliveryNotes.first;
  PaymentMethod _payment = PaymentMethod.easyPay;
  List<SavedPaymentMethod> _paymentMethods = const [];
  String? _paymentId;
  SavedPaymentMethod? get _savedPayment =>
      _paymentMethods.where((p) => p.id == _paymentId).firstOrNull;
  bool _agreed = false;
  bool _paying = false;
  String? _paymentError;
  ProfileOrder? _placed;
  bool _loadingOrders = false;
  final _messages = GlobalKey<ScaffoldMessengerState>();
  final _celebrationArtwork = GlobalKey(
    debugLabel: 'order-celebration-artwork',
  );

  // Coordinates measured in each SVG's viewBox, not in the screen viewport.
  // Other drawings have no authored hand anchor and keep the standalone popper.
  ({double aspect, Offset hand})? get _celebrationPose =>
      switch (_friend.assetPath) {
        'assets/figma/character_card.svg' => (
          aspect: 235.895 / 144.8,
          hand: const Offset(193 / 235.895, 45 / 144.8),
        ),
        'assets/figma/character_friend.svg' => (
          aspect: 528.8 / 297.343,
          hand: const Offset(455 / 528.8, 70 / 297.343),
        ),
        _ => null,
      };

  CharacterFriend get _friend => _friends![_index];
  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Why the friends couldn't be loaded.
  String? _loadError;

  Future<void> _load() async {
    final List<CharacterFriend> friends;
    final List<DeliveryAddress> addresses;
    final List<SavedPaymentMethod> payments;
    try {
      friends = await widget.repository.fetchFriends();
      addresses = await _orders.fetchAddresses();
      payments = await _orders.fetchPaymentMethods();
    } catch (error) {
      if (mounted) {
        setState(() => _loadError = failureMessage(error, '잠시 후 다시 시도해 주세요.'));
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _loadError = null;
      _friends = friends;
      _addresses = addresses;
      _address = math.max(0, addresses.indexWhere((a) => a.isDefault));
      _paymentMethods = payments;
      final preferred = payments.where((p) => p.isDefault).firstOrNull;
      _paymentId = preferred?.id;
      _payment = preferred?.kind ?? _payment;
      final at = friends.indexWhere((f) => f.id == widget.initialFriend?.id);
      _index = math.max(0, at);
    });
  }

  void _go(_Step step) {
    if (!_paying) setState(() => _step = step);
  }

  void _back() {
    if (_paying) return;
    switch (_step) {
      case _Step.pick:
        Navigator.of(context).pop();
      case _Step.options:
        _go(_Step.pick);
      case _Step.checkout:
        _go(_Step.options);
      case _Step.done:
        goHome(context);
    }
  }

  Future<void> _pay() async {
    final address = _deliverTo;
    if (_paying || !_agreed || address == null || _step != _Step.checkout) {
      return;
    }
    // Freeze the agreed contents BEFORE awaiting any request.
    final now = _now;
    String two(int n) => n.toString().padLeft(2, '0');
    final order = ProfileOrder(
      id: orderNumber(now),
      product: '${_friend.name} 인형',
      asset: _friend.assetPath,
      options: [..._doll.labels, if (_doll.quantity > 1) '${_doll.quantity}개'],
      date: '${now.year}.${two(now.month)}.${two(now.day)}',
      price: _doll.total,
      status: ProfileOrderStatus.preparing,
      deliveryNote: _note,
      paymentMethod: _savedPayment?.summary ?? _payment.label,
      paymentCompleted: true,
      simulatedPayment: widget.confirmPayment == null,
      shipping: ShippingInfo(
        recipient: address.recipient,
        address: address.full,
        courier: '제작이 끝나면 보내 드려요',
      ),
    );
    setState(() {
      _paying = true;
      _paymentError = null;
    });
    try {
      // Judge demonstration: simulate completion locally, without contacting
      // any payment gateway or creating a charge.
      if (widget.confirmPayment case final confirm?) {
        await confirm();
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
      // A page closed while paying must not place a phantom order.
      if (!mounted) return;
      await _orders.placeOrder(order);
      if (!mounted) return;
      setState(() {
        _placed = order;
        _step = _Step.done;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _paymentError = '주문을 완료하지 못했어요. 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _showOrders() async {
    if (_loadingOrders) return;
    _loadingOrders = true;
    try {
      final orders = await _orders.fetchOrders();
      if (mounted) showAllOrders(context, orders);
    } catch (error) {
      if (mounted) _tell(failureMessage(error, '주문 내역을 불러오지 못했어요. 다시 눌러 주세요.'));
    } finally {
      _loadingOrders = false;
    }
  }

  void _tell(String message) => _messages.currentState
    ?..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _createFriend() async {
    await Navigator.of(
      context,
    ).push(bogleRoute(CreateStudioScreen(repository: widget.repository)));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => withBogleBodyFont(
    context,
    PopScope(
      canPop: !_paying,
      child: AbsorbPointer(
        absorbing: _paying,
        child: ScaffoldMessenger(
          key: _messages,
          child: Scaffold(
            backgroundColor: BogleColors.cream,
            body: Fireworks(
              active: _step == _Step.done,
              style: FireworksStyle.screenFan,
              focusTarget: _celebrationArtwork,
              child: LayoutBuilder(
                builder: (context, box) {
                  final media = MediaQuery.of(context);
                  final sx = box.maxWidth / 1194;
                  final sy = box.maxHeight / 834;
                  final barBottom = AppTopBar.bottomFor(media);
                  final top = barBottom + 76 * sy;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned(
                        left: 43 * sx + media.padding.left,
                        right: 43 * sx + media.padding.right,
                        top: top,
                        bottom: 36 * sy + media.padding.bottom,
                        child: AnimatedSwitcher(
                          duration: Duration(
                            milliseconds:
                                MediaQuery.disableAnimationsOf(context)
                                ? 0
                                : 280,
                          ),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(opacity: animation, child: child),
                          child: KeyedSubtree(
                            key: ValueKey(_step),
                            child: _body(),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.topCenter,
                        child: AppTopBar(
                          repository: widget.repository,
                          title: 'Order',
                        ),
                      ),
                      // Figma 568:2488: 68 pt at (59, 147), solid like every
                      // other page's back button.
                      Positioned(
                        left: 59 * sx,
                        top: top - 44 * sy,
                        child: BogleBackButton(
                          size: math.max(48, 68 * math.min(sx, sy)),
                          inkKey: const ValueKey('order-back'),
                          onTap: _back,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
    font: bogleUiFont,
  );

  Widget _body() {
    final friends = _friends;
    if (friends == null && _loadError != null) {
      return Center(
        child: ProfileEmptyState(
          icon: Icons.cloud_off_rounded,
          title: '친구들을 불러오지 못했어요',
          message: _loadError!,
          action: '다시 불러오기',
          onPressed: () {
            setState(() => _loadError = null);
            _load();
          },
        ),
      );
    }
    if (friends == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (friends.isEmpty) return _noFriends();
    return switch (_step) {
      _Step.pick => _pick(friends),
      _Step.options => _options(),
      _Step.checkout => _checkout(),
      _Step.done => _done(),
    };
  }

  Widget _noFriends() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.toys_rounded, size: 56, color: BogleColors.logo),
        const SizedBox(height: 12),
        const Text(
          '인형으로 만들 친구가 아직 없어요',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: BogleColors.text,
          ),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: '친구 만들러 가기',
          icon: Icons.brush_rounded,
          onPressed: _createFriend,
        ),
      ],
    ),
  );

  // ---- ① 캐릭터 선택 ------------------------------------------------------

  Widget _pick(List<CharacterFriend> friends) => DollFriendPicker(
    friends: friends,
    selected: _index,
    onSelect: (i) => setState(() => _index = i),
    onNext: () => _go(_Step.options),
  );

  // ---- ② 인형 옵션 --------------------------------------------------------

  Widget _options() => DollOptions(
    friend: _friend,
    order: _doll,
    onChanged: (order) => setState(() => _doll = order),
    onOrder: () => _go(_Step.checkout),
  );

  // ---- ③ 주문/결제 --------------------------------------------------------

  Widget _checkout() {
    final address = _deliverTo;
    final accent = Color(_friend.accentHex);
    return LayoutBuilder(
      builder: (context, box) {
        final minimumHeight =
            720.0 * math.max(1, MediaQuery.textScalerOf(context).scale(1));
        final panels = BoglePanelFlow(
          leadingFlex: 5,
          trailingFlex: 6,
          compactLeadingHeight: minimumHeight,
          compactTrailingHeight: minimumHeight,
          leading: _Panel(
            padding: const EdgeInsets.fromLTRB(28, 26, 28, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('주문 상품', style: _Type.panelTitle),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ArtTile(
                      asset: _friend.assetPath,
                      size: 124,
                      radius: 22,
                      color: Color.lerp(accent, Colors.white, .35)!,
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_friend.name} 인형',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: BogleColors.text,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [for (final l in _doll.labels) _Tag(l)],
                          ),
                          const SizedBox(height: 10),
                          Text('수량 ${_doll.quantity}개', style: _Type.muted),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 40, color: BogleColors.line),
                _PriceRow(
                  '상품 금액',
                  '${formatWon(_doll.unitPrice)} × ${_doll.quantity}',
                ),
                _PriceRow(
                  '배송비',
                  _doll.shipping == 0 ? '무료' : formatWon(_doll.shipping),
                ),
                const SizedBox(height: 18),
                const Text('도착까지', style: _Type.panelTitle),
                const SizedBox(height: 14),
                Expanded(child: _Journey(ordered: _now)),
                const Divider(height: 28, color: BogleColors.line),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '총 결제 금액',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: BogleColors.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(formatWon(_doll.total), style: _Type.total),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          trailing: _Panel(
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('배송 정보', style: _Type.panelTitle),
                    const Spacer(),
                    if (address != null)
                      TextButton.icon(
                        onPressed: _chooseAddress,
                        icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                        label: const Text('배송지 변경'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (address != null)
                  _AddressCard(address: address)
                else
                  _NewAddressCard(onTap: _addAddress),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _note,
                  decoration: const InputDecoration(
                    labelText: '배송 메모',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                  ),
                  items: [
                    for (final n in deliveryNotes)
                      DropdownMenuItem(value: n, child: Text(n)),
                  ],
                  onChanged: (n) => setState(() => _note = n ?? _note),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    const Text('결제 수단', style: _Type.panelTitle),
                    const Spacer(),
                    TextButton(
                      onPressed: _choosePayment,
                      child: const Text('결제 수단 관리'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final (i, p) in PaymentMethod.values.indexed)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
                          child: _ChoiceCard(
                            selected: _payment == p,
                            onTap: () => setState(() {
                              _payment = p;
                              _paymentId = _paymentMethods
                                  .where((m) => m.kind == p)
                                  .firstOrNull
                                  ?.id;
                            }),
                            leading: Icon(
                              switch (p) {
                                PaymentMethod.easyPay =>
                                  Icons.account_balance_wallet_outlined,
                                PaymentMethod.card => Icons.credit_card_rounded,
                                PaymentMethod.transfer =>
                                  Icons.account_balance_outlined,
                              },
                              color: BogleColors.logo,
                              size: 26,
                            ),
                            title: p.label,
                            note: _savedPayment?.kind == p
                                ? _savedPayment!.summary
                                : p.note,
                          ),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                _Agreement(
                  value: _agreed,
                  onChanged: (v) => setState(() => _agreed = v),
                ),
                const SizedBox(height: 12),
                if (_paymentError != null) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _paymentError!,
                      key: const ValueKey('order-payment-error'),
                      style: const TextStyle(color: BogleColors.blueStrong),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                PrimaryButton(
                  expanded: true,
                  label: _paying ? '결제하는 중…' : '${formatWon(_doll.total)} 결제하기',
                  icon: _paying
                      ? Icons.hourglass_top_rounded
                      : Icons.check_circle_outline_rounded,
                  onPressed: _agreed && !_paying && address != null
                      ? _pay
                      : null,
                ),
              ],
            ),
          ),
        );
        if (BogleViewport.of(context).stackPanels(box.maxWidth)) return panels;
        if (box.maxHeight < minimumHeight) {
          return SingleChildScrollView(
            child: SizedBox(height: minimumHeight, child: panels),
          );
        }
        return panels;
      },
    );
  }

  Future<void> _chooseAddress() async {
    final previous = _deliverTo?.id;
    final chosen = await Navigator.of(context).push<DeliveryAddress>(
      bogleRoute(
        AddressBookScreen(
          repository: _orders,
          selecting: true,
          selectedId: previous,
          search: widget.searchAddress,
        ),
      ),
    );
    await _refreshAddresses(chosen?.id ?? previous);
  }

  Future<void> _addAddress() async {
    final address = await showDeliveryAddressForm(
      context,
      firstAddress: _addresses.isEmpty,
      search: widget.searchAddress,
      onSave: _orders.saveAddress,
    );
    if (address != null) await _refreshAddresses(address.id);
  }

  Future<void> _refreshAddresses(String? id) async {
    try {
      final addresses = await _orders.fetchAddresses();
      if (!mounted) return;
      final selected = addresses.indexWhere((a) => a.id == id);
      setState(() {
        _addresses = addresses;
        _address = selected >= 0
            ? selected
            : math.max(0, addresses.indexWhere((a) => a.isDefault));
      });
    } catch (error) {
      if (mounted) _tell(failureMessage(error, '배송지를 불러오지 못했어요. 다시 시도해 주세요.'));
    }
  }

  Future<void> _choosePayment() async {
    final chosen = await Navigator.of(context).push<SavedPaymentMethod>(
      bogleRoute(
        PaymentMethodsScreen(
          repository: _orders,
          selecting: true,
          selectedId: _paymentId,
        ),
      ),
    );
    try {
      final methods = await _orders.fetchPaymentMethods();
      if (!mounted) return;
      setState(() {
        _paymentMethods = methods;
        final selected = methods
            .where((p) => p.id == (chosen?.id ?? _paymentId))
            .firstOrNull;
        _paymentId = selected?.id;
        _payment = selected?.kind ?? _payment;
      });
    } catch (error) {
      if (mounted) {
        _tell(failureMessage(error, '결제 수단을 불러오지 못했어요. 다시 시도해 주세요.'));
      }
    }
  }

  // ---- ④ 주문 완료 --------------------------------------------------------

  Widget _done() {
    final order = _placed!;
    final name = _friend.name;
    final arrival = estimatedArrival(_now);
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Rise(
                  child: SizedBox(
                    key: _celebrationArtwork,
                    width: _celebrationPose == null
                        ? null
                        : 170 * _celebrationPose!.aspect,
                    height: 170,
                    child: FriendArtwork(
                      assetPath: _friend.assetPath,
                      semanticsLabel: name,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _Rise(
                  delay: 1,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: BogleColors.logo,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        SizedBox(width: 4),
                        Text(
                          '주문 완료',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _Rise(
                  delay: 1,
                  child: Text(
                    '${particle(name, '이', '가')} 인형이 되어가는 중이에요!',
                    textAlign: TextAlign.center,
                    style: _Type.question,
                  ),
                ),
                const SizedBox(height: 8),
                _Rise(
                  delay: 2,
                  child: Text(
                    '${koreanDate(arrival)}까지 ${toward(_deliverTo?.label ?? '집')} 찾아갈게요',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: BogleColors.muted,
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                _Rise(
                  delay: 3,
                  child: SizedBox(
                    width: 680,
                    child: _Panel(
                      padding: const EdgeInsets.fromLTRB(30, 24, 30, 26),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              _Fact('주문번호', order.id),
                              _Fact('받는 분', order.shipping!.recipient),
                              _Fact('결제 금액', formatWon(order.price)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '결제 완료 · ${order.paymentMethod}',
                            style: _Type.muted,
                          ),
                          const SizedBox(height: 22),
                          DeliverySteps(status: order.status),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                _Rise(
                  delay: 4,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PrimaryButton(
                        secondary: true,
                        label: '홈으로',
                        icon: Icons.home_rounded,
                        onPressed: () => goHome(context),
                      ),
                      const SizedBox(width: 16),
                      PrimaryButton(
                        label: '주문 현황 보기',
                        icon: Icons.receipt_long_rounded,
                        onPressed: _showOrders,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
