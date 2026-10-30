part of '../house_widgets.dart';

// A friend as a silhouette (the invite tile) and its drawing cropped to what is
// drawn.

/// A friend as a flat silhouette in [color], cropped to what is drawn and
/// fitted into [size]: the invitation tile shows whose house it is
/// (Figma 621:2129). 뭉글이's comes from Figma as drawn; others are made from
/// their artwork's outline, soft glows left out, wherever the artwork comes
/// from (asset, file or URL). Art with no outline to take — a photographed
/// drawing, a picture with its own background, or one that can't be read —
/// gets 뭉글이's, so the tile is never blank.
class FriendSilhouette extends StatelessWidget {
  const FriendSilhouette({
    super.key,
    required this.assetPath,
    required this.size,
    this.color = defaultColor,
  });
  final String assetPath;
  final Size size;
  final Color color;

  static const defaultColor = Color(0xFF2ACB86);

  /// Silhouettes drawn in Figma, by the artwork they are of.
  static const _drawn = {
    'assets/figma/character_card.svg': 'assets/figma/house_invite.svg',
  };
  static const fallback = 'assets/figma/house_invite.svg';

  /// Paints everything in [color]; alpha is pushed through a threshold at
  /// half so faint glows and shadows drop out and the edge stays crisp.
  ColorFilter get _fill => ColorFilter.matrix([
    0, 0, 0, 0, (color.r * 255).roundToDouble(), //
    0, 0, 0, 0, (color.g * 255).roundToDouble(),
    0, 0, 0, 0, (color.b * 255).roundToDouble(),
    0, 0, 0, 8, -1020,
  ]);

  Widget _figma(String svg) => SvgPicture.asset(
    svg,
    key: ValueKey('silhouette-$svg'),
    width: size.width,
    height: size.height,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    excludeFromSemantics: true,
  );

  @override
  Widget build(BuildContext context) {
    final drawn =
        _drawn[assetPath] ?? (isPhotographedArt(assetPath) ? fallback : null);
    if (drawn != null) return _figma(drawn);
    return SizedBox.fromSize(
      size: size,
      child: FutureBuilder(
        future: artLookOf(assetPath),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox();
          }
          final look = snap.data;
          if (look == null || !look.clearGround) return _figma(fallback);
          return KeyedSubtree(
            key: ValueKey('silhouette-$assetPath'),
            child: _Cropped(
              look: look,
              child: ColorFiltered(
                colorFilter: _fill,
                child: ExcludeSemantics(
                  child: FriendArtwork(assetPath: assetPath, fit: BoxFit.fill),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A friend's artwork with its empty margin cut away, so the drawing itself
/// fills the box (contained, centred), whatever canvas it was drawn on.
/// Used wherever a design gives the friend a slot of its own, like the order
/// portrait. Art with a background of its own, or not yet measured, shows
/// whole.
class TrimmedFriendArtwork extends StatelessWidget {
  const TrimmedFriendArtwork({
    super.key,
    required this.assetPath,
    this.semanticsLabel,
  });
  final String assetPath;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final whole = FriendArtwork(
      assetPath: assetPath,
      semanticsLabel: semanticsLabel,
    );
    if (isPhotographedArt(assetPath)) return whole;
    return FutureBuilder(
      future: artLookOf(assetPath),
      builder: (context, snap) {
        final look = snap.data;
        if (look == null || !look.clearGround) return whole;
        return _Cropped(
          look: look,
          child: FriendArtwork(
            assetPath: assetPath,
            semanticsLabel: semanticsLabel,
            fit: BoxFit.fill,
          ),
        );
      },
    );
  }
}

/// [child] (the artwork at its own size) cut to the part [look] says is
/// drawn, and that part fitted into the space given.
class _Cropped extends StatelessWidget {
  const _Cropped({required this.look, required this.child});
  final ArtLook look;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final natural = look.natural, drawn = look.drawn;
    return FittedBox(
      child: SizedBox(
        width: natural.width * drawn.width,
        height: natural.height * drawn.height,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: natural.width,
            maxWidth: natural.width,
            minHeight: natural.height,
            maxHeight: natural.height,
            child: Transform.translate(
              offset: Offset(
                -drawn.left * natural.width,
                -drawn.top * natural.height,
              ),
              child: SizedBox.fromSize(size: natural, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
