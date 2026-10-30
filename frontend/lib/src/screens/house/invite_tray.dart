import 'package:flutter/material.dart';

import '../../models/character_friend.dart';
import '../../theme/bogle_theme.dart';
import '../../widgets/bogle_widgets.dart';

/// Above the action bar, like the snack tray: the other friends, one of
/// whom can be invited over.
class InviteTray extends StatelessWidget {
  const InviteTray({
    super.key,
    required this.friends,
    required this.onInvite,
    required this.onClose,
  });

  /// Everyone but the host.
  final List<CharacterFriend> friends;
  final ValueChanged<CharacterFriend> onInvite;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 14, 10, 14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .95),
      borderRadius: BorderRadius.circular(28),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1A3A4A8C),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          friends.isEmpty ? '초대할 친구가 아직 없어요' : '누구를 초대할까요?',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: BogleColors.muted,
          ),
        ),
        const SizedBox(width: 14),
        // Many friends scroll sideways instead of overflowing.
        Flexible(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final friend in friends)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _Guest(
                      friend: friend,
                      onTap: () => onInvite(friend),
                    ),
                  ),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: '초대 닫기',
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded, color: BogleColors.muted),
        ),
      ],
    ),
  );
}

class _Guest extends StatelessWidget {
  const _Guest({required this.friend, required this.onTap});
  final CharacterFriend friend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Color(friend.accentHex);
    return Semantics(
      button: true,
      label: '${friend.name} 초대하기',
      excludeSemantics: true,
      child: Material(
        color: Color.lerp(accent, Colors.white, .72),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: SizedBox(
            width: 92,
            height: 96,
            child: Column(
              children: [
                const SizedBox(height: 8),
                SizedBox(
                  width: 72,
                  height: 56,
                  child: FriendArtwork(assetPath: friend.thumbnail),
                ),
                const SizedBox(height: 6),
                Text(
                  friend.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: BogleColors.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
