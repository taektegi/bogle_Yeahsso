import '../data/api/api_client.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/app_services.dart';
import '../data/character_repository.dart';
import '../data/chat_service.dart';
import '../data/conversation_archive.dart';
import '../data/failures.dart';
import '../data/friend_talk.dart';
import '../data/korean.dart';
import '../data/motion_service.dart';
import '../data/window_view.dart';
import '../models/character_friend.dart';
import '../models/friend_status.dart';
import '../theme/bogle_theme.dart';
import '../widgets/bogle_widgets.dart';
import '../widgets/top_bar.dart';
import 'house/chat_panel.dart';
import 'house/scene_speech.dart';
import 'house/figure_motion.dart';
import 'house/house_widgets.dart';
import 'house/invite_tray.dart';
import 'house/motion_clip_player.dart';
import 'house/room_scene.dart';
import 'house/sleep_schedule_dialog.dart';
import 'house/snacks.dart';
import 'profile/profile_widgets.dart';

part 'house/friend_screen_layout.dart';
part 'house/company.dart';
part 'house/snack_time.dart';

/// The friend's house (Figma 568:2335, asleep 568:2533): the friend keeps
/// living in a room made for it, looking out on its own view. It lives
/// there on its own — hops, waves and dances now and then, and goes to bed
/// and gets up at its own times — while the child talks with it, feeds it
/// and invites friends over.
class FriendScreen extends StatefulWidget {
  const FriendScreen({
    super.key,
    required this.repository,
    required this.friend,
    this.celebrate = false,
    this.random,
    this.motion,
    this.chat,
    this.clock,
  });

  final CharacterRepository repository;
  final CharacterFriend friend;

  /// Just created: show the moving-in welcome first.
  final bool celebrate;

  /// Scripted lines; injectable for tests.
  final math.Random? random;

  /// Animated clips; defaults to the app's ([AppServices]).
  final MotionService? motion;

  /// Answers in the chat; defaults to the app's ([AppServices]).
  final ChatService? chat;

  /// The time of day, for bedtime and the window; injectable for tests.
  final DateTime Function()? clock;

  @override
  State<FriendScreen> createState() => _FriendScreenState();
}

