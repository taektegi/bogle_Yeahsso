part of '../archive_screen.dart';

/// Asks before a friend leaves for good, showing who it is.
class _GoodbyeDialog extends StatelessWidget {
  const _GoodbyeDialog({required this.friend});
  final CharacterFriend friend;
  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: SizedBox(
      height: 96,
      child: FriendArtwork(assetPath: friend.assetPath),
    ),
    title: Text('${particle(friend.name, '과', '와')} 작별할까요?'),
    content: Text('${friend.name}의 집도 함께 사라져요.', textAlign: TextAlign.center),
    actionsAlignment: MainAxisAlignment.center,
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('그대로 두기'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE5484D)),
        child: const Text('작별하기'),
      ),
    ],
  );
}

/// Rename a friend, or change how it sees itself and how it talks.
class _EditFriendDialog extends StatefulWidget {
  const _EditFriendDialog({required this.friend});
  final CharacterFriend friend;
  @override
  State<_EditFriendDialog> createState() => _EditFriendDialogState();
}

class _EditFriendDialogState extends State<_EditFriendDialog> {
  late final _name = TextEditingController(text: widget.friend.name);
  late final _personality = TextEditingController(
    text: widget.friend.personality,
  );
  late final _introduction = TextEditingController(
    text: widget.friend.displayIntroduction,
  );
  late String _speech = widget.friend.speechStyle;

  @override
  void dispose() {
    _name.dispose();
    _personality.dispose();
    _introduction.dispose();
    super.dispose();
  }

  /// Reads the fields when pressed, not when the button was last drawn.
  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(
      context,
      widget.friend.copyWith(
        name: name,
        personality: _personality.text.trim(),
        introduction: _introduction.text.trim(),
        speechStyle: _speech,
      ),
    );
  }

  Widget _field({
    required String label,
    required Key fieldKey,
    required TextEditingController controller,
    required int limit,
    int minLines = 1,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ExcludeSemantics(child: Text(label, style: _labelStyle)),
      const SizedBox(height: 10),
      Semantics(
        label: label,
        child: TextField(
          key: fieldKey,
          controller: controller,
          maxLength: limit,
          minLines: minLines,
          maxLines: maxLines,
          onChanged: onChanged,
          style: const TextStyle(
            fontFamily: bogleUiFont,
            fontSize: 17,
            height: 1.5,
            color: BogleColors.text,
          ),
          cursorColor: BogleColors.logo,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            counterStyle: const TextStyle(
              fontFamily: bogleUiFont,
              fontSize: 12,
              color: BogleColors.muted,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: BogleColors.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: BogleColors.logo, width: 2),
            ),
          ),
        ),
      ),
    ],
  );

  static const _labelStyle = TextStyle(
    fontFamily: bogleDisplayFont,
    fontSize: 20,
    height: 1.3,
    color: BogleColors.text,
  );

  @override
  Widget build(BuildContext context) {
    final name = _name.text.trim();
    final fields = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field(
          label: '이름',
          fieldKey: const ValueKey('edit-name'),
          controller: _name,
          limit: 12,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 18),
        _field(
          label: '친구 소개',
          fieldKey: const ValueKey('edit-introduction'),
          controller: _introduction,
          limit: 70,
          minLines: 2,
          maxLines: 3,
        ),
        const SizedBox(height: 18),
        _field(
          label: '성격',
          fieldKey: const ValueKey('edit-personality'),
          controller: _personality,
          limit: 30,
        ),
      ],
    );
    final speech = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('말투', style: _labelStyle),
        const SizedBox(height: 12),
        if (SpeechProfile.tryParse(widget.friend.speechStyle) == null &&
            _speech != widget.friend.speechStyle)
          TextButton(
            onPressed: () =>
                setState(() => _speech = widget.friend.speechStyle),
            child: const Text(
              '기존 말투로 돌아가기',
              style: TextStyle(fontFamily: bogleUiFont, fontSize: 14),
            ),
          ),
        SpeechStylePicker(
          value: _speech,
          onChanged: (value) => setState(() => _speech = value),
        ),
      ],
    );
    return BogleDialogFrame(
      key: const ValueKey('edit-friend-dialog'),
      width: 820,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BogleDialogHeader(title: '친구 정보 수정', closeLabel: '수정 닫기'),
          Flexible(
            child: Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
                child: LayoutBuilder(
                  builder: (context, box) {
                    if (box.maxWidth >= 700 &&
                        MediaQuery.textScalerOf(context).scale(1) <= 1.3) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 4, child: fields),
                          const SizedBox(width: 32),
                          Expanded(flex: 5, child: speech),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [fields, const SizedBox(height: 24), speech],
                    );
                  },
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      foregroundColor: BogleColors.text,
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: BogleColors.line),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: bogleDisplayFont,
                        fontSize: 20,
                      ),
                    ),
                    child: const Text('취소'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: name.isEmpty ? null : _save,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      backgroundColor: BogleColors.logo,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: BogleColors.blueSoft,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: bogleDisplayFont,
                        fontSize: 20,
                      ),
                    ),
                    child: const Text('저장'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
