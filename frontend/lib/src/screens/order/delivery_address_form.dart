import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/order_repository.dart';
import '../../theme/bogle_theme.dart';
import '../../widgets/bogle_dialog.dart';
import 'postcode_search.dart';

Future<DeliveryAddress?> showDeliveryAddressForm(
  BuildContext context, {
  DeliveryAddress? initial,
  bool firstAddress = false,
  AddressSearch? search,
  required Future<void> Function(DeliveryAddress) onSave,
}) => showDialog<DeliveryAddress>(
  context: context,
  barrierDismissible: false,
  builder: (_) => DeliveryAddressForm(
    initial: initial,
    firstAddress: firstAddress,
    search: search ?? searchPostcode,
    onSave: onSave,
  ),
);

class DeliveryAddressForm extends StatefulWidget {
  const DeliveryAddressForm({
    super.key,
    this.initial,
    this.firstAddress = false,
    required this.search,
    required this.onSave,
  });
  final DeliveryAddress? initial;
  final bool firstAddress;
  final AddressSearch search;
  final Future<void> Function(DeliveryAddress) onSave;
  @override
  State<DeliveryAddressForm> createState() => _DeliveryAddressFormState();
}

class _DeliveryAddressFormState extends State<DeliveryAddressForm> {
  late final _id =
      widget.initial?.id ?? 'address-${DateTime.now().microsecondsSinceEpoch}';
  late final _label = TextEditingController(
    text: widget.initial?.label ?? '우리 집',
  );
  late final _recipient = TextEditingController(
    text: widget.initial?.recipient,
  );
  late final _phone = TextEditingController(text: widget.initial?.phone);
  late final _zip = TextEditingController(text: widget.initial?.zip);
  late final _street = TextEditingController(text: widget.initial?.street);
  late final _detail = TextEditingController(text: widget.initial?.detail);
  late bool _default = widget.initial?.isDefault ?? widget.firstAddress;
  final _detailFocus = FocusNode();
  bool _saving = false, _searching = false;
  String? _error;
  List<TextEditingController> get _fields => [
    _label,
    _recipient,
    _phone,
    _zip,
    _street,
    _detail,
  ];
  bool get _complete =>
      _label.text.trim().isNotEmpty &&
      _recipient.text.trim().isNotEmpty &&
      RegExp(
        r'^0\d{8,10}$',
      ).hasMatch(_phone.text.replaceAll(RegExp(r'\D'), '')) &&
      RegExp(r'^\d{5}$').hasMatch(_zip.text) &&
      _street.text.trim().isNotEmpty;

  Future<void> _search() async {
    if (_searching || _saving) return;
    FocusScope.of(context).unfocus();
    setState(() => _searching = true);
    try {
      final result = await widget.search(context);
      if (result == null || !mounted) return;
      setState(() {
        _zip.text = result.zip;
        _street.text = result.street;
        _detail.clear();
        _error = null;
      });
      _detailFocus.requestFocus();
    } catch (_) {
      if (mounted) setState(() => _error = '주소 검색에 연결하지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _save() async {
    if (_saving || !_complete) return;
    final address = DeliveryAddress(
      id: _id,
      isDefault: _default,
      label: _label.text.trim(),
      recipient: _recipient.text.trim(),
      phone: _phone.text.trim(),
      zip: _zip.text.trim(),
      street: _street.text.trim(),
      detail: _detail.text.trim(),
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(address);
      if (mounted) Navigator.pop(context, address);
    } catch (_) {
      if (mounted) setState(() => _error = '배송지 정보를 저장하지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    String key,
    TextEditingController controller,
    String label, {
    TextInputType? keyboard,
    int? maxLength,
    List<TextInputFormatter>? formatters,
  }) => TextField(
    key: ValueKey('address-$key'),
    controller: controller,
    enabled: !_saving,
    focusNode: key == 'detail' ? _detailFocus : null,
    keyboardType: keyboard,
    maxLength: maxLength,
    inputFormatters: formatters,
    decoration: InputDecoration(labelText: label, counterText: ''),
    onChanged: (_) => setState(() {}),
  );

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    _detailFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: BogleDialog(
      title: widget.initial == null ? '새 배송지' : '배송지 수정',
      icon: Icons.location_on_outlined,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          key: const ValueKey('address-save'),
          onPressed: _complete && !_saving && !_searching ? _save : null,
          child: Text(_saving ? '저장 중…' : '저장'),
        ),
      ],
      child: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field('label', _label, '배송지 이름', maxLength: 12),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _field(
                      'recipient',
                      _recipient,
                      '받는 분',
                      maxLength: 30,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field(
                      'phone',
                      _phone,
                      '연락처',
                      keyboard: TextInputType.phone,
                      maxLength: 13,
                      formatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                key: const ValueKey('address-search'),
                onPressed: _saving || _searching ? null : _search,
                icon: const Icon(Icons.search_rounded),
                label: Text(_searching ? '주소 검색 중…' : '주소 검색'),
              ),
              const SizedBox(height: 12),
              _field(
                'zip',
                _zip,
                '우편번호',
                keyboard: TextInputType.number,
                maxLength: 5,
                formatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 12),
              _field('street', _street, '기본주소', maxLength: 300),
              const SizedBox(height: 12),
              _field('detail', _detail, '상세주소 (동·호수 등)', maxLength: 100),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('기본 배송지로 설정'),
                value: _default,
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _default = v ?? false),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(color: BogleColors.blueStrong),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
