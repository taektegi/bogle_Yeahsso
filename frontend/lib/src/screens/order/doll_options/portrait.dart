part of '../doll_options.dart';

/// The left block: a gentle colour wash with the portrait on circular glass
/// and a line in 양진체 inside. With a [question] (the friend step) the ask
/// sits above the circle.
class _Portrait extends StatelessWidget {
  const _Portrait({
    super.key,
    required this.friend,
    required this.textScale,
    this.headline = '날 직접 만나 봐 !',
    this.question,
  });
  final CharacterFriend friend;
  final double textScale;
  final String headline;
  final String? question;

  @override
  Widget build(BuildContext context) {
    final circle = LayoutBuilder(
      builder: (context, box) {
        final diameter = math.min(box.maxWidth * 372 / 422, box.maxHeight * .8);
        return Center(
          child: SizedBox.square(
            dimension: diameter,
            child: CharacterPreviewSurface(
              friend: friend,
              child: Stack(
                children: [
                  Positioned(
                    top: diameter * .205,
                    left: diameter * .07,
                    right: diameter * .07,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        headline,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: bogleDisplayFont,
                          fontSize: 27.47 * textScale,
                          height: 1.1,
                          letterSpacing: -.82,
                          color: BogleColors.text,
                        ),
                      ),
                    ),
                  ),
                  // Figma 470:2957's slot in the 372 pt circle. Every friend,
                  // 뭉글이 included, is drawn from its own artwork exactly as
                  // in the house and the archive: no stand-in pictures made
                  // elsewhere (one rendered outside Flutter once gave 뭉글이 a
                  // white halo and a grey outline).
                  Positioned(
                    left: diameter * 26 / 372,
                    right: diameter * 26 / 372,
                    top: diameter * 142 / 372,
                    height: diameter * 155.25 / 372,
                    // The drawn part fills the slot, as Figma draws 뭉글이.
                    child: TrimmedFriendArtwork(
                      key: ValueKey('order-portrait-${friend.id}'),
                      assetPath: friend.assetPath,
                      semanticsLabel: '${friend.name} 인형 미리보기',
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    final question = this.question;
    return Container(
      key: const ValueKey('order-doll-preview'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(Color(friend.accentHex), BogleColors.cream, .70)!,
            Color.lerp(Color(friend.accentHex), Colors.white, .84)!,
            Color.lerp(Color(friend.accentHex), BogleColors.cream, .48)!,
          ],
          stops: const [0, .5, 1],
        ),
        borderRadius: BorderRadius.circular(24 * textScale),
        border: Border.all(color: Colors.white.withValues(alpha: .8)),
      ),
      child: question == null
          ? circle
          : Column(
              children: [
                SizedBox(height: 34 * textScale),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Semantics(
                      header: true,
                      child: Text(
                        question,
                        key: const ValueKey('order-pick-question'),
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: bogleDisplayFont,
                          fontSize: 26 * textScale,
                          height: 1.2,
                          letterSpacing: -.78,
                          color: BogleColors.text,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(child: circle),
              ],
            ),
    );
  }
}
