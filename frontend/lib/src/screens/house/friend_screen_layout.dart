part of '../friend_screen.dart';

// Laying the house out: where the friend, guest, snack, clip and balloon go,
// and the little welcome and spoken-line widgets.

extension on _FriendScreenState {
  Widget _guestAt(
    CharacterFriend guest,
    FriendStatus status,
    double w,
    double feet,
  ) {
    final (:center, :size) = _visitorSpot(w);
    return Positioned(
      key: const ValueKey('house-guest'),
      left: center - size / 2,
      bottom: feet,
      width: size,
      height: size,
      child: DragTarget<Snack>(
        onWillAcceptWithDetails: (_) => _canGuestAct,
        onAcceptWithDetails: (drop) => _feed(drop.data, recipient: guest.id),
        builder: (context, _, _) => LivingCharacter(
          key: ValueKey('guest-${guest.id}'),
          friend: guest,
          asleep: false,
          reaction: Reaction.hearts,
          reactionId: _guestPets,
          onTap: _petGuest,
          size: size,
          cue: _guestCue,
          gaze: _guestGaze,
          attentive: _chatOpen || _meal != null || !_canGuestAct,
          onIdleAct: (act) => _respondTogether(true, act),
          onFigureSize: (figure) {
            if (_guest?.id == guest.id && _guestFigure != figure) {
              _update(() => _guestFigure = figure);
            }
          },
          hero: false,
        ),
      ),
    );
  }

  /// A motion clip standing where the figure stands: the friend in its
  /// first frame is lined up with the drawing on the rug — same height, same
  /// feet, same middle — so the figure and the clip swap without a jump.
  Widget? _clipAt(MotionClipKind kind, double w, double h, double feet) {
    final clip = _clips[kind];
    final figure = _figure;
    if (clip == null || figure == null) return null;
    final drawn = _on(
      _figureBox(figure, w, h, feet),
      _art ?? const Rect.fromLTWH(0, 0, 1, 1),
    );
    final scale = drawn.height / clip.figure.height;
    if (!scale.isFinite || scale <= 0) return null;
    final play = _plays;
    return Positioned(
      key: const ValueKey('friend-motion-clip'),
      left: drawn.center.dx - clip.figure.center.dx * scale,
      top: drawn.bottom - clip.figure.bottom * scale,
      width: clip.size.width * scale,
      height: clip.size.height * scale,
      child: IgnorePointer(
        child: MotionClipPlayer(
          // A new player for each play: it starts from the first frame.
          key: ValueKey(('clip', kind, play)),
          clip: clip,
          semanticLabel: _friend.name,
          onStarted: () => _clipStarted(play),
          onDone: () => _clipDone(play),
        ),
      ),
    );
  }

