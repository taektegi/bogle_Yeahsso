import '../../widgets/bogle_dialog.dart';
import 'package:flutter/material.dart';

import '../../data/order_repository.dart';
import '../../theme/bogle_theme.dart';
import 'profile_widgets.dart';

/// "주문 내역" (마이페이지 design): the latest order in three columns —
/// what it is, where it goes, how far it has come — then earlier orders,
/// each in its own blue-framed card.
class OrdersSection extends StatelessWidget {
  const OrdersSection({
    super.key,
    required this.orders,
    required this.onShop,
    this.onChangeAddress,
  });

  /// Newest first.
  final List<ProfileOrder> orders;
  final VoidCallback onShop;
  final void Function(ProfileOrder)? onChangeAddress;

  @override
  Widget build(BuildContext context) => ProfileSection(
    title: '주문 내역',
    trailing: orders.isEmpty
        ? null
        : TextButton(
            onPressed: () => showAllOrders(context, orders),
            style: TextButton.styleFrom(
              foregroundColor: BogleColors.text,
              minimumSize: const Size(0, 44),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('전체 주문 내역 보기'),
          ),
    child: ProfileCard(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      child: orders.isEmpty
          ? ProfileEmptyState(
              icon: Icons.inventory_2_outlined,
              title: '아직 주문 내역이 없어요',
              message: '좋아하는 캐릭터를 인형으로 만나 보세요.',
              action: '인형 만들러 가기',
              onPressed: onShop,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LatestOrder(
                  order: orders.first,
                  onChangeAddress: onChangeAddress,
                ),
                if (orders.length > 1) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Divider(
                      height: 1,
                      thickness: 1.5,
                      color: ProfileStyle.rule,
                    ),
                  ),
                  const Text(
                    '이전 주문 내역',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: BogleColors.text,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final o in orders.skip(1).take(3))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PastOrder(order: o),
                    ),
                ],
              ],
            ),
    ),
  );
}

class _LatestOrder extends StatelessWidget {
  const _LatestOrder({required this.order, this.onChangeAddress});
  final ProfileOrder order;
  final void Function(ProfileOrder)? onChangeAddress;

