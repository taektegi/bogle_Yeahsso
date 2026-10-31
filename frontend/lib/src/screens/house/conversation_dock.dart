import 'package:flutter/material.dart';

import '../../data/friend_talk.dart';
import '../../theme/bogle_theme.dart';
import 'chat_typography.dart';
import '../../widgets/measured_size.dart';

/// 답은 방 안의 말풍선에, 입력과 지난 이야기는 작은 크림색 받침에 둔다.
class ConversationDock extends StatefulWidget {
  const ConversationDock({
    super.key,
    this.compact = false,
    required this.enabled,
    required this.thinking,
    required this.onSend,
    required this.onClose,
    required this.onHistory,
    this.onHeightChanged,
  });
  static const baseHeight = 218.0;
  static const preferredWidth = 760.0;
  final bool enabled, thinking;
  final bool compact;
  final void Function(String, TalkTopic?) onSend;
  final VoidCallback onClose, onHistory;
  final ValueChanged<double>? onHeightChanged;
  @override
  State<ConversationDock> createState() => _ConversationDockState();
}

class _ConversationDockState extends State<ConversationDock> {
  final _field = TextEditingController();
  final _focus = FocusNode();
  String? _sent;
  bool get _canSend => widget.enabled && !widget.thinking;
  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _field.text.trim();
    if (!_canSend || text.isEmpty) return;
    _submit(text, null);
    _field.clear();
    _focus.requestFocus();
  }

  void _submit(String text, TalkTopic? topic) {
    setState(() => _sent = text);
    widget.onSend(text, topic);
  }

  @override
  Widget build(BuildContext context) => TextFieldTapRegion(
    child: MeasuredSize(
      onSize: (size) => widget.onHeightChanged?.call(size.height),
      child: Material(
        color: BogleColors.cream,
        elevation: 3,
        shadowColor: BogleColors.logo.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: widget.compact
              ? const EdgeInsets.fromLTRB(12, 6, 12, 10)
              : const EdgeInsets.fromLTRB(20, 16, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.only(bottom: widget.compact ? 6 : 12),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('house-chat-return'),
                      onPressed: widget.onClose,
                      style: FilledButton.styleFrom(
                        backgroundColor: BogleColors.blueSoft,
                        foregroundColor: BogleColors.text,
                        minimumSize: const Size(0, 52),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        textStyle: HouseChatType.action,
                      ),
                      icon: const Icon(Icons.arrow_back_rounded, size: 24),
                      label: const Text('집으로 돌아가기'),
                    ),
                    TextButton.icon(
                      onPressed: widget.onHistory,
                      style: TextButton.styleFrom(
                        foregroundColor: BogleColors.muted,
                        minimumSize: const Size(0, 48),
                        textStyle: HouseChatType.action,
                      ),
                      icon: const Icon(Icons.history_rounded, size: 18),
                      label: const Text('이전 이야기'),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height:
                    (widget.compact ? 38.0 : 48.0) +
                    (MediaQuery.textScalerOf(context).scale(15) - 15).clamp(
                      0,
                      60,
                    ),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    if (widget.thinking && _sent != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        child: Text(
                          '나: $_sent',
                          maxLines: 1,
                          style: HouseChatType.meta,
                        ),
                      ),
                    if (!widget.thinking && _field.text.isEmpty)
                      for (final (topic, text) in quickTalks)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: ActionChip(
                            backgroundColor: Colors.white,
                            side: BorderSide.none,
                            label: Text(text, style: HouseChatType.quick),
                            onPressed: _canSend
                                ? () => _submit(text, topic)
                                : null,
                          ),
                        ),
                  ],
                ),
              ),
              SizedBox(height: widget.compact ? 0 : 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('house-chat-field'),
                      controller: _field,
                      focusNode: _focus,
                      enabled: widget.enabled,
                      style: HouseChatType.input,
                      maxLength: 200,
                      maxLines: 1,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _send(),
                      textInputAction: TextInputAction.send,
                      scrollPadding: EdgeInsets.zero,
                      onTapOutside: (_) => _focus.unfocus(),
                      decoration: InputDecoration(
                        counterText: '',
                        hintStyle: HouseChatType.hint,
                        filled: true,
                        fillColor: Colors.white,
                        hintText: !widget.enabled
                            ? '친구가 자고 있어요'
                            : widget.thinking
                            ? '친구가 생각하고 있어요…'
                            : '하고 싶은 말을 적어 봐요',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filled(
                    key: const ValueKey('house-chat-send'),
                    tooltip: '보내기',
                    onPressed: _canSend && _field.text.trim().isNotEmpty
                        ? _send
                        : null,
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