  /// Where the snack tray opens: it slides up and back down out of the
  /// way, the room easing to its new height either way.
  Widget _traySlot(Widget? tray) {
    const none = SizedBox(
      key: ValueKey('no-snack-tray'),
      width: double.infinity,
    );
    if (MediaQuery.disableAnimationsOf(context)) return tray ?? none;
    return AnimatedSize(
      duration: _FriendScreenState._trayMotion,
      curve: Curves.easeInOutCubic,
      alignment: Alignment.bottomCenter,
      child: AnimatedSwitcher(
        duration: _FriendScreenState._trayMotion,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, .4),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: tray ?? none,
      ),
    );
  }

  /// Where the figure stands: bottom-centred on the rug.
  Rect _figureBox(Size figure, double w, double h, double feet) =>
      Rect.fromLTWH(
        _hostCenter(w) - figure.width / 2,
        h - feet - figure.height,
        figure.width,
        figure.height,
      );

  /// [part] (fractions of the figure) on screen.
  static Rect _on(Rect box, Rect part) => Rect.fromLTRB(
    box.left + part.left * box.width,
    box.top + part.top * box.height,
    box.left + part.right * box.width,
    box.top + part.bottom * box.height,
  );

  /// The friend's mouth on screen: where its drawing or face map says, or
  /// else a little below the middle of its head.
  Rect _mouth(Rect box, FigureAnchors anchors) {
    if (anchors.mouth case final mouth?) return _on(box, mouth);
    final head = _on(box, anchors.head);
    return Rect.fromCenter(
      center: Offset(head.center.dx, head.top + head.height * .62),
      width: head.width * .12,
      height: head.height * .06,
    );
  }

  /// The snack being eaten, held up at the friend's mouth: in front of a
  /// side-on snout, or beside the corner of a mouth facing us — a little
  /// low, clear of the eye — so the mouth stays in sight as it eats.
  Widget? _eatingAt(
    Snack snack,
    double w,
    double h,
    double feet, {
    bool guest = false,
  }) {
    final figure = guest ? _guestFigure : _figure;
    if (figure == null) return null;
    final anchors = (guest ? _guestAnchors : _anchors) ?? FigureAnchors.whole;
    final box = guest
        ? Rect.fromLTWH(
            _visitorSpot(w).center - figure.width / 2,
            h - feet - figure.height,
            figure.width,
            figure.height,
          )
        : _figureBox(figure, w, h, feet);
    final mouth = _mouth(box, anchors);
    // Bite-sized: a little bigger than the mouth.
    final size = (mouth.width * 1.8).clamp(52.0, 80.0);
    final facing = anchors.facing;
    final centre = switch (facing) {
      < 0 => Offset(mouth.left - size * .55, mouth.center.dy - size * .05),
      > 0 => Offset(mouth.right + size * .55, mouth.center.dy - size * .05),
      _ => Offset(mouth.right + size * .42, mouth.center.dy + size * .14),
    };
    return Positioned(
      key: ValueKey(guest ? 'guest-snack' : 'house-snack'),
      left: centre.dx - size * .9,
      top: centre.dy - size * .9,
      child: Eating(
        key: ValueKey((guest, _mealNumber)),
        snack: snack,
        size: size,
        mouthSide: facing < 0 ? 1 : -1,
        onDone: guest ? _guestAte : _ate,
      ),
    );
  }

  /// Where [key]'s card is on screen (as drawn, scaled), if it's showing.
  Rect? _card(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return null;
    return MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
  }

  /// Comic placement: the balloon floats just above the top of the friend
  /// (horns and spines included) over its head, its tail aimed at the
  /// mouth. It keeps to the screen and clear of the corner cards, sliding
  /// sideways (the tail staying over the head) and wrapping narrower when
  /// it must; a friend too tall for a balloon above it gets one beside its
  /// head.
  Widget? _speech(double w, double h, double feet) {
    final speakingGuest = _guestSpeaking && _canGuestAct && _thinking == 0;
    final text = _thinking > 0
        ? '···'
        : speakingGuest
        ? _guestBubble
        : _bubble;
    final figure = speakingGuest ? _guestFigure : _figure;
    if (figure == null || text == null) return null;
    final speaker = _hasCompany
        ? (speakingGuest ? _guest!.name : _friend.name)
        : null;
    final box = speakingGuest
        ? Rect.fromLTWH(
            _visitorSpot(w).center - figure.width / 2,
            h - feet - figure.height,
            figure.width,
            figure.height,
          )
        : _figureBox(figure, w, h, feet);
    final anchors =
        (speakingGuest ? _guestAnchors : _anchors) ?? FigureAnchors.whole;
    final art = speakingGuest
        ? box
        : _on(box, _art ?? const Rect.fromLTWH(0, 0, 1, 1));
    final head = _on(box, anchors.head);
    const margin = 16.0, gap = 10.0;
    final ceiling =
        _stagePan +
        (_chatOpen
            ? MediaQuery.paddingOf(context).top + 12
            : AppTopBar.bottomFor(MediaQuery.of(context)) + 12);
    final maxWidth = _hasCompany ? 300.0 : SpeechBubble.widest;
    var balloon = SceneSpeech.estimate(context, text, width: maxWidth);
    var tip = Offset(
      head.center.dx + head.width * .18,
      math.min(head.top, art.top) - 18,
    );
    if (tip.dy - balloon.height < ceiling) {
      tip = Offset(head.right + 12, ceiling + balloon.height);
    }

    // The room left and right at the balloon's height.
    var lo = margin, hi = w - margin;
    final band = Rect.fromLTRB(0, tip.dy - balloon.height, w, tip.dy);
    for (final card in [
      if (_stagePan < 20) ...[?_card(_namePlate), ?_card(_back)],
    ]) {
      if (!card.overlaps(band)) continue;
      if (card.center.dx < w / 2) {
        lo = math.max(lo, card.right + gap);
      } else {
        hi = math.min(hi, card.left - gap);
      }
    }
    final room = math.max(SpeechBubble.narrowest + 40, hi - lo);
    if (balloon.width > room) {
      balloon = SceneSpeech.estimate(context, text, width: room);
    }

    // Figma's balloon points from its bottom-left corner, so that corner
    // goes at the tip and the balloon opens to the right; with no room
    // there it flips, pointing from its bottom-right corner instead.
    var width = balloon.width;
    var flip = tip.dx + width > hi && tip.dx - width >= lo;
    var left = (flip ? tip.dx - width : tip.dx)
        .clamp(lo, math.max(lo, hi - width))
        .toDouble();
    var sideTail = false;
    var speechWidth = math.min(maxWidth, room);
    // 키보드로 세로 공간이 줄면 두 친구의 얼굴을 덮지 않고 화자 바깥쪽에 둔다.
    final bodies = [
      Rect.fromLTWH(
        _hostCenter(w) - _stageSize / 2,
        h - feet - _stageSize,
        _stageSize,
        _stageSize,
      ),
      if (_hasCompany)
        Rect.fromLTWH(
          _visitorSpot(w).center - _visitorSpot(w).size / 2,
          h - feet - _visitorSpot(w).size,
          _visitorSpot(w).size,
          _visitorSpot(w).size,
        ),
    ];
    final body = Rect.fromLTWH(
      left,
      tip.dy - balloon.height,
      width,
      balloon.height - SpeechBubble.boxyTailHeight,
    );
    if (_chatOpen && bodies.any((figure) => body.overlaps(figure.inflate(8)))) {
      final leftEdge = bodies.map((r) => r.left).reduce(math.min);
      final rightEdge = bodies.map((r) => r.right).reduce(math.max);
      final leftRoom = leftEdge - margin - gap;
      final rightRoom = w - margin - gap - rightEdge;
      final useLeft = speakingGuest
          ? rightRoom < 180 && leftRoom > rightRoom
          : leftRoom >= 180 || leftRoom > rightRoom;
      speechWidth = math
          .min(maxWidth, useLeft ? leftRoom : rightRoom)
          .clamp(150.0, maxWidth);
      sideTail = true;
      balloon = SceneSpeech.estimate(
        context,
        text,
        width: speechWidth,
        sideTail: true,
      );
      width = balloon.width;
      left = useLeft ? leftEdge - gap - width : rightEdge + gap;
      flip = useLeft;
      final y = math.max(ceiling, head.center.dy - balloon.height);
      tip = Offset(tip.dx, y + balloon.height);
    }
    final still = MediaQuery.disableAnimationsOf(context);
    // A new line glides the balloon to its new spot rather than jumping
    // there; the old line fades as the new one pops out of the tail.
    return AnimatedPositioned(
      duration: still ? Duration.zero : const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      left: left,
      bottom: h - tip.dy,
      child: AnimatedSwitcher(
        duration: Duration(milliseconds: still ? 0 : 240),
        reverseDuration: Duration(milliseconds: still ? 0 : 140),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeIn,
        // Old and new share the tail's corner, so neither shifts sideways
        // while they swap.
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.bottomLeft,
          clipBehavior: Clip.none,
          children: [...previous, ?current],
        ),
        // Each pops out of (and back into) its own tail.
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: animation,
          alignment: (child as _Spoken).origin,
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: _Spoken(
          key: ValueKey((text, speaker)),
          origin: flip ? Alignment.bottomRight : Alignment.bottomLeft,
          child: SceneSpeech(
            text: text,
            speaker: speaker,
            maxWidth: speechWidth,
            sideTail: sideTail,
            tailRight: flip,
          ),
        ),
      ),
    );
  }
}

/// A line of speech in the balloon, remembering where its tail is so it
/// pops out of (and back into) that spot.
class _Spoken extends StatelessWidget {
  const _Spoken({super.key, required this.origin, required this.child});
  final Alignment origin;
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

/// "친구가 되었어요!" — the new friend moves into its house.
class _Welcome extends StatelessWidget {
  const _Welcome({required this.friend, required this.onEnter});
  final CharacterFriend friend;
  final VoidCallback onEnter;
  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: ColoredBox(
      color: const Color(0x66232A4D),
      child: Center(
        child: Container(
          width: 460,
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 28),
          decoration: houseCard(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 160,
                child: FriendArtwork(
                  assetPath: friend.assetPath,
                  semanticsLabel: friend.name,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '친구가 되었어요!',
                style: TextStyle(
                  fontFamily: bogleDisplayFont,
                  fontSize: 32,
                  color: BogleColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${friend.name}가 새 집으로 이사 왔어요.\n이제 여기서 계속 함께 지내요.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  height: 1.45,
                  color: BogleColors.muted,
                ),
              ),
              const SizedBox(height: 22),
              PrimaryButton(
                label: '집 구경하기',
                icon: Icons.home_rounded,
                onPressed: onEnter,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