  @override
  Widget build(BuildContext context) {
    final ship = order.shipping;
    const divider = VerticalDivider(
      width: 40,
      thickness: 1.5,
      color: ProfileStyle.rule,
    );
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 12,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ArtTile(
                  asset: order.asset,
                  size: 112,
                  radius: 10,
                  color: ProfileStyle.tile,
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.product,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: ProfileStyle.displayTitle,
                      ),
                      const SizedBox(height: 8),
                      _Chips(order.options),
                      const Spacer(),
                      Text(
                        formatWon(order.price),
                        style: ProfileStyle.price.copyWith(fontSize: 18),
                      ),
                      const SizedBox(height: 2),
                      if (order.paymentCompleted)
                        Text('결제 완료', style: ProfileStyle.label),
                      Text(
                        '주문 번호 : ${order.id}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: ProfileStyle.subtle,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          divider,
          Expanded(
            flex: 9,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ColumnTitle(
                  '배송 정보',
                  trailing: IconButton(
                    tooltip: '배송지 바꾸기',
                    onPressed:
                        order.status == ProfileOrderStatus.preparing &&
                            onChangeAddress != null
                        ? () => onChangeAddress!(order)
                        : null,
                    icon: const Icon(
                      Icons.edit_rounded,
                      color: BogleColors.text,
                    ),
                  ),
                ),
                if (ship == null)
                  const Text(
                    '배송이 시작되면 표시돼요.',
                    style: TextStyle(fontSize: 16, color: ProfileStyle.subtle),
                  )
                else ...[
                  _Info('수령인', ship.recipient),
                  _Info('배송지', ship.address),
                  _Info('택배사', ship.courier),
                ],
              ],
            ),
          ),
          divider,
          Expanded(
            flex: 9,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ColumnTitle(
                  '배송 현황',
                  trailing: TextButton(
                    onPressed: () => showOrderDetails(context, order),
                    style: TextButton.styleFrom(
                      foregroundColor: BogleColors.text,
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('자세히'),
                  ),
                ),
                const SizedBox(height: 4),
                DeliverySteps(status: order.status),
                const SizedBox(height: 16),
                StatusChip(order.status.label),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ColumnTitle extends StatelessWidget {
  const _ColumnTitle(this.text, {this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: SizedBox(
      height: 40,
      child: Row(
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(text, style: ProfileStyle.displayTitle),
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    ),
  );
}

/// "수령인  -  이서준"
class _Info extends StatelessWidget {
  const _Info(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 15, color: BogleColors.text),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            '-',
            style: TextStyle(fontSize: 15, color: BogleColors.text),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: BogleColors.text,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Chips extends StatelessWidget {
  const _Chips(this.options);
  final List<String> options;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [for (final o in options) OptionChip(o)],
  );
}

/// An earlier order in its blue frame: the doll, its options, price and
/// number; the date; its status; and a round button for the details.
class _PastOrder extends StatelessWidget {
  const _PastOrder({required this.order});
  final ProfileOrder order;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: const BorderSide(color: ProfileStyle.rule, width: 1.5),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showOrderDetails(context, order),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            ArtTile(
              asset: order.asset,
              size: 96,
              radius: 8,
              color: ProfileStyle.tile,
            ),
            const SizedBox(width: 18),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(order.product, style: ProfileStyle.displayTitle),
                  const SizedBox(height: 6),
                  _Chips(order.options),
                  const SizedBox(height: 8),
                  Text(
                    formatWon(order.price),
                    style: ProfileStyle.price.copyWith(fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '주문 번호 : ${order.id}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: ProfileStyle.subtle,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Center(
                child: Text(
                  order.date,
                  style: const TextStyle(
                    fontSize: 16,
                    color: ProfileStyle.subtle,
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Center(child: StatusChip(order.status.label)),
            ),
            const SizedBox(width: 12),
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x1F3A4A8C),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.chevron_right_rounded,
                size: 26,
                color: BogleColors.logo,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class OrderRow extends StatelessWidget {
  const OrderRow({super.key, required this.order});
  final ProfileOrder order;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: ProfileStyle.border),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => showOrderDetails(context, order),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            ArtTile(asset: order.asset, size: 56, radius: 12),
            const SizedBox(width: 16),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.product,
                    style: ProfileStyle.itemTitle.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  _Chips(order.options),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(order.date, style: ProfileStyle.label),
            ),
            Expanded(
              flex: 2,
              child: Text(
                formatWon(order.price),
                style: ProfileStyle.price.copyWith(fontSize: 16),
              ),
            ),
            StatusChip(order.status.label),
            const SizedBox(width: 12),
            const Icon(Icons.chevron_right_rounded, color: ProfileStyle.subtle),
          ],
        ),
      ),
    ),
  );
}

/// Reference stepper: filled check dots joined by a thin line.
class DeliverySteps extends StatelessWidget {
  const DeliverySteps({super.key, required this.status});
  final ProfileOrderStatus status;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '배송 현황: ${status.label}',
    excludeSemantics: true,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final step in ProfileOrderStatus.values)
          Expanded(
            child: Column(
              children: [
                SizedBox(
                  height: 22,
                  child: Row(
                    children: [
                      Expanded(
                        child: _Line(
                          visible: step.index > 0,
                          done: step.index <= status.index,
                        ),
                      ),
                      _Dot(done: step.index <= status.index),
                      Expanded(
                        child: _Line(
                          visible: step != ProfileOrderStatus.values.last,
                          done: step.index < status.index,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    step.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: step == status
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: step == status
                          ? ProfileStyle.link
                          : ProfileStyle.subtle,
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

class _Dot extends StatelessWidget {
  const _Dot({required this.done});
  final bool done;
  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: done ? BogleColors.logo : const Color(0xFFD9D9D9),
      border: Border.all(color: Colors.white, width: 3),
      boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 3)],
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line({required this.visible, required this.done});
  final bool visible;
  final bool done;
  @override
  Widget build(BuildContext context) => Container(
    height: 1.5,
    color: !visible
        ? Colors.transparent
        : done
        ? BogleColors.logo
        : const Color(0xFFE0E0E0),
  );
}

enum _Filter {
  all('전체'),
  inProgress('진행 중'),
  done('완료');

  const _Filter(this.label);
  final String label;

  bool accepts(ProfileOrder o) => switch (this) {
    all => true,
    inProgress => o.status != ProfileOrderStatus.delivered,
    done => o.status == ProfileOrderStatus.delivered,
  };
}

void showAllOrders(BuildContext context, List<ProfileOrder> orders) =>
    showDialog<void>(
      context: context,
      builder: (context) {
        var filter = _Filter.all;
        return StatefulBuilder(
          builder: (context, setState) {
            final shown = orders.where(filter.accepts).toList();
            return BogleDialog(
              title: '전체 주문 내역',
              icon: Icons.receipt_long_outlined,
              width: 800,
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('닫기'),
                ),
              ],
              child: SizedBox(
                width: 760,
                height: 460,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final f in _Filter.values)
                          ChoiceChip(
                            label: Text(f.label),
                            selected: filter == f,
                            showCheckmark: false,
                            selectedColor: ProfileStyle.statusFill,
                            onSelected: (_) => setState(() => filter = f),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: shown.isEmpty
                          ? const Center(
                              child: Text(
                                '해당하는 주문이 없어요.',
                                style: ProfileStyle.label,
                              ),
                            )
                          : ListView.separated(
                              itemCount: shown.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, i) => OrderRow(order: shown[i]),
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

void showOrderDetails(BuildContext context, ProfileOrder order) =>
    showDialog<void>(
      context: context,
      builder: (context) => BogleDialog(
        title: '주문 상세',
        icon: Icons.inventory_2_outlined,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
        child: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ArtTile(asset: order.asset, size: 80),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(order.product, style: ProfileStyle.itemTitle),
                          const SizedBox(height: 4),
                          Text(
                            '${formatWon(order.price)} · ${order.date}',
                            style: ProfileStyle.value,
                          ),
                          Text('주문번호 ${order.id}', style: ProfileStyle.label),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _Chips(order.options),
                if (order.paymentCompleted) ...[
                  const SizedBox(height: 16),
                  Text(
                    '결제 완료 · ${order.paymentMethod}',
                    style: ProfileStyle.value,
                  ),
                ],
                const SizedBox(height: 24),
                DeliverySteps(status: order.status),
              ],
            ),
          ),
        ),
      ),
    );
