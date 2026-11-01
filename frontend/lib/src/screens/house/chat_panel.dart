import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/chat_service.dart';
import '../../data/friend_talk.dart';
import '../../data/korean.dart';
import '../../models/character_friend.dart';
import '../../theme/bogle_theme.dart';
import '../../widgets/bogle_widgets.dart';
import 'house_widgets.dart';
import 'chat_typography.dart';

/// The conversation, beside the friend in its room: every line said so
/// far, from earlier visits too, scrolls in one tall card, newest at the
/// bottom like any messenger. Quick replies come first: tapping is easier
/// than typing for young children; the text field is there for those who
/// can.
///
/// The history uses Pretendard for both sides, with white friend balloons
/// and logo-blue child balloons on the cream of the room's wall. While the
/// friend thinks, three dots bob in a balloon of its own and sending waits
/// for its answer. The field grows to four lines instead of scrolling
/// sideways, and a tap anywhere in the panel (a quick reply, send) keeps
/// the keyboard up; a tap outside puts it away. The round × at the top
/// closes the conversation.
class ChatPanel extends StatefulWidget {
  const ChatPanel({
    super.key,
    required this.friend,
    required this.lines,
    required this.onSend,
    required this.onClose,
    required this.enabled,
    this.thinking = false,
    this.speakers = const [],
  });
  final CharacterFriend friend;
  final List<ChatLine> lines;
  final List<CharacterFriend?> speakers;
  final void Function(String text, TalkTopic? topic) onSend;
  final VoidCallback onClose;

  /// False while the friend is asleep.
  final bool enabled;

  /// The friend is working out its answer.
  final bool thinking;

  /// The longest line a child can send, in letters as they see them.
  static const maxLength = 200;

  /// The figma "미선택버튼" grey: send with nothing to send.
  static const _idle = Color(0xFFDAD9CD);
  static const _chip = Color(0xFFE6EBFF);

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _field = TextEditingController();
  final _focus = FocusNode(debugLabel: 'house-chat-field');

