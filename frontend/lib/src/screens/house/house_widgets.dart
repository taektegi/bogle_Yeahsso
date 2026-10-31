import '../../util/art_cache.dart';

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../data/art_source.dart';
import '../../models/character_friend.dart';
import '../../models/friend_status.dart';
import '../../theme/bogle_theme.dart';
import '../../widgets/bogle_widgets.dart';
import '../../widgets/house_transition.dart';
import 'face_map.dart';
import 'figure_motion.dart';
import 'figure_rig.dart';

part 'house_widgets/speech_bubble.dart';
part 'house_widgets/art_looks.dart';
part 'house_widgets/silhouettes.dart';
part 'house_widgets/action_tiles.dart';
part 'house_widgets/window_notice.dart';

/// Figma's white cards: 0 0 4 1 shadow at 15 % black.
BoxDecoration houseCard([double radius = 15]) => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(radius),
  boxShadow: figmaShadow,
);

/// Figma "Group 1261155779": who this friend is. Its name in 양진체, its
/// personality on a blue chip and how it's doing today in Pretendard, and
/// below them when it goes to bed (tap to change).
class NamePlate extends StatelessWidget {
  const NamePlate({
    super.key,
    required this.friend,
    this.status,
    this.onEditSleep,
  });
  final CharacterFriend friend;
  final FriendStatus? status;
  final VoidCallback? onEditSleep;

  static const _ui = TextStyle(
    fontFamily: bogleUiFont,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.39,
    color: BogleColors.text,
  );

  /// Today in a line, from its needs: sleepy, hungry or happy.
  static String feeling(FriendStatus status) {
    if (status.asleep) return '지금은 자는 중...';
    if (status.fullness < 40) return '배가 고파요';
    if (status.energy < 35) return '조금 졸려요';
    if (status.mood >= 70) return '오늘도 힘찬 하루 !';
    if (status.mood >= 45) return '기분 좋은 하루예요';
    return '조금 심심해요';
  }

