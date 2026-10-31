import 'package:flutter/material.dart';
import '../../data/order_repository.dart';
import '../../theme/bogle_theme.dart';
import 'delivery_address_form.dart';
import 'management_widgets.dart';
import 'postcode_search.dart';

class AddressBookScreen extends StatefulWidget {
  const AddressBookScreen({
    super.key,
    required this.repository,
    this.selecting = false,
    this.selectedId,
    this.search,
  });
  final OrderRepository repository;
  final bool selecting;
  final String? selectedId;
  final AddressSearch? search;
  @override
  State<AddressBookScreen> createState() => _AddressBookScreenState();
}

class _AddressBookScreenState extends State<AddressBookScreen> {
  List<DeliveryAddress> _addresses = [];
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final addresses = await widget.repository.fetchAddresses();
      if (mounted) {
        setState(() {
          _addresses = List.of(addresses)
            ..sort(
              (a, b) => (b.isDefault ? 1 : 0).compareTo(a.isDefault ? 1 : 0),
            );
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '배송지를 불러오지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([DeliveryAddress? address]) async {
    final saved = await showDeliveryAddressForm(
      context,
      initial: address,
      firstAddress: _addresses.isEmpty,
      search: widget.search,
      onSave: widget.repository.saveAddress,
    );
    if (!mounted || saved == null) return;
    if (widget.selecting) {
      Navigator.pop(context, saved);
      return;
    }
    await _load();
  }

  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = '배송지 변경을 저장하지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(DeliveryAddress address) async {
    if (await confirmRemoval(
      context,
      '배송지를 삭제할까요?',
      '${address.label} 배송지를 목록에서 삭제해요. 기존 주문의 배송지는 유지돼요.',
    )) {
      await _act(() => widget.repository.deleteAddress(address.id));
    }
  }

  @override
  Widget build(BuildContext context) => ManagementPage(
    title: widget.selecting ? '배송지 선택' : '배송지 관리',
    addLabel: '새 배송지 추가',
    onAdd: () => _edit(),
    busy: _busy,
    error: _error,
    onRetry: _load,
    children: [
      if (!_busy && _addresses.isEmpty && _error == null)
        const ManagementCard(
          child: Text('받으실 주소를 등록해 주세요.\n주소 검색으로 우편번호와 기본주소를 한 번에 입력할 수 있어요.'),
        ),
      for (final address in _addresses)
        ManagementCard(
          key: ValueKey('saved-address-${address.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      address.label,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (address.isDefault) const DefaultLabel(text: '기본 배송지'),
                ],
              ),
              const SizedBox(height: 12),
              Text('${address.recipient} · ${address.phone}'),
              const SizedBox(height: 8),
              Text('(${address.zip}) ${address.street}'),
              if (address.detail.isNotEmpty) Text(address.detail),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (widget.selecting)
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => Navigator.pop(context, address),
                      icon: Icon(
                        widget.selectedId == address.id
                            ? Icons.check_rounded
                            : Icons.local_shipping_outlined,
                      ),
                      label: const Text('이 주소로 선택'),
                    ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _edit(address),
                    child: const Text('수정'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _delete(address),
                    child: const Text('삭제'),
                  ),
                  if (!address.isDefault)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _act(
                              () => widget.repository.setDefaultAddress(
                                address.id,
                              ),
                            ),
                      child: const Text('기본 배송지로 설정'),
                    ),
                ],
              ),
            ],
          ),
        ),
      const SizedBox(height: 12),
      const Text(
        '기본 배송지는 주문할 때 먼저 선택돼요.',
        style: TextStyle(color: BogleColors.muted),
      ),
    ],
  );
}
