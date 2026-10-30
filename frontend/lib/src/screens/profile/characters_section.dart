import 'package:flutter/material.dart';

import '../../models/character_friend.dart';
import '../../theme/bogle_theme.dart';
import 'profile_widgets.dart';

const _tile = 136.0;
const _gap = 22.0;

/// "내 친구들" (마이페이지 design): each friend on a big periwinkle tile with
/// its name under it in the display font, a grey tile at the end to make a
/// new one, and a round button to see more.
class CharactersSection extends StatefulWidget {
  const CharactersSection({
    super.key,
    required this.friends,
    required this.onOpen,
    required this.onCreate,
  });
  final List<CharacterFriend> friends;
  final ValueChanged<CharacterFriend> onOpen;
  final VoidCallback onCreate;

  @override
  State<CharactersSection> createState() => _CharactersSectionState();
}

class _CharactersSectionState extends State<CharactersSection> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _next() => _scroll.animateTo(
    (_scroll.offset + (_tile + _gap) * 3).clamp(
      0,
      _scroll.position.maxScrollExtent,
    ),
    duration: Duration(
      milliseconds: MediaQuery.disableAnimationsOf(context) ? 1 : 320,
    ),
    curve: Curves.easeOutCubic,
  );

  @override
  Widget build(BuildContext context) => ProfileSection(
    title: '내 친구들',
    trailing: _MakeButton(onTap: widget.onCreate),
    child: ProfileCard(
      padding: const EdgeInsets.fromLTRB(22, 20, 16, 16),
      child: SizedBox(
        // Tile + gap + name line, growing with the reader's text size.
        height: _tile + 12 + MediaQuery.textScalerOf(context).scale(21) * 1.3,
        child: Row(
          children: [
            Expanded(
              child: ListView.separated(
                key: const ValueKey('profile-characters'),
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                itemCount: widget.friends.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: _gap),
                itemBuilder: (context, i) => i == widget.friends.length
                    ? _NewTile(onTap: widget.onCreate)
                    : _CharacterTile(
                        friend: widget.friends[i],
                        onTap: () => widget.onOpen(widget.friends[i]),
                      ),
              ),
            ),
            ListenableBuilder(
              listenable: _scroll,
              builder: (context, _) {
                final more =
                    _scroll.hasClients &&
                    _scroll.position.hasContentDimensions &&
                    _scroll.offset < _scroll.position.maxScrollExtent - 1;
                return AnimatedOpacity(
                  opacity: more ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 32),
                    child: _RoundNext(
                      tooltip: '더 보기',
                      onTap: more ? _next : null,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// The design's filled pill with a white "+" disc: "캐릭터 만들러 가기".
class _MakeButton extends StatelessWidget {
  const _MakeButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '캐릭터 만들러 가기',
    excludeSemantics: true,
    child: Material(
      color: BogleColors.logo,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 20, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add_rounded,
                  size: 24,
                  color: BogleColors.logo,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                '캐릭터 만들러 가기',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The design's white disc with a chevron, to scroll on.
class _RoundNext extends StatelessWidget {
  const _RoundNext({required this.tooltip, required this.onTap});
  final String tooltip;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      shadowColor: const Color(0x223A4A8C),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox.square(
          dimension: 54,
          child: Icon(
            Icons.chevron_right_rounded,
            size: 30,
            color: BogleColors.logo,
          ),
        ),
      ),
    ),
  );
}

/// The design's grey tile after the friends: room for a new one.
class _NewTile extends StatelessWidget {
  const _NewTile({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '새로운 캐릭터 만들기',
    excludeSemantics: true,
    child: Column(
      children: [
        Material(
          color: const Color(0xFFE3E3DB),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: const SizedBox.square(
              dimension: _tile,
              child: Icon(Icons.add_rounded, size: 44, color: Colors.white),
            ),
          ),
        ),
      ],
    ),
  );
}

class _CharacterTile extends StatelessWidget {
  const _CharacterTile({required this.friend, required this.onTap});
  final CharacterFriend friend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: _tile,
    child: Column(
      children: [
        Semantics(
          container: true,
          button: true,
          label: '${friend.name} 만나기',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: onTap,
            child: ArtTile(
              asset: friend.thumbnail,
              size: _tile,
              radius: 10,
              color: ProfileStyle.tile,
            ),
          ),
        ),
        const SizedBox(height: 12),
        ExcludeSemantics(
          child: Text(
            friend.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ProfileStyle.displayTitle,
          ),
        ),
      ],
    ),
  );
}
