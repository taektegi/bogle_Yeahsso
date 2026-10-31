part of '../friend_screen.dart';

extension on _FriendScreenState {
  Future<void> _openInvites() async {
    if (_inviteTray) {
      _update(() => _inviteTray = false);
      return;
    }
    if (_inviting || _hasCompany || _meal != null || _status?.asleep != false) {
      return;
    }
    final visit = _visit;
    try {
      final everyone = await widget.repository.fetchFriends();
      if (!mounted ||
          visit != _visit ||
          _hasCompany ||
          _status?.asleep != false) {
        return;
      }
      _update(() {
        _others = everyone.where((f) => f.id != _friend.id).toList();
        _inviteTray = true;
        _snackTray = false;
        _chatOpen = false;
      });
    } catch (error) {
      if (mounted) _tell(failureMessage(error, '친구들을 불러오지 못했어요.'));
    }
  }

  double get _guestTravel {
    final spot = _visitorSpot(_room.width);
    return (_room.width - spot.center) / spot.size + .7;
  }

  Future<void> _invite(CharacterFriend guest) async {
    if (_inviting || _hasCompany || _status?.asleep != false) return;
    _inviting = true;
    final visit = ++_visit;
    try {
      final status = await widget.repository.fetchStatus(guest.id);
      if (!mounted || visit != _visit || _status?.asleep != false) return;
      if (guest.sleep.asleepAt(_now())) {
        _tell("${particle(guest.name, '은', '는')} 지금 자고 있어요.");
        return;
      }
      _update(() {
        _inviteTray = false;
        _bubble = null;
        _guestBubble = null;
        _guest = guest;
        _guestStatus = status.copyWith(asleep: false);
        _guestAnchors = null;
        _guestFigure = null;
        _guestReady = false;
        _guestLeaving = false;
        _guestSpeaking = false;
        _guestCue = FigureCue(
          Act.enter,
          travel: _guestTravel,
          direction: -1,
          onDone: () => _arrived(guest),
        );
        _hostCue = FigureCue(Act.lookAround);
      });
      if (MediaQuery.disableAnimationsOf(context)) {
        _company.value = 1;
      } else {
        _company.forward();
      }
      anchorsFor(guest.assetPath)
          .then((anchors) {
            if (mounted && visit == _visit && _guest?.id == guest.id) {
              _update(() => _guestAnchors = anchors);
            }
          })
          .onError((_, _) {});
    } catch (error) {
      if (mounted && visit == _visit) {
        _tell(failureMessage(error, '친구를 초대하지 못했어요.'));
      }
    } finally {
      _inviting = false;
    }
  }

  void _arrived(CharacterFriend guest) {
    if (!mounted || _guest != guest || _guestLeaving || _status == null) return;
    _update(() {
      _guestReady = true;
      _bubble = _talk.say(TalkTopic.welcome, thing: guest.name);
      _guestSpeaking = false;
      _recordLine((mine: false, text: _bubble!));
      _status = _status!.copyWith(
        mood: _status!.mood + 6,
        closeness: _status!.closeness + 1,
        updatedAt: DateTime.now(),
      );
      _hostCue = FigureCue(Act.wave);
    });
    _saveStatus(_status!);
    _laterForGuest(guest, greetingReplyDelay(_bubble!), () {
      _guestCue = FigureCue(Act.wave, direction: -1);
      _guestBubble = FriendTalk(guest).say(TalkTopic.visit);
      _recordLine((mine: false, text: _guestBubble!), speaker: guest);
      _guestSpeaking = true;
    });
  }

  void _laterForGuest(
    CharacterFriend guest,
    Duration delay,
    VoidCallback action,
  ) {
    final visit = _visit;
    final hostIntent = _hostIntent, guestIntent = _guestIntent;
    _timers.add(
      Timer(delay, () {
        if (!mounted ||
            visit != _visit ||
            hostIntent != _hostIntent ||
            guestIntent != _guestIntent ||
            _guest?.id != guest.id ||
            !_canGuestAct ||
            _meal != null ||
            _thinking > 0 ||
            _chatOpen) {
          return;
        }
        _update(action);
      }),
    );
  }

  void _petGuest() {
    final guest = _guest, status = _guestStatus;
    if (guest == null || status == null || !_canGuestAct || _meal != null) {
      return;
    }
    _guestIntent++;
    _update(() {
      _guestPets++;
      _guestBubble = FriendTalk(guest).say(TalkTopic.pet);
      _recordLine((mine: false, text: _guestBubble!), speaker: guest);
      _guestSpeaking = true;
      _guestStatus = status.copyWith(
        mood: status.mood + 3,
        closeness: status.closeness + 1,
        updatedAt: DateTime.now(),
      );
    });
    _saveVisitor(guest.id, _guestStatus!);
    _respondTogether(true, Act.giggle);
  }

  Future<void> _saveVisitor(String id, FriendStatus status) async {
    try {
      await widget.repository.saveStatus(id, status);
    } catch (error) {
      if (mounted) _tell(failureMessage(error, '친구의 돌봄 기록을 저장하지 못했어요.'));
    }
  }

  void _respondTogether(bool fromGuest, Act act) {
    final guest = _guest;
    if (guest == null ||
        !_canGuestAct ||
        _socialBusy ||
        _meal != null ||
        _chatOpen ||
        _thinking > 0 ||
        _performing != null) {
      return;
    }
    final response = switch (act) {
      Act.sneeze || Act.hiccup => Act.wonder,
      Act.dance || Act.wiggle || Act.hum => Act.wiggle,
      Act.wave => Act.wave,
      Act.giggle || Act.laugh => Act.lookAround,
      _ => null,
    };
    if (response == null) return;
    _socialBusy = true;
    _laterForGuest(guest, const Duration(milliseconds: 600), () {
      if (fromGuest) {
        _hostCue = FigureCue(response);
      } else {
        _guestCue = FigureCue(response, direction: -1);
      }
    });
    _timers.add(
      Timer(const Duration(seconds: 5), () {
        _socialBusy = false;
      }),
    );
  }

  void _seeGuestOff({bool saying = true}) {
    final guest = _guest;
    if (guest == null || _guestLeaving) return;
    ++_visit; // 이전 방문의 늦은 반응을 새 손님에게 적용하지 않는다.
    _guestServe?.cancel();
    _guestServe = null;
    void leave() {
      if (!mounted || _guest?.id != guest.id) return;
      _update(
        () => _guestCue = FigureCue(
          Act.leave,
          travel: _guestTravel,
          onDone: () {
            if (!mounted || _guest?.id != guest.id) return;
            _update(() {
              _guest = null;
              _guestStatus = null;
              _guestCue = null;
              _guestLeaving = false;
              _guestReady = false;
              _socialBusy = false;
              _guestFigure = null;
              _guestAnchors = null;
              _guestSpeaking = false;
            });
            if (MediaQuery.disableAnimationsOf(context)) {
              _company.value = 0;
            } else {
              _company.reverse();
            }
          },
        ),
      );
    }

    _update(() {
      _guestLeaving = true;
      _guestReady = false;
      _guestEating = null;
      _guestBubble = null;
      _guestSpeaking = false;
      _inviteTray = false;
      if (saying) {
        _bubble = _talk.say(TalkTopic.bye, thing: guest.name);
        _recordLine((mine: false, text: _bubble!));
        _hostCue = FigureCue(Act.wave);
      }
      _guestCue = FigureCue(Act.wave, direction: -1, onDone: leave);
    });
    _finishMealIfDone();
  }
}