  @override
  void initState() {
    super.initState();
    _field.addListener(_changed);
    _focus.addListener(_changed);
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  bool get _canTalk => widget.enabled && !widget.thinking;
  bool get _canSend => _canTalk && _field.text.trim().isNotEmpty;

  void _submit() {
    final text = _field.text.trim();
    if (text.isEmpty || !_canTalk) return;
    widget.onSend(text, null);
    _field.clear();
    // Keep typing: the keyboard stays for the next line.
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final friend = widget.friend;
    final accent = Color(friend.accentHex);
    return TextFieldTapRegion(
      child: Semantics(
        container: true,
        label: '${particle(friend.name, '과', '와')} 나누는 이야기',
        child: Container(
          decoration: houseCard(28),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            // Short (above the keyboard): a slimmer header, so the
            // conversation keeps its room.
            builder: (context, box) => Column(
              children: [
                _header(friend, accent, compact: box.maxHeight < 440),
                Expanded(
                  child: ColoredBox(
                    color: BogleColors.cream,
                    child: _messages(friend, accent, box.maxWidth),
                  ),
                ),
                // Writing a line of its own, the child doesn't need them.
                if (widget.enabled && _field.text.isEmpty) _quickReplies(),
                _composer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(
    CharacterFriend friend,
    Color accent, {
    required bool compact,
  }) => Container(
    padding: EdgeInsets.fromLTRB(18, compact ? 8 : 14, 14, compact ? 8 : 14),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xFFF0EEDF))),
    ),
    child: Row(
      children: [
        _Avatar(friend: friend, accent: accent, size: compact ? 40 : 52),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                friend.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: bogleDisplayFont,
                  fontSize: compact ? 21 : 24,
                  height: 1.2,
                  letterSpacing: -.6,
                  color: BogleColors.text,
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 2),
                Text(
                  !widget.enabled
                      ? '쿨쿨 자는 중이에요'
                      : widget.thinking
                      ? '대답을 생각하고 있어요'
                      : '${particle(friend.name, '과', '와')} 이야기하는 중',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HouseChatType.meta,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          key: const ValueKey('house-chat-return'),
          tooltip: '대화 닫기',
          onPressed: widget.onClose,
          style: IconButton.styleFrom(
            backgroundColor: BogleColors.blueSoft,
            foregroundColor: BogleColors.text,
            minimumSize: const Size.square(52),
          ),
          icon: const Icon(Icons.close_rounded, size: 28),
        ),
      ],
    ),
  );

  Widget _messages(CharacterFriend friend, Color accent, double width) {
    // Balloons take up to three quarters of the card, as in a messenger.
    final balloon = math.max(220.0, width * .74);
    final lines = widget.lines.reversed.toList();
    final thinking = widget.thinking && widget.enabled;
    final count = lines.length + (thinking ? 1 : 0);
    return ListView.builder(
      key: const ValueKey('house-chat'),
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      itemCount: count,
      itemBuilder: (context, i) {
        if (thinking && i == 0) {
          return _FriendRow(
            friend: friend,
            accent: accent,
            showAvatar: true,
            child: const _ThinkingDots(key: ValueKey('house-chat-thinking')),
          );
        }
        final at = thinking ? i - 1 : i;
        final line = lines[at];
        CharacterFriend who(int reversedIndex) {
          final original = widget.lines.length - 1 - reversedIndex;
          return original < widget.speakers.length
              ? widget.speakers[original] ?? friend
              : friend;
        }

        final speaker = who(at);
        // Newer lines come first (the list runs bottom up).
        final newer = at == 0 ? null : lines[at - 1];
        final older = at + 1 < lines.length ? lines[at + 1] : null;
        final endsRun =
            newer == null ||
            newer.mine != line.mine ||
            (!line.mine && who(at - 1).id != speaker.id);
        final startsRun =
            older == null ||
            older.mine != line.mine ||
            (!line.mine && who(at + 1).id != speaker.id);
        final gap = EdgeInsets.only(top: startsRun ? 10 : 4);
        if (line.mine) {
          return Padding(
            padding: gap,
            child: Align(
              alignment: Alignment.centerRight,
              child: _Balloon(
                text: line.text,
                mine: true,
                tail: endsRun,
                maxWidth: balloon,
              ),
            ),
          );
        }
        return Padding(
          padding: gap,
          child: _FriendRow(
            friend: speaker,
            accent: Color(speaker.accentHex),
            showAvatar: endsRun && !(thinking && at == 0),
            child: _Balloon(
              text: line.text,
              mine: false,
              tail: endsRun && !(thinking && at == 0),
              maxWidth: balloon,
            ),
          ),
        );
      },
    );
  }

  /// The quick replies, all in sight: they wrap onto a second line rather
  /// than hide off the side. They wait, greyed, while the friend thinks of
  /// its answer.
  Widget _quickReplies() => Container(
    key: const ValueKey('house-chat-quick-row'),
    width: double.infinity,
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
    child: Wrap(
      key: const ValueKey('house-chat-quick'),
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (topic, label) in quickTalks)
          ActionChip(
            label: Text(label),
            labelStyle: HouseChatType.quick,
            backgroundColor: ChatPanel._chip,
            disabledColor: const Color(0xFFF1F1EA),
            side: BorderSide.none,
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            labelPadding: const EdgeInsets.symmetric(horizontal: 8),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onPressed: _canTalk ? () => widget.onSend(label, topic) : null,
          ),
      ],
    ),
  );