class _FriendScreenState extends State<FriendScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  /// The friend, as last saved here (bedtime, memories and level change).
  late CharacterFriend _friend = widget.friend;
  late final FriendTalk _talk = FriendTalk(_friend, random: widget.random);
  late final ChatService _chat = widget.chat ?? AppServices.of(context).chat;
  late final MotionService _motion =
      widget.motion ?? AppServices.of(context).motion;

  FriendStatus? _status;
  String? _loadError;
  final List<ChatLine> _lines = [];
  final List<CharacterFriend?> _lineSpeakers = [];
  late final _conversations = AppServices.of(context).conversations;

  void _recordLine(ChatLine line, {CharacterFriend? speaker}) {
    final who = line.mine ? null : speaker ?? _friend;
    _lines.add(line);
    _lineSpeakers.add(who);
    _conversations
        .append(_friend.id, ConversationEntry(line, speaker: who))
        .catchError((Object error) {
          if (mounted) _tell(failureMessage(error, '이야기를 저장하지 못했어요.'));
        });
  }

  String? _bubble;
  String? _guestBubble;
  bool _guestSpeaking = false;
  bool _chatOpen = false;

  /// Answers the friend is still thinking of (the chat shows dots).
  int _thinking = 0;
  late bool _welcome = widget.celebrate;
  Reaction _reaction = Reaction.none;
  int _reactionId = 0;
  int _request = 0;
  final _timers = <Timer>[];
  late final _company = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
    reverseDuration: const Duration(milliseconds: 800),
  )..addListener(_companyChanged);

  /// The conversation sliding in beside the friend, and the room panning
  /// over to make space for it.
  late final _chatView = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  )..addListener(_companyChanged);
  double _stageSize = 0, _stagePan = 0;
  final _deferredAnswers = <({String text, TalkTopic topic})>[];
  void _companyChanged() {
    if (mounted) setState(() {});
  }

  void _update(VoidCallback action) => setState(action);

  DateTime _now() => (widget.clock ?? DateTime.now)();

  /// The window and bedtime follow the device clock, re-checked every
  /// minute, right at the next bedtime or wake-up, and whenever the app
  /// comes back to the foreground.
  late DayTime _time = dayTimeOf(_now());
  late final Timer _clock;
  Timer? _nextNight;

  /// Laid-out size of the friend's figure and the drawn part of it, for
  /// placing the speech bubble at its head.
  Size? _figure;
  Rect? _art;

  /// Where the friend's head and mouth are and which way it looks: a snack
  /// is held to its mouth and its balloon floats by its head.
  FigureAnchors? _anchors;

  /// The back button and name card at the top left, which a balloon keeps
  /// clear of.
  final _namePlate = GlobalKey();
  final _back = GlobalKey();

  /// Snack time: the tray is open, a snack may be on its way, and the
  /// friend leans toward a snack being dragged (see [LivingCharacter.gaze]).
  bool _snackTray = false;
  Snack? _eating;

  /// A chosen snack waiting for the tray to tuck away before it's eaten.
  Timer? _serve;

  /// Snacks given while another is still being eaten, in order: every one
  /// gets eaten, one after another.
  final _snacks = <_Serving>[];
  _Serving? _meal;
  Snack? _guestEating;
  Timer? _guestServe;
  int _mealNumber = 0;
  static const _trayMotion = Duration(milliseconds: 300);
  final _gaze = ValueNotifier<double?>(null);
  final _guestGaze = ValueNotifier<double?>(null);

  /// A friend invited over: the tray to pick one, the guest itself, and
  /// what the guest and the host are told to act out.
  bool _inviteTray = false;
  List<CharacterFriend> _others = const [];
  CharacterFriend? _guest;
  bool _guestLeaving = false;
  FigureCue? _guestCue;
  FigureCue? _hostCue;
  int _guestPets = 0;
  FriendStatus? _guestStatus;
  bool _guestReady = false, _inviting = false, _socialBusy = false;
  int _visit = 0;
  int _hostIntent = 0, _guestIntent = 0;
  Size? _guestFigure;
  FigureAnchors? _guestAnchors;
  bool get _hasCompany => _guest != null;
  bool get _canGuestAct =>
      _guestReady && !_guestLeaving && _guestStatus?.asleep == false;
  double get _together => Curves.easeInOutSine.transform(_company.value);
  double _hostCenter(double width) => width / 2 - _stageSize * .55 * _together;
  ({double center, double size}) _visitorSpot(double width) =>
      (center: width / 2 + _stageSize * .55, size: _stageSize * .9);

  /// The room's size at the last layout, for how far a guest hops in.
  Size _room = Size.zero;

  /// Clips made from this friend's drawing that are loaded and ready, and
  /// the one playing now. It stands in for the figure once its first frame
  /// is up ([_clipShowing]) and until its last; each play is a fresh player
  /// ([_plays]), so it always starts from the beginning.
  Map<MotionClipKind, LoadedClip> _clips = const {};
  MotionClipKind? _performing;
  bool _clipShowing = false;
  int _plays = 0;

  /// Ends a clip that never finishes on its own (a player that stalls).
  Timer? _performance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock = Timer.periodic(const Duration(minutes: 1), (_) => _checkTime());
    _load();
    _loadWindow();
  }

  /// Whether the page has finished coming in (from the archive, the friend
  /// hops off its card onto the rug): the balloon and the hello wait till
  /// then.
  bool _landed = false;
  bool _helloAfterLanding = false;
  Animation<double>? _arrival;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final arrival = ModalRoute.of(context)?.animation;
    if (identical(arrival, _arrival)) return;
    _arrival?.removeStatusListener(_onArrival);
    _arrival = arrival;
    // The page is first built off stage (for measuring heroes) with its
    // animation standing in as finished; the same animation then switches
    // to the real one, so follow its status rather than the first look.
    _landed = arrival == null || arrival.isCompleted;
    arrival?.addStatusListener(_onArrival);
  }

  void _onArrival(AnimationStatus status) {
    // Leaving (reverse) changes nothing here: the house folds away round
    // its friend, balloon and all, without a rebuild.
    if (status == AnimationStatus.reverse) return;
    final landed = status == AnimationStatus.completed;
    if (landed == _landed || !mounted) return;
    if (!landed) {
      setState(() => _landed = false);
      return;
    }
    // A breath after touching down, so the frame the friend lands on is
    // spent on the landing alone, not on the balloon popping up too.
    _timers.add(Timer(const Duration(milliseconds: 180), _land));
  }

  void _land() {
    if (!mounted || _landed || _arrival?.isCompleted != true) return;
    setState(() => _landed = true);
    if (_helloAfterLanding) {
      _helloAfterLanding = false;
      _sayHello();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkTime();
      if (_status != null) _loadHistory(_request);
    }
  }

  void _checkTime() {
    if (!mounted) return;
    final now = dayTimeOf(_now());
    if (now != _time) setState(() => _time = now);
    _followSchedule();
    if (_guest case final guest?) {
      if (guest.sleep.asleepAt(_now())) _seeGuestOff();
    }
  }

  /// Falls asleep at bedtime and wakes at its wake-up time, by itself.
  void _followSchedule() {
    final status = _status;
    if (status == null || !mounted) return;
    final now = _now();
    _nextNight?.cancel();
    _nextNight = Timer(
      _friend.sleep.nextChange(now).difference(now) +
          const Duration(seconds: 1),
      _checkTime,
    );
    final asleep = _friend.sleep.asleepAt(now);
    if (asleep == status.asleep) return;
    if (asleep) {
      // Bedtime: a guest heads home first.
      _seeGuestOff(saying: false);
      _cancelMeals();
      _care(status.copyWith(asleep: true), TalkTopic.sleep, Reaction.none);
      setState(() {
        _snackTray = false;
        _inviteTray = false;
      });
    } else {
      _care(
        status.copyWith(
          asleep: false,
          energy: math.max(status.energy, 90),
          mood: status.mood + 5,
        ),
        TalkTopic.wake,
        Reaction.none,
      );
    }
  }

  Future<void> _editSleep() async {
    final schedule = await showSleepSchedule(context, _friend);
    if (schedule == null || !mounted || schedule == _friend.sleep) return;
    final before = _friend;
    final friend = _friend.copyWith(sleep: schedule);
    setState(() => _friend = friend);
    try {
      await widget.repository.saveFriend(friend);
    } catch (error) {
      if (!mounted) return;
      setState(() => _friend = before);
      _tell(failureMessage(error, '잠자는 시간을 바꾸지 못했어요.'));
      return;
    }
    _followSchedule();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _arrival?.removeStatusListener(_onArrival);
    _clock.cancel();
    _nextNight?.cancel();
    _gaze.dispose();
    _guestGaze.dispose();
    _company.dispose();
    _chatView.dispose();
    _performance?.cancel();
    _serve?.cancel();
    _guestServe?.cancel();
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  WindowView? _window;
  bool _windowBusy = false;

  /// The service is still making the scenery: say so over the default view.
  bool _windowWaiting = false;
  String? _windowError;

  Future<void> _loadWindow({bool regenerate = false}) async {
    final service = AppServices.of(context).windowViews;
    if (_windowBusy || service == null || !service.supports(_friend)) return;
    setState(() {
      _windowBusy = true;
      _windowError = null;
    });
    try {
      final view = await service.load(
        _friend,
        regenerate: regenerate,
        active: () => mounted,
        onWaiting: () {
          if (mounted) setState(() => _windowWaiting = true);
        },
      );
      if (mounted && view != null) setState(() => _window = view);
    } catch (error) {
      if (mounted) {
        setState(() => _windowError = failureMessage(error, '배경을 만들지 못했어요.'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _windowBusy = false;
          _windowWaiting = false;
        });
      }
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    _loadClips(request);
    final asset = _friend.assetPath;
    artBounds(asset).then((art) {
      if (mounted && asset == _friend.assetPath) setState(() => _art = art);
    });
    anchorsFor(asset).then((anchors) {
      if (mounted && asset == _friend.assetPath) {
        setState(() => _anchors = anchors);
      }
    });
    final FriendStatus fetched;
    try {
      fetched = await widget.repository.fetchStatus(_friend.id);
    } catch (error) {
      if (!mounted || request != _request) return;
      final message = failureMessage(error, '잠시 후 다시 시도해 주세요.');
      if (_status == null) {
        setState(() => _loadError = message);
      } else {
        _tell(message);
      }
      return;
    }
    if (!mounted || request != _request) return;
    // Whatever time it is now, it's already in bed or up.
    final asleep = _friend.sleep.asleepAt(_now());
    final status = asleep == fetched.asleep
        ? fetched
        : fetched.copyWith(
            asleep: asleep,
            energy: asleep ? null : math.max(fetched.energy, 90),
          );
    if (!identical(status, fetched)) {
      _saveStatus(status);
    }
    List<ConversationEntry> history = const [];
    try {
      history = await _conversations.read(_friend.id);
    } catch (error) {
      if (mounted) _tell(failureMessage(error, '이전 이야기를 읽지 못했어요.'));
    }
    if (!mounted || request != _request) return;
    setState(() {
      _loadError = null;
      _status = status;
      _lines
        ..clear()
        ..addAll(history.map((item) => item.line));
      _lineSpeakers
        ..clear()
        ..addAll(history.map((item) => item.speaker));
      _bubble = status.asleep
          ? _talk.say(TalkTopic.asleep)
          : _talk.say(TalkTopic.greet);
      _recordLine((mine: false, text: _bubble!));
    });
    _followSchedule();
    _loadHistory(request);
    if (!status.asleep && !_welcome) _sayHello();
    // The balloon keeps clear of the cards, which are only measured once
    // laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  /// Coming in, the friend waves hello as the greeting pops up — just after
  /// the page has slid in, so the wave isn't missed.
  void _sayHello() {
    // Not while it is still flying in from its card.
    if (!_landed) {
      _helloAfterLanding = true;
      return;
    }
    final friend = _friend.id;
    _timers.add(
      Timer(const Duration(milliseconds: 420), () {
        if (!mounted || _friend.id != friend || _status?.asleep != false) {
          return;
        }
        if (!_landed) {
          _helloAfterLanding = true;
          return;
        }
        setState(() => _hostCue = FigureCue(Act.wave));
      }),
    );
  }

  /// Fetches the friend's clips in the background and keeps the ones that
  /// load; until then (or if its drawing can't be animated) the built-in
  /// motions are all there is.
  Future<void> _loadClips(int request) async {
    final Map<MotionClipKind, MotionClip>? clips;
    try {
      clips = await _motion.clipsFor(_friend);
    } catch (_) {
      return; // no clips: the built-in motions
    }
    if (clips == null || clips.isEmpty || !mounted) return;
    final ready = <MotionClipKind, LoadedClip>{};
    for (final MapEntry(key: kind, value: clip) in clips.entries) {
      // Kept on the iPad once fetched, else still on the service.
      if (await LoadedClip.load(clip.url) case final loaded?) {
        ready[kind] = loaded;
      }
    }
    if (mounted && request == _request) setState(() => _clips = ready);
  }

  /// Plays a clip if this friend has it and nothing else needs the figure
  /// (a snack at its mouth, another clip); the built-in [reaction]
  /// otherwise. Call inside setState.
  /// Whether the clip plays.
  bool _perform(MotionClipKind kind, Reaction reaction) {
    final clip = _clips[kind];
    if (clip == null ||
        _performing != null ||
        _eating != null ||
        _serve != null ||
        MediaQuery.disableAnimationsOf(context)) {
      _react(reaction);
      return false;
    }
    _performance?.cancel();
    _performing = kind;
    _clipShowing = false;
    _plays++;
    final play = _plays;
    _performance = Timer(clip.length + const Duration(seconds: 2), () {
      if (mounted && _plays == play) setState(_stopClip);
    });
    return true;
  }

  /// The clip's first frame is up: it takes the figure's place.
  void _clipStarted(int play) {
    if (!mounted || play != _plays || _performing == null) return;
    setState(() => _clipShowing = true);
  }

  /// The clip played to its end (or couldn't play): the figure is back.
  void _clipDone(int play) {
    if (!mounted || play != _plays) return;
    setState(_stopClip);
  }

  /// Ends any clip at once. Call inside setState.
  void _stopClip() {
    _performance?.cancel();
    _performance = null;
    _performing = null;
    _clipShowing = false;
  }

  void _react(Reaction r) {
    _reaction = r;
    _reactionId++;
  }

  /// Applies care, saves it, and lets the friend answer.
  /// [line] is what the friend says; without one, a line of its own about
  /// [topic].
  void _care(
    FriendStatus next,
    TalkTopic topic,
    Reaction reaction, {
    String? line,
  }) {
    final said = line ?? _talk.say(topic);
    setState(() {
      _status = next.copyWith(updatedAt: DateTime.now());
      _bubble = said;
      _guestSpeaking = false;
      _recordLine((mine: false, text: said));
      _react(reaction);
    });
    _saveStatus(_status!);
  }

  void _pet() {
    final s = _status;
    if (s == null) return;
    if (s.asleep) {
      setState(() => _bubble = _talk.say(TalkTopic.asleep));
      return;
    }
    if (_meal != null || (_hasCompany && !_guestReady)) return;
    _hostIntent++;
    _care(
      s.copyWith(mood: s.mood + 3, closeness: s.closeness + 1),
      TalkTopic.pet,
      Reaction.hearts,
    );
    // 터치 동작을 손 흔들기 클립으로 덮지 않는다.
    setState(_stopClip);
    _respondTogether(false, Act.giggle);
  }

  Future<void> _send(String text, TalkTopic? topic) async {
    if (_status == null ||
        _status!.asleep ||
        _thinking > 0 ||
        _deferredAnswers.isNotEmpty ||
        text.trim().isEmpty) {
      return;
    }
    setState(() => _recordLine((mine: true, text: text)));
    final t = topic ?? _talk.topicFor(text);
    _answer(text, t);
    // Every chat is a memory; enough memories and the friend grows.
    try {
      await widget.repository.addMemory(_friend.id, text);
    } catch (error) {
      if (mounted) _tell(failureMessage(error, '이야기를 추억으로 저장하지 못했어요.'));
      return;
    }
    if (!mounted) return;
    final memories = _friend.memories + 1;
    final grown = _friend.copyWith(
      memories: memories,
      level: _friend.level + (memories % _memoriesPerLevel == 0 ? 1 : 0),
    );
    try {
      await widget.repository.saveFriend(grown);
    } catch (_) {
      // Growing is the house's own business: it still shows, and saves
      // with the next change.
    }
    if (!mounted) return;
    setState(() => _friend = grown);
  }

  static const _memoriesPerLevel = 5;

  /// The chat from earlier visits goes above today's greeting.
  bool _loadingHistory = false;
  Future<void> _loadHistory(int request) async {
    if (_loadingHistory || _chat is LocalChatService) return;
    _loadingHistory = true;
    final friend = _friend.id;
    try {
      final chat = _chat;
      if (chat is ServerChatHistory) {
        final past = await (chat as ServerChatHistory).historyEntries(_friend);
        if (!mounted || request != _request || _friend.id != friend) return;
        await _conversations.mergeServer(_friend, past);
      } else {
        if (!await _conversations.needsServerHistory(friend)) return;
        final past = await _chat.history(_friend);
        if (!mounted || request != _request || _friend.id != friend) return;
        await _conversations.prepend(friend, [
          for (final line in past)
            ConversationEntry(line, speaker: line.mine ? null : _friend),
        ]);
      }
      final combined = await _conversations.read(friend);
      if (!mounted || request != _request || _friend.id != friend) return;
      setState(() {
        _lines
          ..clear()
          ..addAll(combined.map((e) => e.line));
        _lineSpeakers
          ..clear()
          ..addAll(combined.map((e) => e.speaker));
      });
    } catch (_) {
      // Keep the pending flag: next room visit or app resume retries.
    } finally {
      _loadingHistory = false;
    }
  }

  /// The friend thinks a moment, then answers: through the chat service,
  /// or with a line of its own when that has nothing to say.
  Future<void> _answer(String text, TalkTopic topic) async {
    final friend = _friend.id;
    final pause = Future<void>.delayed(const Duration(milliseconds: 450));
    setState(() => _thinking++);
    String? reply;
    try {
      reply = await _chat.replyTo(_friend, text);
    } on ApiException catch (error) {
      if (mounted) {
        _tell(
          error.statusCode == 429
              ? '지금은 기기 안의 대사로 대화하고 있어요. 잠시 후 다시 이야기해 주세요.'
              : '서버 연결이 어려워 기기 안의 대사로 답할게요.',
        );
      }
    } catch (_) {
      // Offline or failed: the friend answers itself.
    }
    reply ??= _talk.careReply(text);
    await pause;
    if (!mounted) return;
    setState(() => _thinking = math.max(0, _thinking - 1));
    if (_friend.id != friend) return;
    final s = _status;
    if (s == null || s.asleep) return;
    final said = reply ?? _talk.say(topic);
    if (_meal != null) {
      _deferredAnswers.add((text: said, topic: topic));
      return;
    }
    _showAnswer(said, topic);
  }

  void _showAnswer(String reply, TalkTopic topic) {
    final s = _status;
    if (s == null || s.asleep) return;
    _care(
      s.copyWith(mood: s.mood + 3, closeness: s.closeness + 2),
      topic,
      topic == TalkTopic.love ? Reaction.hearts : Reaction.none,
      line: reply,
    );
    _actOut(topic);
  }

  /// The friend acts out what was said: "같이 놀자!" gets a dance (its own
  /// dance clip if it has one), "오늘 뭐 했어?" a think and "뭘 좋아해?" a
  /// happy bounce. Not while asleep or eating.
  void _actOut(TalkTopic topic) {
    if (_status?.asleep ?? true) return;
    if (_eating != null || _serve != null) return;
    if (_chatOpen) {
      setState(
        () => _hostCue = FigureCue(
          topic == TalkTopic.love ? Act.shy : Act.wonder,
        ),
      );
      return;
    }
    final act = switch (topic) {
      TalkTopic.play => Act.dance,
      TalkTopic.today => Act.wonder,
      TalkTopic.likes => Act.bounce,
      _ => null,
    };
    if (act == null) return;
    setState(() {
      final danced =
          act == Act.dance && _perform(MotionClipKind.dance, Reaction.none);
      if (!danced) _hostCue = FigureCue(act);
    });
  }

  /// How the friend feels now, from its care and the clock: it is sleepy
  /// when tired or near bedtime, hungry when its tummy is empty, cheerful
  /// when its mood is high. What it does by itself follows (see [Vibe]).
  Vibe get _vibe {
    final s = _status;
    if (s == null || s.asleep) return Vibe.calm;
    final now = _now();
    final minute = now.hour * 60 + now.minute;
    final toBed = (_friend.sleep.bedtime - minute) % (24 * 60);
    if (s.energy < 30 || toBed <= 45) return Vibe.sleepy;
    if (s.fullness < 30) return Vibe.hungry;
    if (s.mood >= 75) return Vibe.cheerful;
    return Vibe.calm;
  }

  @override
  Widget build(BuildContext context) => withBogleBodyFont(
    context,
    font: bogleUiFont,
    ScaffoldMessenger(
      key: _messages,
      child: PopScope(
        canPop: !_chatOpen,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _chatOpen) _closeChat();
        },
        child: Scaffold(
          // The house keeps its size under the keyboard; the chat makes room
          // for it itself (see [_house]).
          resizeToAvoidBottomInset: false,
          body: AnimatedSwitcher(
            duration: Duration(
              milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 350,
            ),
            child: KeyedSubtree(key: ValueKey(_friend.id), child: _house()),
          ),
        ),
      ),
    ),
  );

  final _messages = GlobalKey<ScaffoldMessengerState>();

  void _openChat() {
    setState(() {
      _chatOpen = true;
      _snackTray = false;
      _inviteTray = false;
    });
    _slideChat();
  }

  void _closeChat() {
    FocusScope.of(context).unfocus();
    setState(() => _chatOpen = false);
    _slideChat();
  }

  void _slideChat() => _chatView.animateTo(
    _chatOpen ? 1 : 0,
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 380),
    curve: Curves.easeInOutCubic,
  );

  /// A short note at the bottom of the house (something didn't save).
  void _tell(String message) => _messages.currentState
    ?..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _saveStatus(FriendStatus status) async {
    try {
      await widget.repository.saveStatus(_friend.id, status);
    } catch (error) {
      if (mounted) _tell(failureMessage(error, '친구의 돌봄 기록을 저장하지 못했어요.'));
    }
  }

  Widget _house() {
    final status = _status;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        _room = box.biggest;
        final room = RoomLayout(_room);
        final scale = room.s;
        final media = MediaQuery.of(context);
        final top = AppTopBar.bottomFor(media) + 32 * scale;
        final keyboard = _chatOpen ? media.viewInsets.bottom : 0.0;
        // The conversation stands tall on the right and the room pans left
        // to keep the friend, rug and all, in the middle of what is left.
        // Too narrow for both (a split screen), the card has the width.
        final chat = _chatView.value;
        final narrow = w < 900;
        final margin = narrow ? 16.0 : 24.0;
        final panelWidth = narrow
            ? w - 2 * margin
            : (w * .44).clamp(440.0, 600.0);
        final panX = narrow ? 0.0 : (panelWidth + margin) / 2 * chat;
        final factor = keyboard > 0
            ? ((h - keyboard) / 600).clamp(.58, .9)
            : 1.0;
        _stageSize = room.host * factor;
        // With the keyboard up the room rises till the friend's feet clear it.
        final pan = keyboard > 0
            ? math.max(0.0, room.feet - (h - keyboard - 16))
            : 0.0;
        _stagePan = pan;
        return Stack(
          children: [
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(0, -pan),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: _stage(status, room, w, h, top, pan, panX),
                ),
              ),
            ),
            if (status != null && (_chatOpen || chat > 0))
              Positioned(
                top: keyboard > 0 ? media.padding.top + 16 : top,
                bottom: keyboard > 0
                    ? keyboard + 16
                    : media.padding.bottom + margin,
                right: margin,
                width: panelWidth,
                child: IgnorePointer(
                  ignoring: !_chatOpen,
                  child: Opacity(
                    opacity: chat,
                    child: Transform.translate(
                      offset: Offset((1 - chat) * panelWidth * .3, 0),
                      child: ChatPanel(
                        key: const ValueKey('chat'),
                        friend: _friend,
                        lines: _lines,
                        speakers: _lineSpeakers,
                        enabled: !status.asleep,
                        thinking: _thinking > 0 || _deferredAnswers.isNotEmpty,
                        onSend: _send,
                        onClose: _closeChat,
                      ),
                    ),
                  ),
                ),
              ),
            if (_welcome)
              _Welcome(
                friend: _friend,
                onEnter: () {
                  setState(() => _welcome = false);
                  if (_status?.asleep == false) _sayHello();
                },
              ),
          ],
        );
      },
    );
  }

  /// The room and everything in it but the chat: it pans up as one while
  /// the child types. The room itself and whoever is in it also pan [panX]
  /// to the left, out of the conversation's way; the header, back button
  /// and tiles stay put.
  List<Widget> _stage(
    FriendStatus? status,
    RoomLayout room,
    double w,
    double h,
    double top,
    double pan,
    double panX,
  ) {
    // Panned up for the keyboard, the header and back button slip off the
    // top: they fade on the way rather than hang half cut.
    final chrome = (1 - pan / (40 * room.s)).clamp(0.0, 1.0);
    final size = _stageSize;
    final feet = h - room.feet;
    final scale = room.s;
    final id = _friend.id;
    final cast = [
      Positioned.fill(
        child: RoomScene(
          view: _window ?? WindowView.forFriend(_friend),
          time: _time,
          lightsOff: status?.asleep ?? false,
          company: _together,
          bottomOverflow: pan,
          rightOverflow: panX,
        ),
      ),
      Positioned(
        left: _hostCenter(w) - size / 2,
        bottom: feet,
        width: size,
        height: size,
        // There from the first frame, so it can hop in from its card
        // (a hero needs somewhere to land); until its status is read
        // it sleeps or wakes by its bedtime.
        // Hidden while a clip stands in for it, but still there: it
        // keeps living, and a snack dropped or a pat while a clip
        // plays still reaches the friend (eating ends the clip).
        child: Opacity(
          key: const ValueKey('house-figure'),
          opacity: _clipShowing ? 0 : 1,
          child: DragTarget<Snack>(
            onWillAcceptWithDetails: (_) =>
                _status?.asleep == false && (!_hasCompany || _canGuestAct),
            onAcceptWithDetails: (d) => _feed(d.data, recipient: _friend.id),
            builder: (context, _, _) => LivingCharacter(
              friend: _friend,
              asleep: status?.asleep ?? _friend.sleep.asleepAt(_now()),
              reaction: _reaction,
              reactionId: _reactionId,
              onTap: _pet,
              size: size,
              gaze: _gaze,
              cue: _hostCue,
              vibe: _vibe,
              attentive: _chatOpen || _meal != null,
              onIdleAct: (act) => _respondTogether(false, act),
              onFigureSize: (figure) {
                if (id == _friend.id && figure != _figure) {
                  setState(() => _figure = figure);
                }
              },
            ),
          ),
        ),
      ),
      if (_canGuestAct)
        Positioned(
          key: const ValueKey('shared-snack-target'),
          left: w / 2 - 30,
          bottom: feet,
          width: 60,
          height: size * .45,
          child: DragTarget<Snack>(
            onWillAcceptWithDetails: (_) => true,
            onAcceptWithDetails: (drop) => _feed(drop.data),
            builder: (context, candidate, rejected) => candidate.isEmpty
                ? const SizedBox.expand()
                : Center(
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: BogleColors.cream,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '같이 먹기',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
          ),
        ),
      if ((_guest, status) case (final guest?, final status?))
        _guestAt(guest, status, w, feet),
      if (_eating case final snack?) ?_eatingAt(snack, w, h, feet),
      if (_guestEating case final snack?)
        ?_eatingAt(snack, w, h, feet, guest: true),
      if (_performing case final kind?) ?_clipAt(kind, w, h, feet),
      // In conversation the words are in the chat card instead.
      if ((_bubble != null || _guestBubble != null || _thinking > 0) &&
          !_welcome &&
          !_chatOpen &&
          _landed)
        ?_speech(w, h, feet),
    ];
    return [
      Positioned.fill(
        child: Transform.translate(
          offset: Offset(-panX, 0),
          child: Stack(clipBehavior: Clip.none, children: cast),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        top: 0,
        child: _fading(
          chrome,
          AppTopBar(
            key: const ValueKey('house-header'),
            repository: widget.repository,
            title: 'Home',
          ),
        ),
      ),
      Positioned(
        left: 59 * room.sx,
        top: top,
        child: _fading(
          chrome,
          BogleBackButton(
            key: _back,
            inkKey: const ValueKey('house-back'),
            size: 68 * scale,
            onTap: () => Navigator.maybePop(context),
          ),
        ),
      ),
      if (_windowWaiting && _window == null && !_chatOpen)
        Positioned(
          left: room.window.left,
          width: room.window.width,
          top: room.window.top + 30 * scale,
          child: Center(
            child: WindowPendingNotice(
              key: const ValueKey('house-window-pending'),
              scale: scale,
            ),
          ),
        ),
      if (!_chatOpen &&
          AppServices.of(context).windowViews?.supports(_friend) == true)
        Positioned(
          right: 32 * room.sx,
          top: top,
          child: IconButton.filledTonal(
            key: const ValueKey('house-window-action'),
            tooltip: _windowBusy
                ? '배경을 만들고 있어요'
                : _windowError != null
                ? '배경 만들기 다시 시도'
                : '창밖 배경 새로 만들기',
            onPressed: _windowBusy
                ? null
                : () async {
                    if (_window != null) {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('창밖 풍경을 새로 그릴까요?'),
                          content: const Text('새 풍경이 완성될 때까지 지금 풍경을 유지해요.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('취소'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('새로 만들기'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true || !mounted) return;
                    }
                    await _loadWindow(regenerate: true);
                    if (mounted && _windowError != null) _tell(_windowError!);
                  },
            icon: _windowBusy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _windowError == null
                        ? Icons.landscape_outlined
                        : Icons.refresh,
                  ),
          ),
        ),
      if (!_chatOpen)
        Positioned(
          left: 54 * room.sx,
          top: top + 100 * scale,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: NamePlate(
              key: _namePlate,
              friend: _friend,
              status: status,
              onEditSleep: _editSleep,
            ),
          ),
        ),
      // In conversation the tiles make way: the chat card closes itself.
      if (!_chatOpen)
        Positioned(
          left: 0,
          right: 0,
          bottom: 40 * scale - pan,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _traySlot(switch (status) {
                  final s? when _snackTray && !s.asleep => Padding(
                    key: const ValueKey('snack-tray'),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Center(
                      child: SnackTray(
                        friend: _friend,
                        together: _canGuestAct,
                        onGive: _feed,
                        onDrag: (at) => _dragSnack(at, w),
                        onClose: () => setState(() => _snackTray = false),
                      ),
                    ),
                  ),
                  final s? when _inviteTray && !s.asleep => Padding(
                    key: const ValueKey('invite-tray'),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Center(
                      child: InviteTray(
                        friends: _others,
                        onInvite: _invite,
                        onClose: () => setState(() => _inviteTray = false),
                      ),
                    ),
                  ),
                  _ => null,
                }),
                if (status != null)
                  Center(child: _actions(status, scale))
                else
                  Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 480),
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.all(20),
                      decoration: houseCard(),
                      child: _loadError == null
                          ? const Center(
                              child: CircularProgressIndicator(
                                semanticsLabel: '친구의 집 불러오는 중',
                              ),
                            )
                          : ProfileEmptyState(
                              icon: Icons.cloud_off_rounded,
                              title: '친구의 집을 불러오지 못했어요',
                              message: _loadError!,
                              action: '다시 불러오기',
                              onPressed: () {
                                setState(() => _loadError = null);
                                _load();
                              },
                            ),
                    ),
                  ),
              ],
            ),
          ),
        ),
    ];
  }

  /// [child] at [opacity], out of reach once it has faded out. At full
  /// opacity it is left as it is.
  static Widget _fading(double opacity, Widget child) => opacity >= 1
      ? child
      : IgnorePointer(
          ignoring: opacity < .5,
          child: Opacity(opacity: opacity, child: child),
        );

  /// Figma's three tiles (568:2335): 대화하기, 간식주기 and 초대하기, whose
  /// icon is the host's own silhouette. With a guest over it turns into
  /// 배웅하기 (not designed yet): the guest's silhouette heading off.
  Widget _actions(FriendStatus status, double scale) {
    Widget svg(String name, double w, double h) => SvgPicture.asset(
      'assets/figma/$name.svg',
      width: w * scale,
      height: h * scale,
      excludeFromSemantics: true,
    );
    // Figma 621:2043, and its 48 × 26 icon 2 pt below the middle; a taller
    // friend gets up to 40 pt of height.
    const inviteTint = Color(0xFFD9EEDF);
    final host = Transform.translate(
      offset: Offset(0, 2 * scale),
      child: FriendSilhouette(
        assetPath: _friend.assetPath,
        size: Size(48.0925 * scale, 40 * scale),
      ),
    );
    Widget leaving(CharacterFriend guest) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        svg('house_speed_lines', 10, 26),
        SizedBox(width: 2 * scale),
        FriendSilhouette(
          assetPath: guest.assetPath,
          size: Size(36 * scale, 34 * scale),
        ),
      ],
    );
    return ActionTiles(
      scale: scale,
      actions: [
        HouseAction(
          icon: svg('house_chat', 31.207, 30.166),
          label: '대화하기',
          tint: const Color(0xFFE4E6F5),
          onTap: _openChat,
        ),
        HouseAction(
          icon: svg('house_cookie', 36, 36),
          label: _snackTray ? '간식 닫기' : '간식주기',
          tint: const Color(0xFFFDE6D3),
          onTap: status.asleep ? null : _openSnacks,
        ),
        if (_guest case final guest?)
          HouseAction(
            icon: leaving(guest),
            label: '배웅하기',
            tint: inviteTint,
            onTap: _guestLeaving ? null : _seeGuestOff,
          )
        else
          HouseAction(
            icon: host,
            label: _inviteTray ? '초대 닫기' : '초대하기',
            tint: inviteTint,
            onTap: status.asleep ? null : _openInvites,
          ),
      ],
    );
  }
}
