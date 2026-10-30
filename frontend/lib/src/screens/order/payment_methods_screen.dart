import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/order_catalog.dart';
import '../../data/order_repository.dart';
import '../../theme/bogle_theme.dart';
import '../../widgets/bogle_dialog.dart';
import 'management_widgets.dart';

class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({
    super.key,
    required this.repository,
    this.selecting = false,
    this.selectedId,
  });
  final OrderRepository repository;
  final bool selecting;
  final String? selectedId;
  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  List<SavedPaymentMethod> _methods = [];
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final methods = await widget.repository.fetchPaymentMethods();
      if (mounted) {
        setState(() {
          _methods = List.of(methods)
            ..sort(
              (a, b) => (b.isDefault ? 1 : 0).compareTo(a.isDefault ? 1 : 0),
            );
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '결제 수단을 불러오지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([SavedPaymentMethod? method]) async {
    final saved = await showDialog<SavedPaymentMethod>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PaymentMethodForm(
        initial: method,
        firstMethod: _methods.isEmpty,
        onSave: widget.repository.savePaymentMethod,
      ),
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
      if (mounted) setState(() => _error = '결제 수단을 저장하지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(SavedPaymentMethod method) async {
    if (await confirmRemoval(
      context,
      '결제 수단을 삭제할까요?',
      '${method.nickname}을 목록에서 삭제해요. 기존 주문 내역은 유지돼요.',
    )) {
      await _act(() => widget.repository.deletePaymentMethod(method.id));
    }
  }

  @override
  Widget build(BuildContext context) => ManagementPage(
    title: '결제 수단 관리',
    addLabel: '결제 수단 추가',
    onAdd: () => _edit(),
    busy: _busy,
    error: _error,
    onRetry: _load,
    children: [
      if (!_busy && _methods.isEmpty && _error == null)
        const ManagementCard(
          child: Text('자주 사용하는 결제 수단을 등록해 주세요.\n주문할 때 등록한 수단을 바로 선택할 수 있어요.'),
        ),
      for (final method in _methods)
        ManagementCard(
          key: ValueKey('saved-payment-${method.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.account_balance_wallet_outlined,
                    color: BogleColors.logo,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      method.nickname,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (method.isDefault) const DefaultLabel(text: '기본 결제 수단'),
                ],
              ),
              const SizedBox(height: 12),
              Text(method.kind.label),
              const SizedBox(height: 6),
              Text(method.summary),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (widget.selecting)
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => Navigator.pop(context, method),
                      icon: Icon(
                        widget.selectedId == method.id
                            ? Icons.check_rounded
                            : Icons.credit_card_rounded,
                      ),
                      label: const Text('이 수단으로 선택'),
                    ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _edit(method),
                    child: const Text('수정'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _delete(method),
                    child: const Text('삭제'),
                  ),
                  if (!method.isDefault)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _act(
                              () => widget.repository.setDefaultPaymentMethod(
                                method.id,
                              ),
                            ),
                      child: const Text('기본 결제 수단으로 설정'),
                    ),
                ],
              ),
            ],
          ),
        ),
    ],
  );
}

class PaymentMethodForm extends StatefulWidget {
  const PaymentMethodForm({
    super.key,
    this.initial,
    this.firstMethod = false,
    required this.onSave,
  });
  final SavedPaymentMethod? initial;
  final bool firstMethod;
  final Future<void> Function(SavedPaymentMethod) onSave;
  @override
  State<PaymentMethodForm> createState() => _PaymentMethodFormState();
}

class _PaymentMethodFormState extends State<PaymentMethodForm> {
  static const _providers = {
    PaymentMethod.easyPay: ['카카오페이', '네이버페이', '토스페이', '페이코'],
    PaymentMethod.card: [
      '신한카드',
      'KB국민카드',
      '현대카드',
      '삼성카드',
      '롯데카드',
      '하나카드',
      '우리카드',
      'NH농협카드',
      'BC카드',
      '기타 카드',
    ],
    PaymentMethod.transfer: [
      '국민은행',
      '신한은행',
      '우리은행',
      '하나은행',
      '농협은행',
      '카카오뱅크',
      '토스뱅크',
      '기업은행',
      '기타 은행',
    ],
  };
  late final _id =
      widget.initial?.id ?? 'payment-${DateTime.now().microsecondsSinceEpoch}';
  late PaymentMethod _kind = widget.initial?.kind ?? PaymentMethod.card;
  late String _provider = widget.initial?.provider ?? _providers[_kind]!.first;
  late final _name = TextEditingController(
    text: widget.initial?.nickname ?? '내 카드',
  );
  late final _last4 = TextEditingController(text: widget.initial?.last4);
  late bool _default = widget.initial?.isDefault ?? widget.firstMethod;
  bool _saving = false;
  String? _error;
  bool get _complete =>
      _name.text.trim().isNotEmpty &&
      (_kind == PaymentMethod.easyPay ||
          RegExp(r'^\d{4}$').hasMatch(_last4.text));
  @override
  void dispose() {
    _name.dispose();
    _last4.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_complete) return;
    final method = SavedPaymentMethod(
      id: _id,
      kind: _kind,
      provider: _provider,
      nickname: _name.text.trim(),
      last4: _kind == PaymentMethod.easyPay ? '' : _last4.text,
      isDefault: _default,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(method);
      if (mounted) Navigator.pop(context, method);
    } catch (_) {
      if (mounted) setState(() => _error = '결제 수단을 저장하지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: BogleDialog(
      title: widget.initial == null ? '결제 수단 추가' : '결제 수단 수정',
      icon: Icons.account_balance_wallet_outlined,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          key: const ValueKey('payment-method-save'),
          onPressed: _complete && !_saving ? _save : null,
          child: Text(_saving ? '저장 중…' : '저장'),
        ),
      ],
      child: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<PaymentMethod>(
                key: const ValueKey('payment-kind'),
                initialValue: _kind,
                decoration: const InputDecoration(labelText: '결제 방식'),
                items: [
                  for (final kind in PaymentMethod.values)
                    DropdownMenuItem(value: kind, child: Text(kind.label)),
                ],
                onChanged: _saving
                    ? null
                    : (kind) {
                        if (kind == null) return;
                        setState(() {
                          _kind = kind;
                          _provider = _providers[kind]!.first;
                          _last4.clear();
                          _name.text = switch (kind) {
                            PaymentMethod.card => '내 카드',
                            PaymentMethod.easyPay => '내 간편결제',
                            PaymentMethod.transfer => '내 계좌',
                          };
                        });
                      },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey('payment-provider-${_kind.name}'),
                initialValue: _provider,
                decoration: const InputDecoration(labelText: '카드사 · 서비스 · 은행'),
                items: [
                  for (final provider in _providers[_kind]!)
                    DropdownMenuItem(value: provider, child: Text(provider)),
                ],
                onChanged: _saving
                    ? null
                    : (provider) =>
                          setState(() => _provider = provider ?? _provider),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('payment-nickname'),
                controller: _name,
                enabled: !_saving,
                maxLength: 20,
                decoration: const InputDecoration(
                  labelText: '이름',
                  counterText: '',
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_kind != PaymentMethod.easyPay) ...[
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('payment-last4'),
                  controller: _last4,
                  enabled: !_saving,
                  maxLength: 4,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: _kind == PaymentMethod.card
                        ? '카드번호 뒤 4자리'
                        : '계좌번호 뒤 4자리',
                    counterText: '',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('기본 결제 수단으로 설정'),
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