  @override
  Widget build(BuildContext context) {
    final sleep = friend.sleep;
    final status = this.status;
    return Container(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 280),
      padding: const EdgeInsets.fromLTRB(10, 4, 12, 8),
      decoration: houseCard(),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 3),
              child: Text(
                friend.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: bogleDisplayFont,
                  fontSize: 20,
                  height: 2,
                  letterSpacing: -0.6,
                  color: BogleColors.text,
                ),
              ),
            ),
            const SizedBox(height: 7),
            if (friend.personality.isNotEmpty)
              Container(
                constraints: const BoxConstraints(minWidth: 115, minHeight: 35),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: BogleColors.logo,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    friend.personality,
                    style: _ui.copyWith(color: Colors.white),
                  ),
                ),
              ),
            if (status != null) ...[
              const SizedBox(height: 15),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  feeling(status),
                  key: const ValueKey('house-feeling'),
                  style: _ui,
                ),
              ),
            ],
            const SizedBox(height: 6),
            Semantics(
              button: onEditSleep != null,
              label:
                  '잠자는 시간, ${timeOfDayLabel(sleep.bedtime)}에 자고 '
                  '${timeOfDayLabel(sleep.wakeTime)}에 일어나요',
              hint: onEditSleep == null ? null : '눌러서 바꾸기',
              excludeSemantics: true,
              child: InkWell(
                key: const ValueKey('house-sleep-schedule'),
                borderRadius: BorderRadius.circular(10),
                onTap: onEditSleep,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 2, 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.bedtime_rounded,
                        size: 15,
                        color: Color(0xFF8C7BFF),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          '${timeOfDayLabel(sleep.bedtime)} ~ '
                          '${timeOfDayLabel(sleep.wakeTime)}',
                          key: const ValueKey('house-sleep-label'),
                          style: _ui.copyWith(
                            fontSize: 12,
                            letterSpacing: -0.36,
                            color: BogleColors.muted,
                          ),
                        ),
                      ),
                      if (onEditSleep != null)
                        const Icon(
                          Icons.edit_rounded,
                          size: 13,
                          color: BogleColors.muted,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum Reaction {
  none,
  hearts,
  jump,

  /// "No thanks": a small side-to-side shake.
  shake,
}

/// Something for a friend to act out, given by the scene (a guest hopping
/// in, a wave hello). A new cue plays even if it asks for the same act.
class FigureCue {
  FigureCue(this.act, {this.travel = 1.5, this.direction = 1, this.onDone});
  final Act act;

  /// For [Act.enter] and [Act.leave]: how far it hops, in stage sizes.
  final double travel;

  /// Which way it hops, or which arm waves: -1 left, 1 right.
  final double direction;
  final VoidCallback? onDone;
}

/// The friend standing on its rug, alive: it breathes and blinks, now and
/// then hops, waves or dances on its own (see [FigureMotion]), answers
/// being touched, and nods off at bedtime with floating Zs.
class LivingCharacter extends StatefulWidget {
  const LivingCharacter({
    super.key,
    required this.friend,
    required this.asleep,
    required this.reaction,
    required this.reactionId,
    required this.onTap,
    required this.size,
    this.onFigureSize,
    this.gaze,
    this.cue,
    this.hero = true,
    this.random,
    this.vibe = Vibe.calm,
    this.attentive = false,
    this.onIdleAct,
  });
  final CharacterFriend friend;
  final bool asleep;

  /// How the friend feels: what it does by itself follows it.
  final Vibe vibe;
  final bool attentive;
  final ValueChanged<Act>? onIdleAct;
  final Reaction reaction;

  /// Changes each time a new reaction should play.
  final int reactionId;
  final VoidCallback onTap;
  final double size;

  /// The drawn figure's size; it always stands bottom-centred in the
  /// [size] square.
  final ValueChanged<Size>? onFigureSize;

  /// Where something tempting is, from -1 (far left) to 1 (far right); the
  /// friend leans and stretches toward it. Null when there is nothing.
  final ValueListenable<double?>? gaze;

  final FigureCue? cue;

  /// Flies between pages with the friend's other pictures (the host does;
  /// a visiting guest does not).
  final bool hero;

  /// Picks the idle acts and their timing; injectable for tests.
  final math.Random? random;

  @override
  State<LivingCharacter> createState() => _LivingCharacterState();
}

class _LivingCharacterState extends State<LivingCharacter>
    with SingleTickerProviderStateMixin {
  late final FigureMotion _motion = FigureMotion(random: widget.random)
    ..vibe = widget.vibe
    ..liveliness = _energy;
  double get _energy {
    final personality = widget.friend.personality;
    if (RegExp('차분|조용|느긋|든든').hasMatch(personality)) return .9;
    if (RegExp('호기심|탐험|활발|장난|엉뚱').hasMatch(personality)) return 1.05;
    return 1;
  }

  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  final _pose = ValueNotifier(FigurePose.rest);

  @visibleForTesting
  FigurePose get debugPose => _pose.value;
  @visibleForTesting
  Act? get debugAct => _motion.acting;
  bool _still = false;
  bool _started = false;

  // The shuttle is the original drawing. Do not let the hidden landing
  // figure breathe/blink ahead of it, then jump to that pose on handoff.
  Animation<double>? _arrival;
  bool _arriving = false;
  static const _settleSeconds = .32;
  double _life = _settleSeconds;
  double get _settle => _still
      ? 1
      : Curves.easeInOut.transform((_life / _settleSeconds).clamp(0.0, 1.0));

  /// The drawing's moving parts, or for a flat picture where its face is,
  /// once read. Without either it moves as a whole.
  FigureRig? _rig;
  FaceMap? _face;
  bool? _card;

  @override
  void initState() {
    super.initState();
    final asset = widget.friend.assetPath;
    rigFor(asset).then((rig) {
      if (!mounted || rig == null) return;
      _motion
        ..hasArms = rig.hasArms
        ..facing = rig.facing;
      setState(() => _rig = rig);
    });
    faceMapFor(asset).then((face) {
      if (!mounted || face == null) return;
      _motion.facing = face.facing;
      setState(() => _face = face);
    });
    standsAsCard(asset).then((card) {
      if (mounted && card != _card) setState(() => _card = card);
    });
  }

  double? _heartsAt;
  double _width = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    final arrival = ModalRoute.of(context)?.animation;
    if (!identical(arrival, _arrival)) {
      _arrival?.removeStatusListener(_onArrival);
      _arrival = arrival;
      arrival?.addStatusListener(_onArrival);
      if (arrival != null) _onArrival(arrival.status);
    }
    if (_still) {
      _ticker.stop();
      _pose.value = FigureMotion.still(asleep: widget.asleep);
    } else if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
    // A cue given from the start (a guest arriving) plays once we know
    // whether anything may move.
    if (!_started) {
      _started = true;
      if (widget.cue case final cue?) _play(cue);
    }
  }

  void _onArrival(AnimationStatus status) {
    if (status == AnimationStatus.reverse) return;
    _arriving = status != AnimationStatus.completed;
    if (_arriving) {
      _life = 0;
      if (!_still) _pose.value = FigurePose.rest;
    }
  }

  @override
  void didUpdateWidget(LivingCharacter old) {
    super.didUpdateWidget(old);
    _motion
      ..vibe = widget.vibe
      ..liveliness = _energy;
    if (!old.attentive &&
        widget.attentive &&
        identical(old.cue, widget.cue) &&
        !const [
          Act.eat,
          Act.enter,
          Act.leave,
          Act.doze,
        ].contains(_motion.acting)) {
      _motion.play(Act.wonder);
    }
    if (!identical(old.cue, widget.cue) && widget.cue != null) {
      _play(widget.cue!);
    }
    if (old.asleep != widget.asleep) {
      if (_still) {
        _pose.value = FigureMotion.still(asleep: widget.asleep);
      } else {
        // Nods off at bedtime; wakes with a big stretch.
        _motion.play(widget.asleep ? Act.doze : Act.stretch);
      }
    }
    if (old.reactionId != widget.reactionId &&
        widget.reaction != Reaction.none &&
        !_still) {
      final act = switch (widget.reaction) {
        // A pat is answered differently each time: a giggle, a laugh, a
        // shy blush or a happy bounce.
        Reaction.hearts => _motion.patAct(),
        Reaction.jump => Act.hop,
        Reaction.shake => Act.shake,
        Reaction.none => null,
      };
      if (act != null) _motion.play(act);
      if (widget.reaction == Reaction.hearts) _heartsAt = _motion.time;
    }
  }

  void _play(FigureCue cue) {
    if (_still) {
      // Nothing moves: the scene carries on as if the act had played.
      if (cue.onDone case final done?) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) done();
        });
      }
      return;
    }
    _motion.play(
      cue.act,
      travel: cue.travel,
      direction: cue.direction,
      onDone: cue.onDone,
    );
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (_arriving) return;
    _life = math.min(_settleSeconds, _life + math.min(dt, .025));
    final before = _motion.acting;
    _motion.advance(
      dt,
      asleep: widget.asleep,
      idle: !widget.attentive,
      gaze: widget.gaze?.value,
    );
    if (before == null) {
      if (_motion.acting case final act?) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onIdleAct?.call(act);
        });
      }
    }
    _pose.value = FigurePose.fromRest(_motion.pose, _settle);
  }

  @override
  void dispose() {
    _arrival?.removeStatusListener(_onArrival);
    _ticker.dispose();
    _pose.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final figure = FriendFigure(
      friend: widget.friend,
      slotSize: s,
      pose: _pose,
      rig: _rig,
      face: _face,
      card: _card,
      onSize: (size) {
        _width = size.width;
        widget.onFigureSize?.call(size);
      },
    );
    return Semantics(
      button: true,
      label: '${widget.friend.name} 쓰다듬기',
      excludeSemantics: true,
      // The whole spot the friend stands in responds, not just the drawn
      // pixels: short, wide drawings leave most of it empty.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          width: s,
          height: s,
          child: AnimatedBuilder(
            animation: _pose,
            // The drawing itself is built once; only its transform changes.
            child: widget.hero
                ? friendHero(
                    id: widget.friend.id,
                    assetPath: widget.friend.assetPath,
                    standing: true,
                    child: figure,
                  )
                : figure,
            builder: (context, figure) {
              final p = _pose.value;
              final time = _still ? 0.0 : _motion.time;
              final hearts = _heartsAt == null
                  ? 1.0
                  : (time - _heartsAt!) / 1.1;
              // Softer and smaller the higher it is off the floor.
              final away = (p.lift * 2.2).clamp(0.0, .7);
              final shadowWidth = (_width > 0 ? _width : s * .6) * .62;
              return Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: [
                  Positioned(
                    bottom: -shadowWidth * .07,
                    left: s / 2 + p.dx * s - shadowWidth / 2,
                    width: shadowWidth,
                    height: shadowWidth * .14,
                    child: IgnorePointer(
                      child: Transform.scale(
                        scale: 1 - away * .55,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.all(
                              Radius.elliptical(shadowWidth, shadowWidth * .14),
                            ),
                            color: const Color(
                              0xFF3A4A8C,
                            ).withValues(alpha: .16 * (1 - away)),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF3A4A8C,
                                ).withValues(alpha: .1 * (1 - away)),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(p.dx * s, p.dy * s),
                    child: Transform(
                      alignment: Alignment.bottomCenter,
                      transform: Matrix4.rotationZ(p.tilt)
                        ..multiply(Matrix4.skewX(p.lean))
                        ..multiply(
                          Matrix4.diagonal3Values(
                            p.scaleX * p.turn,
                            p.scaleY,
                            1,
                          ),
                        ),
                      child: Opacity(
                        opacity: widget.asleep ? 1 - .12 * _settle : 1,
                        child: figure,
                      ),
                    ),
                  ),
                  if (widget.asleep)
                    for (var i = 0; i < 3; i++)
                      _Floater(
                        progress: (time / 2.8 + i / 3) % 1,
                        // Left of the head; the speech bubble opens to the right.
                        from: Offset(-s * .2, -s * .42),
                        child: Text(
                          'Z',
                          style: TextStyle(
                            fontSize: 22.0 + i * 6,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            shadows: const [
                              Shadow(color: Color(0x553A4A8C), blurRadius: 6),
                            ],
                          ),
                        ),
                      ),
                  // 에취! 딸꾹! 부르르 — said out loud beside the head.
                  if (_motion.acting case final act? when !_still)
                    if (soundOf(act, _motion.actTime ?? 0) case (
                      final word,
                      final progress,
                    ))
                      _Floater(
                        progress: .1 + progress * .85,
                        from: Offset(s * .3 + p.dx * s, -s * .55),
                        child: Transform.scale(
                          scale: Curves.easeOutBack.transform(
                            (progress * 5).clamp(0.0, 1.0),
                          ),
                          child: Text(
                            word,
                            style: TextStyle(
                              fontFamily: bogleDisplayFont,
                              fontSize: 30,
                              color: Color.lerp(
                                Color(widget.friend.accentHex),
                                BogleColors.text,
                                .45,
                              ),
                              shadows: const [
                                Shadow(color: Colors.white, blurRadius: 8),
                                Shadow(color: Colors.white, blurRadius: 3),
                              ],
                            ),
                          ),
                        ),
                      ),
                  if (hearts < 1)
                    for (var i = 0; i < 5; i++)
                      _Floater(
                        progress: (hearts * 1.2 - i * .08).clamp(0.0, 1.0),
                        from: Offset((i - 2) * s * .12 + p.dx * s, -s * .7),
                        child: Icon(
                          Icons.favorite_rounded,
                          size: 22.0 + (i % 2) * 8,
                          color: const Color(0xFFFF7FA3),
                        ),
                      ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Cut-out friends (vector or clear-ground PNG) stand as they are, a rigged
/// one moving its eyes and arms with [pose]; photographed drawings become
/// a sticker standee so they read as a character rather than a photo.
class FriendFigure extends StatelessWidget {
  const FriendFigure({
    super.key,
    required this.friend,
    this.onSize,
    this.pose,
    this.rig,
    this.face,
    this.card,
    this.slotSize,
  });
  final CharacterFriend friend;
  final double? slotSize;
  final ValueChanged<Size>? onSize;
  final ValueListenable<FigurePose>? pose;

  /// Stands as a card (see [standsAsCard]); until that is known, only
  /// photographed drawings do.
  final bool? card;
  bool get _card => card ?? isPhotographedArt(friend.assetPath);

  /// The drawing's moving parts; with [pose] they move on their own.
  final FigureRig? rig;

  /// Where a flat picture's face is; with [pose] its face is drawn moving
  /// over it.
  final FaceMap? face;

  /// One canvas for both the plain image (while a rig/face loads) and the
  /// animated figure. SVGs otherwise keep their intrinsic size under loose
  /// constraints, while AspectRatio-based rigs expand to the whole slot.
  /// A Hero placeholder locks that smaller size until its last frame.
  Widget _cutout(Widget child) => FutureBuilder<ArtLook?>(
    future: artLookOf(friend.assetPath),
    initialData: measuredArtLook(friend.assetPath),
    builder: (context, snapshot) {
      final look = snapshot.data;
      final aspect =
          look?.natural.aspectRatio ??
          artAspects[friend.assetPath] ??
          rig?.canvas.aspectRatio ??
          face?.size.aspectRatio ??
          1;
      final side = slotSize;
      if (side == null) {
        return _MeasureSize(
          onSize: onSize,
          child: AspectRatio(aspectRatio: aspect, child: child),
        );
      }
      final drawn = look?.drawn ?? const Rect.fromLTWH(0, 0, 1, 1);
      final visibleW = math.max(.01, aspect * drawn.width);
      final visibleH = math.max(.01, drawn.height);
      final height = math.min(
        side / math.max(1, aspect),
        math.min(
          side * .64 / math.sqrt(visibleW * visibleH),
          math.min(side * .94 / visibleW, side * .85 / visibleH),
        ),
      );
      return _MeasureSize(
        onSize: onSize,
        child: SizedBox(width: height * aspect, height: height, child: child),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final rig = this.rig;
    if (rig != null && pose != null) {
      return _cutout(
        ValueListenableBuilder(
          valueListenable: pose!,
          builder: (context, pose, _) =>
              RiggedArtwork(rig: rig, pose: pose, semanticsLabel: friend.name),
        ),
      );
    }
    final face = this.face;
    final card = _card;
    if (face != null && pose != null && !card) {
      return _cutout(
        CustomPaint(
          foregroundPainter: FacePainter(face, pose!),
          child: FriendArtwork(
            assetPath: friend.assetPath,
            semanticsLabel: friend.name,
            fit: BoxFit.fill,
          ),
        ),
      );
    }
    if (!card) {
      return _cutout(
        FriendArtwork(
          assetPath: friend.assetPath,
          semanticsLabel: friend.name,
          fit: BoxFit.fill,
          alignment: Alignment.bottomCenter,
        ),
      );
    }
    return Align(
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        widthFactor: .82,
        heightFactor: .82,
        alignment: Alignment.bottomCenter,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: _MeasureSize(
            onSize: onSize,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x333A4A8C),
                    blurRadius: 18,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: FriendArtwork(
                  assetPath: friend.assetPath,
                  semanticsLabel: friend.name,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Floater extends StatelessWidget {
  const _Floater({
    required this.progress,
    required this.from,
    required this.child,
  });
  final double progress;
  final Offset from;
  final Widget child;
  @override
  Widget build(BuildContext context) => Positioned(
    bottom: -from.dy + progress * 80,
    left: 0,
    right: 0,
    child: IgnorePointer(
      child: Transform.translate(
        offset: Offset(from.dx + math.sin(progress * math.pi * 2) * 10, 0),
        child: Opacity(
          opacity: math.sin(progress * math.pi).clamp(0.0, 1.0),
          child: Center(child: child),
        ),
      ),
    ),
  );
}