  Widget _composer() {
    final focused = _focus.hasFocus;
    // Keyed so the field stays the same field (and keeps a half-typed
    // syllable) when the quick replies above it come and go.
    return Container(
      key: const ValueKey('house-chat-composer'),
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              decoration: BoxDecoration(
                color: widget.enabled
                    ? BogleColors.cream
                    : const Color(0xFFF4F3EA),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: focused ? BogleColors.logo : const Color(0xFFEDEBDA),
                  width: focused ? 2 : 1.5,
                ),
              ),
              child: TextField(
                key: const ValueKey('house-chat-field'),
                controller: _field,
                focusNode: _focus,
                enabled: widget.enabled,
                minLines: 1,
                maxLines: 4,
                maxLength: ChatPanel.maxLength,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submit(),
                onTapOutside: (_) => _focus.unfocus(),
                scrollPadding: EdgeInsets.zero,
                style: HouseChatType.input,
                decoration: InputDecoration(
                  hintText: !widget.enabled
                      ? '지금은 자고 있어요. 내일 또 이야기해요'
                      : widget.thinking
                      ? '친구가 생각하고 있어요…'
                      : '하고 싶은 말을 적어 봐요',
                  hintStyle: HouseChatType.hint,
                  counterText: '',
                  filled: false,
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.fromLTRB(18, 13, 14, 13),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: _canSend ? BogleColors.logo : ChatPanel._idle,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                key: const ValueKey('house-chat-send'),
                tooltip: '보내기',
                // Grey until there is something to send, but always
                // listening: [_submit] skips an empty field.
                onPressed: _canTalk ? _submit : null,
                color: Colors.white,
                disabledColor: Colors.white,
                icon: const Icon(Icons.arrow_upward_rounded, size: 28),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.friend,
    required this.accent,
    required this.size,
  });
  final CharacterFriend friend;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    padding: EdgeInsets.all(size * .12),
    decoration: BoxDecoration(
      color: Color.lerp(Colors.white, accent, .7),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2),
    ),
    child: FriendArtwork(assetPath: friend.thumbnail),
  );
}

/// The friend's side: its face beside the last balloon of a run, the
/// earlier ones lined up with it.
class _FriendRow extends StatelessWidget {
  const _FriendRow({
    required this.friend,
    required this.accent,
    required this.showAvatar,
    required this.child,
  });
  final CharacterFriend friend;
  final Color accent;
  final bool showAvatar;
  final Widget child;

  static const _avatar = 40.0;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      if (showAvatar)
        _Avatar(friend: friend, accent: accent, size: _avatar)
      else
        const SizedBox(width: _avatar),
      const SizedBox(width: 8),
      Flexible(child: child),
      // Room on the right so the friend's side reads as its own.
      const SizedBox(width: 28),
    ],
  );
}

class _Balloon extends StatelessWidget {
  const _Balloon({
    required this.text,
    required this.mine,
    required this.tail,
    required this.maxWidth,
  });
  final String text;
  final bool mine;
  final double maxWidth;

  /// The last of a run points at its speaker with a tucked corner.
  final bool tail;

  @override
  Widget build(BuildContext context) {
    const round = Radius.circular(22), tucked = Radius.circular(6);
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: mine ? BogleColors.logo : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: round,
          topRight: round,
          bottomLeft: !mine && tail ? tucked : round,
          bottomRight: mine && tail ? tucked : round,
        ),
        boxShadow: mine
            ? null
            : const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 6,
                  offset: Offset(0, 1),
                ),
              ],
      ),
      child: Text(
        keepWords(text),
        semanticsLabel: text,
        style: mine
            ? HouseChatType.message.copyWith(color: Colors.white)
            : HouseChatType.message,
      ),
    );
  }
}

/// Three dots bobbing in turn: the friend is thinking of its answer.
class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots({super.key});

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // With reduced motion the dots stay still.
    if (MediaQuery.disableAnimationsOf(context)) {
      _beat.stop();
    } else if (!_beat.isAnimating) {
      _beat.repeat();
    }
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: '생각하는 중',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomRight: Radius.circular(20),
            bottomLeft: Radius.circular(6),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 6,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: AnimatedBuilder(
          animation: _beat,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                  child: Transform.translate(
                    offset: Offset(
                      0,
                      still ? 0 : -4 * _bob(_beat.value - i * .16),
                    ),
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: BogleColors.logo,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Up and down once in the first half of the beat, then rest.
  static double _bob(double t) {
    final at = t % 1;
    return at < .5 ? math.sin(at * 2 * math.pi) : 0;
  }
}
