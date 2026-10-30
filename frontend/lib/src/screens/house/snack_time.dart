part of '../friend_screen.dart';

class _Serving {
  _Serving(this.snack, {required this.host, this.guestId, this.guestVisit});
  final Snack snack;
  final bool host;
  final String? guestId;
  final int? guestVisit;
  bool hostAte = false, guestAte = false;
}

extension on _FriendScreenState {
  void _openSnacks() => _update(() {
    _snackTray = !_snackTray;
    _inviteTray = false;
    _chatOpen = false;
  });

  /// 눌러 주면 함께, 특정 친구에게 끌어 주면 그 친구만 먹는다.
  void _feed(Snack snack, {String? recipient}) {
    if (_status?.asleep != false || (_hasCompany && !_canGuestAct)) return;
    final guestId =
        _canGuestAct && (recipient == null || recipient == _guest!.id)
        ? _guest!.id
        : null;
    final host = recipient == null || recipient == _friend.id;
    if (!host && guestId == null) return;
    _hostIntent++;
    _guestIntent++;
    _gaze.value = null;
    _guestGaze.value = null;
    _update(() {
      _snackTray = false;
      _bubble = null;
      _guestBubble = null;
      _guestSpeaking = false;
    });
    _snacks.add(
      _Serving(
        snack,
        host: host,
        guestId: guestId,
        guestVisit: guestId == null ? null : _visit,
      ),
    );
    _serveNext();
  }

  void _serveNext() {
    if (_meal != null || _serve != null || _snacks.isEmpty) return;
    final meal = _snacks.removeAt(0);
    _meal = meal;
    _mealNumber++;
    void begin() {
      _serve = null;
      if (!mounted || !identical(_meal, meal)) return;
      final guest = _guest;
      if (guest != null &&
          guest.id == meal.guestId &&
          meal.guestVisit == _visit &&
          _canGuestAct) {
        void guestBite() {
          _guestServe = null;
          if (!mounted || !identical(_meal, meal)) return;
          if (_guest?.id != meal.guestId ||
              meal.guestVisit != _visit ||
              !_canGuestAct) {
            _finishMealIfDone();
            return;
          }
          _update(() {
            _guestEating = meal.snack;
            _guestCue = FigureCue(
              Act.eat,
              direction: (_guestAnchors?.facing ?? 0) < 0 ? -1 : 1,
            );
          });
        }

        _guestServe = Timer(
          MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 350),
          guestBite,
        );
      }
      if (meal.host && _status?.asleep == false) {
        _update(() {
          _stopClip();
          _eating = meal.snack;
          _hostCue = FigureCue(
            Act.eat,
            direction: (_anchors?.facing ?? 0) < 0 ? -1 : 1,
          );
        });
      }
      _finishMealIfDone();
    }

    if (MediaQuery.disableAnimationsOf(context)) {
      begin();
    } else {
      _serve = Timer(_FriendScreenState._trayMotion, begin);
    }
  }

  void _ate() {
    final snack = _eating, status = _status;
    if (snack == null || status == null) return;
    final favorite = snack.isFavouriteOf(_friend);
    _meal?.hostAte = true;
    final shared =
        _meal?.guestId != null &&
        _guest?.id == _meal?.guestId &&
        !_guestLeaving;
    final line = shared
        ? '같이 먹으니까 더 맛있어!'
        : _talk.say(
            favorite ? TalkTopic.treat : TalkTopic.snack,
            thing: snack.label,
          );
    _update(() {
      _eating = null;
      _guestSpeaking = false;
      _status = _afterSnack(status, favorite);
      _bubble = line;
      _recordLine((mine: false, text: line));
    });
    _saveStatus(_status!);
    _finishMealIfDone();
    if (_meal == null && _snacks.isEmpty && favorite) {
      _update(() => _perform(MotionClipKind.jump, Reaction.hearts));
    }
  }

  FriendStatus _afterSnack(FriendStatus status, bool favorite) =>
      status.copyWith(
        fullness: status.fullness + 22,
        mood: status.mood + (favorite ? 10 : 5),
        closeness: status.closeness + (favorite ? 3 : 2),
        updatedAt: DateTime.now(),
      );

  void _guestAte() {
    final guest = _guest, status = _guestStatus, snack = _guestEating;
    if (guest == null || status == null || snack == null || !_canGuestAct) {
      return;
    }
    final favorite = snack.isFavouriteOf(guest);
    _meal?.guestAte = true;
    _update(() {
      _guestEating = null;
      _guestStatus = _afterSnack(status, favorite);
      _guestBubble = FriendTalk(
        guest,
      ).say(favorite ? TalkTopic.treat : TalkTopic.snack, thing: snack.label);
      _recordLine((mine: false, text: _guestBubble!), speaker: guest);
      _guestSpeaking = true;
      if (favorite) _guestPets++;
    });
    _saveVisitor(guest.id, _guestStatus!);
    _finishMealIfDone();
  }

  void _finishMealIfDone() {
    if (_meal == null ||
        _serve != null ||
        _guestServe != null ||
        _eating != null ||
        _guestEating != null) {
      return;
    }
    final finished = _meal!;
    _meal = null;
    if (finished.hostAte &&
        finished.guestAte &&
        _guest?.id == finished.guestId) {
      _rememberSnack(_guest!, finished.snack);
    }
    _serveNext();
    if (_meal == null && _deferredAnswers.isNotEmpty) {
      final next = _deferredAnswers.removeAt(0);
      _showAnswer(next.text, next.topic);
    }
  }

  Future<void> _rememberSnack(CharacterFriend guest, Snack snack) async {
    try {
      await widget.repository.addMemory(
        _friend.id,
        "${particle(guest.name, '과', '와')} ${particle(snack.label, '을', '를')} 나눠 먹었어.",
      );
      await widget.repository.addMemory(
        guest.id,
        "${particle(_friend.name, '과', '와')} ${particle(snack.label, '을', '를')} 나눠 먹었어.",
      );
    } catch (error) {
      if (mounted) _tell(failureMessage(error, '함께한 추억을 저장하지 못했어요.'));
    }
  }

  void _cancelMeals() {
    _serve?.cancel();
    _serve = null;
    _guestServe?.cancel();
    _guestServe = null;
    _snacks.clear();
    _meal = null;
    _eating = null;
    _guestEating = null;
    _deferredAnswers.clear();
    _gaze.value = null;
    _guestGaze.value = null;
  }

  void _dragSnack(Offset? global, double width) {
    if (global == null) {
      _gaze.value = null;
      _guestGaze.value = null;
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final x = box.globalToLocal(global).dx;
    _gaze.value = ((x - _hostCenter(width)) / (_stageSize / 2)).clamp(
      -1.0,
      1.0,
    );
    _guestGaze.value = ((x - _visitorSpot(width).center) / (_stageSize / 2))
        .clamp(-1.0, 1.0);
  }
}
