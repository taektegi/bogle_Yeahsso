part of '../archive_screen.dart';

/// Figma card (243:1612): a 268 × 468 white frame (radius 6, a soft 15 %
/// shadow) round the friend's colour (radius 2). Two cream circles float at
/// the top behind the name (32 pt 양진체), the introduction sits under it
/// in 12 pt, the drawing below, and the trash can and brush in the bottom
/// corners. Everything is measured in Figma points times the card's scale.
class _FriendHouseCard extends StatelessWidget {
  const _FriendHouseCard({
    super.key,
    required this.friend,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    this.hero = false,
  });
  final CharacterFriend friend;
  final bool hero;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  static const aspect = 268 / 468;

  /// The corner actions' shared centre line above the colour's bottom
  /// edge: between Figma's trash can (40) and brush (37), so they line up.
  static const _actionsUp = 38.5;

  /// Figma's pale-card icon colour (on 네모린's yellow).
  static const _pale = Color(0xFFBDCFFF);

  @override
  Widget build(BuildContext context) => FutureBuilder<ArtLook?>(
    // One friend's card throughout: the middle card's key moves to the
    // next card as the carousel turns, and without this the next friend
    // would take over this one's colour and fade out of it.
    key: ValueKey(friend.id),
    // Read ahead by the archive; the colour depends on how the friend is
    // painted (see cardColorFor).
    future: artLookOf(friend.assetPath),
    initialData: measuredArtLook(friend.assetPath),
    builder: (context, look) => _layout(friendCardColor(friend, look.data)),
  );

  Widget _layout(Color colour) => LayoutBuilder(
    builder: (context, box) {
      final k = box.maxWidth / 268;
      // A 48 pt touch target centred on an icon at [centre].
      Widget action(Offset centre, Widget button) => Positioned(
        left: centre.dx - 24,
        top: centre.dy - 24,
        width: 48,
        height: 48,
        child: button,
      );
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: _card(k, colour)),
          // Edit and delete actions sit on top of the card as their own
          // buttons, so VoiceOver reaches them too.
          action(
            Offset(
              (10 + 20 + 24.6094 / 2) * k,
              box.maxHeight - (10 + _actionsUp) * k,
            ),
            _CardAction(
              key: const ValueKey('archive-card-delete'),
              label: '${friend.name} 삭제',
              asset: 'assets/figma/archive_trash.svg',
              size: Size(24.6094 * k, 28.2324 * k),
              color: _actionColor(colour),
              onTap: onDelete,
            ),
          ),
          action(
            Offset(
              box.maxWidth - (10 + 11 + 19 / 2) * k,
              box.maxHeight - (10 + _actionsUp) * k,
            ),
            _CardAction(
              key: const ValueKey('archive-card-edit'),
              label: '${friend.name} 편집',
              asset: 'assets/figma/archive_brush.svg',
              size: Size(19 * k, 32 * k),
              color: _actionColor(colour),
              onTap: onEdit,
            ),
          ),
        ],
      );
    },
  );

  Color _actionColor(Color card) =>
      card.computeLuminance() > .75 ? _pale : Colors.white;

  Widget _card(double k, Color colour) => Semantics(
    button: true,
    label: '${friend.name}, ${friend.displayIntroduction}',
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(10 * k),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6 * k),
          boxShadow: figmaShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2 * k),
          // The friend's colour, unless the friend would melt into it
          // (see cardColorFor); eased in if the drawing is read late.
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: colour),
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            builder: (context, colour, layers) =>
                ColoredBox(color: colour!, child: layers),
            // Every layer spans the whole colour: a loose child would shrink
            // to its widest line and sit at the left, so a friend with a
            // short introduction would lean left.
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Figma "Group 1261155789", behind the name.
                Positioned(
                  left: 55 * k,
                  top: 7 * k,
                  child: SvgPicture.asset(
                    'assets/figma/archive_card_circles.svg',
                    key: const ValueKey('archive-card-circles'),
                    width: 145 * k,
                    height: 49 * k,
                    excludeFromSemantics: true,
                  ),
                ),
                Column(
                  children: [
                    SizedBox(height: 12 * k),
                    // A long name shrinks to fit within the card's frame.
                    SizedBox(
                      height: 40 * k,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16 * k),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            friend.name,
                            maxLines: 1,
                            style: TextStyle(
                              fontFamily: bogleDisplayFont,
                              fontSize: 32 * k,
                              height: 40 / 32,
                              letterSpacing: -0.96 * k,
                              color: BogleColors.text,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 20 * k),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16 * k),
                      child: Text(
                        friend.displayIntroduction,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: bogleDisplayFont,
                          fontSize: 12 * k,
                          height: 20 / 12,
                          letterSpacing: -0.36 * k,
                          color: BogleColors.text,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(17 * k, 18 * k, 17 * k, 0),
                        // Sized and centred by how the friend looks, not by
                        // its picture's box (see cardFigureRect).
                        child: CardFigure(
                          assetPath: friend.assetPath,
                          child: HeroMode(
                            enabled: hero,
                            child: friendHero(
                              id: friend.id,
                              assetPath: friend.assetPath,
                              standing: false,
                              child: FriendArtwork(
                                assetPath: friend.assetPath,
                                semanticsLabel: friend.name,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 63 * k),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// The card's corner actions, drawn as in the Figma card (243:1612): an
/// outlined trash can and a brush, in white (or pale blue on a pale card).
class _CardAction extends StatelessWidget {
  const _CardAction({
    super.key,
    required this.label,
    required this.asset,
    required this.size,
    required this.color,
    required this.onTap,
  });
  final String label;
  final String asset;
  final Size size;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onTap,
    padding: EdgeInsets.zero,
    style: IconButton.styleFrom(
      minimumSize: const Size(48, 48),
      tapTargetSize: MaterialTapTargetSize.padded,
    ),
    icon: SvgPicture.asset(
      asset,
      width: size.width,
      height: size.height,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    ),
  );
}
