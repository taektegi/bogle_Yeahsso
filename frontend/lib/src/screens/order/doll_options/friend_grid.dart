part of '../doll_options.dart';

/// Every friend as an option card, three to a row (22 pt apart, as the
/// size cards); a row grows to fill the space, and many rows scroll.
class _FriendGrid extends StatefulWidget {
  const _FriendGrid({
    required this.friends,
    required this.selected,
    required this.scale,
    required this.textScale,
    required this.onSelect,
  });
  final List<CharacterFriend> friends;
  final int selected;
  final double scale;
  final double textScale;
  final ValueChanged<int> onSelect;

  @override
  State<_FriendGrid> createState() => _FriendGridState();
}

class _FriendGridState extends State<_FriendGrid> {
  final _controller = ScrollController();
  final _metrics = ValueNotifier<ScrollMetrics?>(null);

  @override
  void dispose() {
    _controller.dispose();
    _metrics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      const columns = 3;
      final gap = 22 * widget.scale;
      final shadowInset = 4 * widget.scale;
      final width =
          (box.maxWidth - shadowInset * 2 - gap * (columns - 1)) / columns;
      final rows = (widget.friends.length / columns).ceil();
      final height =
          ((box.maxHeight - shadowInset * 2 - gap * (rows - 1)) / rows).clamp(
            width * .95,
            width * 1.7,
          );
      final fade = math.min(24 * widget.scale, box.maxHeight * .18);
      // Metrics notifications also cover the first layout and viewport resize.
      // Only the mask updates during a drag; the card widgets stay in place.
      return NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          if (notification.depth == 0) _metrics.value = notification.metrics;
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.depth == 0) _metrics.value = notification.metrics;
            return false;
          },
          child: ClipRect(
            child: RepaintBoundary(
              child: ValueListenableBuilder<ScrollMetrics?>(
                valueListenable: _metrics,
                builder: (context, metrics, child) {
                  // Reveal the first/last row fully at rest. Fade only towards
                  // content outside the viewport, gradually as it scrolls away.
                  final top = ((metrics?.extentBefore ?? 0) / fade).clamp(
                    0.0,
                    1.0,
                  );
                  final bottom = ((metrics?.extentAfter ?? 0) / fade).clamp(
                    0.0,
                    1.0,
                  );
                  return ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (rect) => LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 1 - top),
                        Colors.white,
                        Colors.white,
                        Colors.white.withValues(alpha: 1 - bottom),
                      ],
                      stops: [0, fade / rect.height, 1 - fade / rect.height, 1],
                    ).createShader(rect),
                    child: child,
                  );
                },
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(overscroll: false),
                  child: GridView.builder(
                    key: const ValueKey('order-friend-grid'),
                    controller: _controller,
                    primary: false,
                    // Shorter coast, firmer edge resistance and a damped return.
                    physics: const _FriendScrollPhysics(),
                    padding: EdgeInsets.all(shadowInset),
                    clipBehavior: Clip.hardEdge,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: gap,
                      crossAxisSpacing: gap,
                      childAspectRatio: width / height,
                    ),
                    itemCount: widget.friends.length,
                    itemBuilder: (context, i) => _FriendOption(
                      friend: widget.friends[i],
                      selected: i == widget.selected,
                      scale: widget.scale,
                      textScale: widget.textScale,
                      onTap: () => widget.onSelect(i),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Apply edge resistance to the part of the very first drag that crosses the
/// boundary too. Native bouncing otherwise moves that event in full, producing
/// a large blank gap on a quick pull or a coalesced touch event.
class _FriendScrollPhysics extends BouncingScrollPhysics {
  const _FriendScrollPhysics({super.parent})
    : super(decelerationRate: ScrollDecelerationRate.fast);

  @override
  _FriendScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _FriendScrollPhysics(parent: buildParent(ancestor));

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (position.outOfRange) {
      return super.applyPhysicsToUserOffset(position, offset);
    }
    final target = position.pixels - offset;
    final edge = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    return offset + (target - edge) * (1 - frictionFactor(0));
  }
}

/// A friend in the option cards' look (white, a thin blue edge, filled
/// blue once chosen): its drawing on its own colour, name and personality.
class _FriendOption extends StatelessWidget {
  const _FriendOption({
    required this.friend,
    required this.selected,
    required this.scale,
    required this.textScale,
    required this.onTap,
  });
  final CharacterFriend friend;
  final bool selected;
  final double scale;
  final double textScale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: friend.name,
    excludeSemantics: true,
    child: Material(
      color: selected ? BogleColors.logo : Colors.white,
      animationDuration: Duration(
        milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 180,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(3.49 * scale),
        side: BorderSide(color: BogleColors.logo, width: .6 * scale),
      ),
      elevation: .6,
      shadowColor: const Color(0x26000000),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('order-friend-${friend.id}'),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(10 * scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  padding: EdgeInsets.all(12 * scale),
                  decoration: BoxDecoration(
                    color: Color(
                      friend.id == 'mungle' ? 0xFFBDCFFF : friend.accentHex,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: FriendArtwork(assetPath: friend.thumbnail),
                ),
              ),
              SizedBox(height: 10 * scale),
              Text(
                friend.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17.45 * textScale,
                  fontWeight: FontWeight.w700,
                  height: 1.34,
                  color: selected ? Colors.white : BogleColors.text,
                ),
              ),
              SizedBox(height: 2 * scale),
              Text(
                friend.personality.isEmpty ? ' ' : friend.personality,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.63 * textScale,
                  fontWeight: FontWeight.w700,
                  height: 1.5,
                  color: selected
                      ? Colors.white
                      : BogleColors.text.withValues(alpha: .5),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The options' summary bar for the friend step: who was chosen, and what
/// a doll starts at (the S size, plain wrapping).
class _PickSummary extends StatelessWidget {
  const _PickSummary({
    required this.friend,
    required this.scale,
    required this.textScale,
  });
  final CharacterFriend friend;
  final double scale;
  final double textScale;

  @override
  Widget build(BuildContext context) {
    final label = TextStyle(
      fontSize: 11.06 * textScale,
      fontWeight: FontWeight.w700,
      height: 1.3,
      color: BogleColors.text.withValues(alpha: .7),
    );
    return Container(
      height: math.max(
        83 * scale,
        32 * scale + 42 * textScale * MediaQuery.textScalerOf(context).scale(1),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: 30 * scale,
        vertical: 12 * scale,
      ),
      decoration: BoxDecoration(
        color: BogleColors.logo.withValues(alpha: .2),
        borderRadius: BorderRadius.circular(5.53 * scale),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('선택한 친구', style: label),
                SizedBox(height: 8 * scale),
                Text(
                  friend.name,
                  key: const ValueKey('order-picked-name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16.59 * textScale,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    color: BogleColors.text.withValues(alpha: .8),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12 * scale),
          SvgPicture.asset(
            'assets/figma/order_summary_divider.svg',
            height: 61.92 * scale,
            excludeFromSemantics: true,
          ),
          SizedBox(width: 30 * scale),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('인형 가격', style: label),
                SizedBox(height: 5 * scale),
                // One line, shrinking on a narrow screen rather than
                // wrapping out of the bar.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${formatWon(DollOrder.basePrice + DollSize.small.extra)}부터',
                    key: const ValueKey('order-from-price'),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 22.11 * textScale,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: const Color(0xFF2A54FF),
                    ),
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
