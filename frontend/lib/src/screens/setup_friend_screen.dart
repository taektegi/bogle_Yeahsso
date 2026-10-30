import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../data/app_services.dart';
import '../data/character_repository.dart';
import '../data/korean.dart';
import '../data/character_generation.dart';
import '../data/failures.dart';
import '../data/friend_profile_choices.dart';
import '../data/speech_style.dart';
import '../widgets/speech_style_picker.dart';
import '../data/friend_creation_messages.dart';
import '../models/character_friend.dart';
import '../theme/bogle_theme.dart';
import '../theme/bogle_viewport.dart';
import '../widgets/bogle_widgets.dart';
import '../widgets/fireworks.dart';
import '../widgets/top_bar.dart';
import '../widgets/friend_arrival.dart';
import 'archive_screen.dart';
import 'friend_screen.dart';
import 'house/house_widgets.dart';
import '../app_lifecycle.dart';

part 'setup/setup_controls.dart';

/// Listens for one short spoken answer. Swappable so tests need no
/// microphone.
abstract interface class VoiceInput {
  /// Starts listening; false when speech recognition is unavailable or
  /// was not allowed. [onWords] gets the words heard so far.
  Future<bool> start(ValueChanged<String> onWords, VoidCallback onDone);
  Future<void> stop();
}

/// On-device Korean dictation (iOS Speech framework).
class DeviceVoiceInput implements VoiceInput {
  final _speech = SpeechToText();
  VoidCallback? _onDone;

  @override
  Future<bool> start(ValueChanged<String> onWords, VoidCallback onDone) async {
    _onDone = onDone;
    try {
      final ready = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') _finish();
        },
        onError: (_) => _finish(),
      );
      if (!ready) return false;
      await _speech.listen(
        onResult: (result) => onWords(result.recognizedWords),
        listenOptions: SpeechListenOptions(
          localeId: 'ko_KR',
          listenFor: const Duration(seconds: 20),
          pauseFor: const Duration(seconds: 3),
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  void _finish() {
    final done = _onDone;
    _onDone = null;
    done?.call();
  }

  @override
  Future<void> stop() async {
    try {
      await _speech.stop();
    } catch (_) {}
    _finish();
  }
}

enum _Step { arrive, name, personality, favorites, speech, friend }

enum _Input { choose, voice, text }

/// Figma "캐릭터 수정" and "친구됨": the new friend arrives between
/// parting clouds, the child names it (by voice or by typing), then picks
/// its personality, favourite things and 말투 from a few answers each
/// (다음 to go on, ← to change an answer), and it greets them in the voice
/// they chose.
class SetupFriendScreen extends StatefulWidget {
  const SetupFriendScreen({
    super.key,
    required this.repository,
    required this.art,
    this.voice,
    this.input,
  });

  final CharacterRepository repository;

  /// The new friend's artwork and colour, from the generator.
  final GeneratedArt art;
  final GenerationInput? input;

  /// Defaults to on-device dictation.
  final VoiceInput? voice;

  @override
  State<SetupFriendScreen> createState() => _SetupFriendScreenState();
}

class _SetupFriendScreenState extends State<SetupFriendScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// The artwork's shape in solid cream: cream colour, and any part at
  /// least a quarter opaque made fully opaque.
  static final _solidCream = ColorFilter.matrix([
    0,
    0,
    0,
    0,
    (BogleColors.cream.r * 255).roundToDouble(),
    0,
    0,
    0,
    0,
    (BogleColors.cream.g * 255).roundToDouble(),
    0,
    0,
    0,
    0,
    (BogleColors.cream.b * 255).roundToDouble(),
    0,
    0,
    0,
    4,
    0,
  ]);

  late final VoiceInput _voice = widget.voice ?? DeviceVoiceInput();
  final _text = TextEditingController();
  final _textFocus = FocusNode();
  final _messages = GlobalKey<ScaffoldMessengerState>();

  _Step _step = _Step.arrive;
  _Input _input = _Input.choose;
  bool _listening = false;
  String _name = '';
  String? _personality;
  final Set<FavoriteChoice> _favorites = {};
  String? _speech;

  /// 친구됨: which greeting line is showing; past the last one, the
  /// friend steps up and the way home appears.
  int _line = 0;
  // Select once per creation screen, never during a rebuild or animation tick.
  late final String _creationMessage =
      friendCreationMessages[math.Random().nextInt(
        friendCreationMessages.length,
      )];
  CharacterFriend? _friend;
  late final AnimationController _arrival;

  /// Once the friend has arrived, a moment to take it in before the first
  /// question comes by itself.
  Timer? _onward;
  static const _arrivalPause = Duration(milliseconds: 1400);

  /// For the farewell's party poppers: the bouquets cross behind the
  /// friend, and the cannons stay beside the two buttons.
  final _friendArt = GlobalKey(debugLabel: 'setup-friend-art');
  final _farewellButtons = GlobalKey(debugLabel: 'setup-farewell-buttons');
  bool _foreground = true;

  /// Where the friend's head is in its drawing, for trying out 말투 in a
  /// balloon over it; with the drawing's size, read once.
  FigureAnchors? _anchors;
  ArtLook? _look;

  @override
  void initState() {
    super.initState();
    _arrival =
        AnimationController(vsync: this, duration: FriendArrival.duration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) _scheduleOnward();
          });
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = onScreen(state);
    final art = widget.art.assetPath;
    Future.wait([anchorsFor(art), artLookOf(art)]).then((read) {
      if (!mounted) return;
      setState(() {
        _anchors = read[0] as FigureAnchors;
        _look = read[1] as ArtLook?;
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncArrival();
  }

  void _syncArrival() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _arrival.stop();
      _arrival.value = 1;
    } else if (_foreground && TickerMode.valuesOf(context).enabled) {
      if (!_arrival.isAnimating && !_arrival.isCompleted) _arrival.forward();
    } else {
      _arrival.stop();
    }
  }

  /// While the friend arrives, a tap anywhere below the top bar goes on
  /// to the name question straight away (finishing the arrival first).
  /// Always in the tree (only listening while arriving), so moving on
  /// keeps the page's widgets and their transitions.
  Widget _tapOnward(Widget child) {
    final arriving = _step == _Step.arrive;
    return Semantics(
      button: arriving,
      label: arriving ? '눌러서 다음으로' : null,
      child: GestureDetector(
        key: const ValueKey('arrival-tap'),
        behavior: arriving
            ? HitTestBehavior.opaque
            : HitTestBehavior.deferToChild,
        onTap: arriving ? _skipArrival : null,
        child: child,
      ),
    );
  }

  void _skipArrival() {
    // Finishing the arrival would schedule the pause; cancel it after.
    if (!_arrival.isCompleted) _arrival.value = 1;
    _onward?.cancel();
    _onward = null;
    _next();
  }

  /// Moves on to the name question after [_arrivalPause], counted only
  /// while the app is in front.
  void _scheduleOnward() {
    if (_onward != null || _step != _Step.arrive || !_foreground) return;
    _onward = Timer(_arrivalPause, () {
      _onward = null;
      if (mounted && _step == _Step.arrive) _next();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = onScreen(state);
    _syncArrival();
    if (!_foreground) {
      _onward?.cancel();
      _onward = null;
    } else if (_arrival.isCompleted) {
      _scheduleOnward();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _onward?.cancel();
    _arrival.dispose();
    if (_listening) _voice.stop();
    _text.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  // ---- Answers ---------------------------------------------------------

  /// The typed or spoken answer: only the name is told rather than chosen.
  String get _answer => _step == _Step.name ? _name : '';

  void _setAnswer(String value) => setState(() {
    if (_step == _Step.name) _name = value;
  });

  bool get _canGoOn => switch (_step) {
    _Step.arrive => _arrival.isCompleted,
    _Step.name => _name.trim().isNotEmpty,
    _Step.personality => _personality != null,
    _Step.favorites => _favorites.isNotEmpty,
    _Step.speech => _speech != null,
    _Step.friend => true,
  };

  /// The favourite things as chosen, in the list's order.
  List<FavoriteChoice> get _favoriteList =>
      favoriteChoices.where(_favorites.contains).toList();

  /// Up to [maxFavorites]; another can be picked once one is let go.
  void _toggleFavorite(FavoriteChoice item) => setState(() {
    if (!_favorites.remove(item) && _favorites.length < maxFavorites) {
      _favorites.add(item);
    }
  });

  /// Back to the question before, keeping every answer.
  Future<void> _back() async {
    if (_saving || _step.index <= _Step.name.index) return;
    await _stopListening();
    if (!mounted) return;
    setState(() {
      _step = _Step.values[_step.index - 1];
      _input = _Input.choose;
      _text.text = _answer;
    });
  }

  /// Saving the new friend (the service may take a few seconds: it writes
  /// the friend's introduction first).
  bool _saving = false;

  Future<void> _next() async {
    if (!_canGoOn || _saving) return;
    await _stopListening();
    if (!mounted) return;
    if (_step == _Step.speech) return _befriend();
    setState(() {
      _step = _Step.values[_step.index + 1];
      _input = _Input.choose;
      _text.text = _answer;
    });
  }

  void _typeInstead() {
    _stopListening();
    setState(() {
      _input = _Input.text;
      _text.text = _answer;
    });
    // Attach the newly built field before asking iOS for its input session.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _step == _Step.name && _input == _Input.text) {
        _textFocus.requestFocus();
      }
    });
  }

  Future<void> _speakInstead() async {
    _textFocus.unfocus();
    setState(() => _input = _Input.voice);
  }

  Future<void> _toggleListening() async {
    if (_listening) return _stopListening();
    setState(() => _listening = true);
    final ok = await _voice.start(
      (words) {
        if (mounted && words.isNotEmpty) _setAnswer(words.trim());
      },
      () {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (ok || !mounted) return;
    setState(() => _listening = false);
    _messages.currentState?.showSnackBar(
      const SnackBar(content: Text('여기서는 말로 알려줄 수 없어요. 글자로 적어 주세요.')),
    );
    _typeInstead();
  }

  Future<void> _stopListening() async {
    if (!_listening) return;
    await _voice.stop();
    if (mounted) setState(() => _listening = false);
  }

  Future<void> _befriend() async {
    final generator = AppServices.of(context).generator;
    setState(() => _saving = true);
    final CharacterFriend friend;
    try {
      friend = await widget.repository.createFriend(
        NewFriend(
          name: _name.trim(),
          personality: _personality!,
          favoriteThings: [for (final item in _favoriteList) item.value],
          speechStyle: _speech!,
          introduction: _introduction,
          assetPath: widget.art.assetPath,
          accentHex: widget.art.accentHex,
          generationJobId: widget.art.jobId,
          thumbnailPath: widget.art.thumbnailPath,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      // Everything chosen stays as it is: one more tap tries again.
      _messages.currentState
        ?..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '${failureMessage(error, '친구를 데려오지 못했어요.')} '
              '다시 눌러 주세요.',
            ),
          ),
        );
      return;
    }
    if (widget.art.jobId case final job?) {
      unawaited(generator.finished(job));
    }
    if (!mounted) return;
    _saving = false;
    setState(() {
      _friend = friend;
      _step = _Step.friend;
      _line = 0;
    });
  }

  void _goTo(Widget page) => Navigator.of(
    context,
  ).pushAndRemoveUntil(bogleRoute(page), (route) => route.isFirst);

  // ---- Korean that fits the name ---------------------------------------

  String get _nameOr => _name.trim().isEmpty ? '이 친구' : _name.trim();

  /// The friend's introduction, from its personality and favourite things.
  String get _introduction => introductionFor(_personality!, _favoriteList);

  /// "나는 뭉글이야" in each 말투.
  String _intro(String style) {
    final n = _nameOr, b = hasBatchim(n);
    return switch (style) {
      '~지요!' => '안녕, 나는 $n${b ? '이' : ''}지요!',
      '해요체' => '안녕하세요, 저는 $n${b ? '이에요' : '예요'}!',
      _ => '안녕, 나는 $n${b ? '이야' : '야'}!',
    };
  }

  List<String> get _greetings {
    final profile = SpeechProfile.tryParse(_speech ?? '');
    if (profile != null) {
      return [profile.introduction(_nameOr), _creationMessage];
    }
    return switch (_speech) {
      '~지요!' => ['${_intro('~지요!')} 만나게 되어 반갑지요!', _creationMessage],
      '해요체' => ['${_intro('해요체')} 만나게 되어 반가워요!', _creationMessage],
      _ => ['${_intro('반말')} 만나게 되어 반가워!', _creationMessage],
    };
  }

  ({String? lead, String title}) get _prompt {
    final n = _nameOr, b = hasBatchim(n);
    return switch (_step) {
      _Step.arrive => (lead: null, title: '친구가 찾아왔어요!'),
      // Figma 364:2094: one line, the ask and the question together.
      _Step.name => (lead: null, title: '이 친구에 대해 알려주세요! 이 친구의 이름은 뭐예요?'),
      // Figma 563:1976's question, with the 구성안's hint.
      _Step.personality => (
        lead: '가장 잘 어울리는 모습을 하나 골라 주세요.',
        title: '$n${b ? '은' : '는'} 어떤 친구인가요?',
      ),
      _Step.favorites => (
        lead: '가장 좋아하는 것을 $maxFavorites개까지 골라 주세요.',
        title: '$n${b ? '이' : '가'} 좋아하는 건 무엇인가요?',
      ),
      _Step.speech => (
        lead: '말투를 누르면 미리 볼 수 있어요.',
        title: '$n${b ? '은' : '는'} 어떻게 말하나요?',
      ),
      _Step.friend => (lead: null, title: '친구가 되었어요!'),
    };
  }

  // ---- Layout ----------------------------------------------------------

  bool get _farewell => _step == _Step.friend && _line >= _greetings.length;

  /// Figma's 1194 × 834 frame to this screen.
  double get _s {
    final size = MediaQuery.sizeOf(context);
    return BogleViewport.designScale(size);
  }

  @override
  Widget build(BuildContext context) {
    final prompt = _prompt;
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 320);
    return withBogleBodyFont(
      context,
      ScaffoldMessenger(
        key: _messages,
        child: Scaffold(
          backgroundColor: BogleColors.cream,
          // Figma 584:2240 and the other setting frames: a flat cream page.
          body: ColoredBox(
            color: BogleColors.cream,
            // The order screen's party poppers, fired once the friend has
            // said hello and "친구가 되었어요!" appears.
            child: Fireworks(
              active: _farewell,
              style: FireworksStyle.screenFan,
              focusTarget: _friendArt,
              keepClear: _farewellButtons,
              child: _SpeechBackdrop(
                enabled: _step == _Step.speech,
                child: Column(
                  children: [
                    // Figma 285:3691: "Setting" while getting to know the
                    // friend, "Hello" once it is one.
                    AppTopBar(
                      key: const ValueKey('setup-header'),
                      repository: widget.repository,
                      title: _step == _Step.friend ? 'Hello' : 'Setting',
                    ),
                    Expanded(
                      child: _step == _Step.friend
                          ? _friendMade()
                          : _tapOnward(
                              Stack(
                                children: [
                                  Positioned.fill(
                                    child: _questions(prompt, motion),
                                  ),
                                  // Figma 568:2319: back to the question
                                  // before, 32 pt under the bar.
                                  Positioned(
                                    left: 59 * _s,
                                    top: 32 * _s,
                                    child: AnimatedSwitcher(
                                      duration: motion,
                                      child: _canGoBack
                                          ? BogleBackButton(
                                              key: const ValueKey('setup-back'),
                                              inkKey: const ValueKey(
                                                'setup-back-ink',
                                              ),
                                              size: math.max(48, 68 * _s),
                                              onTap: _back,
                                            )
                                          : const SizedBox.shrink(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _canGoBack =>
      !_saving &&
      _step.index > _Step.name.index &&
      _step.index < _Step.friend.index;

  /// The questions, Figma 584:2240 below the 115 pt bar: the question ends
  /// at 260, the friend stands in 347–577, the answers end 50 pt from the
  /// bottom (which already clears the home indicator).
  Widget _questions(({String? lead, String title}) prompt, Duration motion) =>
      _step == _Step.speech
      ? _speechQuestion(prompt, motion)
      : _questionViewport(
          child: SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                28,
                53 * _s,
                28,
                math.max(50 * _s, MediaQuery.viewPaddingOf(context).bottom + 8),
              ),
              child: Column(
                children: [
                  // Question, asked in the friend's place.
                  _arrivalReveal(
                    start: .60,
                    end: .82,
                    child: AnimatedSwitcher(
                      duration: motion,
                      child: _farewell
                          ? SizedBox(
                              height: _Prompt.height * _s,
                              key: const ValueKey('none'),
                            )
                          : _Prompt(
                              key: ValueKey(prompt.title),
                              lead: prompt.lead,
                              title: prompt.title,
                              scale: _s,
                            ),
                    ),
                  ),
                  // The told name, under its question;
                  // chosen answers sit below the friend.
                  AnimatedContainer(
                    duration: motion,
                    curve: Curves.easeOutCubic,
                    height:
                        (_step == _Step.name || _step == _Step.arrive
                            ? 87
                            : 24) *
                        _s *
                        math.max(1, BogleViewport.of(context).textScale),
                    child: Center(child: _answerSlot()),
                  ),
                  Expanded(child: _stage(motion)),
                  SizedBox(height: 43 * _s),
                  _arrivalReveal(
                    start: .82,
                    end: 1,
                    child: AnimatedSwitcher(
                      duration: motion,
                      switchInCurve: Curves.easeOutCubic,
                      child: KeyedSubtree(
                        key: ValueKey((_step, _input, _farewell)),
                        child: _controls(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

  Widget _questionViewport({required Widget child}) => LayoutBuilder(
    builder: (context, box) {
      final viewport = BogleViewport.of(context);
      final scroll = viewport.scrollScene(box.biggest);
      // Keep the same ancestors when the keyboard shrinks the viewport.
      // Swapping child for ScrollView used to dispose the focused field,
      // immediately closing the native iPad keyboard again.
      return SingleChildScrollView(
        physics: scroll ? null : const NeverScrollableScrollPhysics(),
        child: SizedBox(
          height: scroll
              ? math.max(
                  box.maxHeight,
                  680 * _s * math.max(1, viewport.textScale),
                )
              : box.maxHeight,
          child: child,
        ),
      );
    },
  );

  Widget _arrivalReveal({
    required double start,
    required double end,
    required Widget child,
  }) {
    if (_step != _Step.arrive) return child;
    return AnimatedBuilder(
      animation: _arrival,
      child: child,
      builder: (context, child) {
        final visible = Interval(
          start,
          end,
          curve: Curves.easeOutCubic,
        ).transform(_arrival.value);
        return IgnorePointer(
          ignoring: !_arrival.isCompleted,
          child: ExcludeSemantics(
            excluding: !_arrival.isCompleted,
            child: Opacity(opacity: visible, child: child),
          ),
        );
      },
    );
  }

  /// The friend, with the clouds it came through on arrival and a speech
  /// bubble when trying out 말투.
  /// The frame the new friend's drawing is fitted into: Figma's 483 × 251.5
  /// figure with 22.9 pt of glow around it.
  static const _artAspect = 528.8 / 297.343;

  Widget _friendFigure({double? width}) {
    final artwork = FriendArtwork(
      assetPath: widget.art.assetPath,
      semanticsLabel: '새 친구',
    );
    return SizedBox(
      key: _friendArt,
      width: width,
      child: AspectRatio(
        aspectRatio: _artAspect,
        child: _step == _Step.friend
            ? Stack(
                fit: StackFit.expand,
                children: [
                  // The drawing is a little see-through; a solid cream
                  // copy of its shape behind it hides the party ribbons
                  // where they cross behind the friend.
                  ExcludeSemantics(
                    key: const ValueKey('friend-backing'),
                    child: ColorFiltered(
                      colorFilter: _solidCream,
                      child: artwork,
                    ),
                  ),
                  artwork,
                ],
              )
            : artwork,
      ),
    );
  }

  Widget _stage(Duration motion) => LayoutBuilder(
    builder: (context, box) {
      // Figma 584:2294: 354 pt wide, 400 with its glow. When it talks,
      // it stands at the foot of the stage, small enough for its balloon
      // to fit above it under the question.
      final room = _balloonRoom(box.maxWidth);
      final width = math.min(
        400 * _s,
        math.max(0.0, box.maxHeight - room) * _artAspect,
      );
      final friend = _friendFigure(width: width);
      if (_step == _Step.arrive) {
        return FriendArrival(progress: _arrival, child: friend);
      }
      final height = width / _artAspect;
      final frame = Rect.fromLTWH(
        (box.maxWidth - width) / 2,
        (box.maxHeight - height + room) / 2,
        width,
        height,
      );
      // The whole stage, so the balloon is placed in its coordinates.
      return SizedBox(
        width: box.maxWidth,
        height: box.maxHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Steps aside smoothly when a balloon needs the room.
            AnimatedPositioned.fromRect(
              duration: motion,
              curve: Curves.easeInOutCubic,
              rect: frame,
              child: _Hop(key: ValueKey(_step), child: friend),
            ),
            if (_balloon case final text?)
              _trying(box.biggest, frame, motion, text),
          ],
        ),
      );
    },
  );

  /// What the friend says over its head while trying out 말투: the same
  /// line in the chosen one.
  String? get _balloon => _step == _Step.speech && _speech != null
      ? SpeechProfile.tryParse(_speech!)?.preview(SpeechSample.play) ??
            speechChoiceOf(_speech!)?.sample
      : null;

  double _balloonWidth(double stageWidth) =>
      math.max(160, math.min(360, stageWidth - 32));

  double _balloonRoom(double stageWidth) {
    if (_step != _Step.speech) return 0;
    var room = 0.0;
    for (final manner in SpeechManner.values) {
      for (final polite in [false, true]) {
        for (final sample in SpeechSample.values) {
          final text = SpeechProfile(manner, polite: polite).preview(sample);
          final size = SpeechBubble.estimate(
            context,
            text,
            maxWidth: _balloonWidth(stageWidth),
          );
          room = math.max(room, size.height + 12);
        }
      }
    }
    return room;
  }

  Widget _speechQuestion(
    ({String? lead, String title}) prompt,
    Duration motion,
  ) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.fromLTRB(32 * _s, 24 * _s, 32 * _s, 20 * _s),
      child: LayoutBuilder(
        builder: (context, box) {
          final header = Padding(
            padding: EdgeInsets.symmetric(horizontal: 64 * _s),
            child: Column(
              children: [
                Text(
                  prompt.lead!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: bogleQuestionFont,
                    fontSize: 22 * _s,
                    height: 1.35,
                    color: const Color(0xFF8C9099),
                  ),
                ),
                SizedBox(height: 5 * _s),
                Text(
                  prompt.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: bogleQuestionFont,
                    fontSize: 36 * _s,
                    height: 1.2,
                    letterSpacing: -1.08 * _s,
                    color: BogleColors.text,
                  ),
                ),
              ],
            ),
          );
          final controls = Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: SpeechStylePicker(
                value: _speech,
                scale: _s,
                enabled: !_saving,
                creationLayout: true,
                onChanged: (value) => setState(() => _speech = value),
                confirmation: FilledButton(
                  key: const ValueKey('setup-befriend'),
                  onPressed: _saving || _speech == null ? null : _next,
                  style: FilledButton.styleFrom(
                    backgroundColor: BogleColors.logo,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: BogleColors.blueSoft,
                    disabledForegroundColor: const Color(0xFF8F97AC),
                    minimumSize: Size(0, 52 * _s),
                    padding: EdgeInsets.symmetric(
                      horizontal: 24 * _s,
                      vertical: 12 * _s,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12 * _s),
                    ),
                    textStyle: TextStyle(
                      fontFamily: bogleDisplayFont,
                      fontSize: 20 * _s,
                      height: 1.2,
                    ),
                  ),
                  child: _saving
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 12),
                            Text('친구를 데려오는 중…'),
                          ],
                        )
                      : const Text('이 말투로 정하기'),
                ),
              ),
            ),
          );
          // 작은 창·큰 글자는 세로로 스크롤해 선택 카드와 확인 버튼을 보장한다.
          if (box.maxWidth < 800 ||
              box.maxHeight < 520 * _s ||
              MediaQuery.textScalerOf(context).scale(1) > 1.4) {
            return SingleChildScrollView(
              child: Column(
                children: [
                  header,
                  SizedBox(
                    height: math.max(
                      290 * _s,
                      _balloonRoom(box.maxWidth) + 230 * _s,
                    ),
                    child: _stage(motion),
                  ),
                  controls,
                ],
              ),
            );
          }
          return Column(
            children: [
              header,
              Expanded(child: _stage(motion)),
              controls,
            ],
          );
        },
      ),
    ),
  );

  /// The friend talking: a balloon just above its head, the tail pointing
  /// down at its mouth, opening the way the friend faces (right unless it
  /// looks left, or there's no room).
  Widget _trying(Size stage, Rect frame, Duration motion, String text) {
    // The drawing, fitted into the friend's frame.
    final natural = _look?.natural;
    final art = natural == null || natural.isEmpty
        ? frame
        : Alignment.center.inscribe(
            applyBoxFit(BoxFit.contain, natural, frame.size).destination,
            frame,
          );
    final anchors = _anchors ?? FigureAnchors.whole;
    final head = Rect.fromLTRB(
      art.left + anchors.head.left * art.width,
      art.top + anchors.head.top * art.height,
      art.left + anchors.head.right * art.width,
      art.top + anchors.head.bottom * art.height,
    );
    const margin = 16.0, gap = 8.0;
    final balloon = SpeechBubble.estimate(
      context,
      text,
      maxWidth: _balloonWidth(stage.width),
    );
    var left = anchors.facing >= 0;
    final lean = head.width * .18 * (left ? 1 : -1);
    final tip = Offset(head.center.dx + lean, head.top - gap);
    // The tail's point, from the balloon's edge it leans back towards.
    const skew = .6;
    const reach = SpeechBubble.defaultTailRoot - skew * SpeechBubble.tailHeight;
    if (left && tip.dx - reach + balloon.width > stage.width - margin) {
      left = false;
    } else if (!left && tip.dx + reach - balloon.width < margin) {
      left = true;
    }
    final x = left ? tip.dx - reach : tip.dx + reach - balloon.width;
    return Positioned(
      left: x.clamp(margin, stage.width - margin - balloon.width).toDouble(),
      bottom: stage.height - tip.dy,
      child: AnimatedSwitcher(
        duration: motion,
        child: SpeechBubble(
          key: ValueKey(text),
          text: text,
          maxWidth: _balloonWidth(stage.width),
          tailRoot: left
              ? SpeechBubble.defaultTailRoot
              : balloon.width - SpeechBubble.defaultTailRoot,
          tailSkew: left ? -skew : skew,
        ),
      ),
    );
  }

  /// Figma's "보글 보글" pill: what the child has told us so far.
  Widget? _answerSlot() {
    if (_step != _Step.name) return null;
    final empty = _answer.trim().isEmpty;
    // Figma 364:2056: nothing under the question until there is an
    // answer (or the child is typing or talking).
    if (empty && _input != _Input.text && !_listening) return null;
    final pill = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      constraints: const BoxConstraints(minWidth: 300, maxWidth: 620),
      height: math.max(
        64,
        MediaQuery.textScalerOf(context).scale(28) * 1.5 + 18,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 30),
      decoration: BoxDecoration(
        color: _input == _Input.text ? Colors.white : BogleColors.blueSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: _input == _Input.text || _listening
              ? BogleColors.blue
              : Colors.transparent,
          width: 2,
        ),
      ),
      // Hugs the answer (never narrower than minWidth).
      child: Center(
        widthFactor: 1,
        child: _input == _Input.text
            // A fixed width: sizing the field to its text lets Korean
            // composition spill past it, under the → button.
            ? SizedBox(
                width: 420,
                child: Semantics(
                  label: '친구 이름',
                  child: TextField(
                    key: const ValueKey('setup-answer'),
                    controller: _text,
                    focusNode: _textFocus,
                    textAlignVertical: TextAlignVertical.center,
                    cursorColor: BogleColors.blueStrong,
                    cursorRadius: const Radius.circular(1),
                    textInputAction: TextInputAction.done,
                    maxLength: 12,
                    style: _pillText.copyWith(fontWeight: FontWeight.w600),
                    // The pill is the field: drop the theme's white box and
                    // outline so nothing is drawn on top of it.
                    decoration: InputDecoration(
                      filled: false,
                      isCollapsed: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      counterText: '',
                      hintText: '이름을 적어 주세요',
                      hintStyle: _pillText.copyWith(
                        color: BogleColors.muted,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    onChanged: _setAnswer,
                    onSubmitted: (_) => _next(),
                  ),
                ),
              )
            : Text(
                empty ? '듣고 있어요…' : _answer,
                key: const ValueKey('setup-answer-text'),
                style: _pillText.copyWith(
                  color: empty ? BogleColors.muted : BogleColors.text,
                ),
              ),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 64),
        Flexible(child: pill),
        const SizedBox(width: 12),
        // Next sits beside the answer, ready once there is one.
        // While typing, "다음" sits under the field instead.
        AnimatedScale(
          duration: const Duration(milliseconds: 180),
          scale: empty || _input == _Input.text ? 0 : 1,
          child: Tooltip(
            message: '다음',
            child: IconButton.filled(
              onPressed: empty || _input == _Input.text ? null : _next,
              style: IconButton.styleFrom(
                backgroundColor: BogleColors.blueStrong,
                minimumSize: const Size(52, 52),
              ),
              icon: const Icon(Icons.arrow_forward_rounded, size: 26),
            ),
          ),
        ),
      ],
    );
  }

  static const _pillText = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: BogleColors.text,
  );

  Widget _controls() {
    switch (_step) {
      case _Step.arrive:
        // Nothing to press: the first question follows on its own.
        return const SizedBox.shrink();
      case _Step.name:
        return _answerControls();
      case _Step.personality:
        return _choices(
          cards: [
            for (final choice in personalityChoices)
              _AnswerCard(
                label: choice,
                width: 240,
                scale: _s,
                selected: _personality == choice,
                onTap: () => setState(() => _personality = choice),
              ),
          ],
          next: _NextPill(
            key: const ValueKey('setup-next'),
            busy: _saving,
            label: '다음',
            scale: _s,
            onTap: _personality == null ? null : _next,
          ),
        );
      case _Step.favorites:
        // One or two of eight, four to a row.
        final full = _favorites.length >= maxFavorites;
        return _choices(
          width: 4 * 203 + 3 * 24,
          cards: [
            for (final item in favoriteChoices)
              _AnswerCard(
                label: item.label,
                scale: _s,
                selected: _favorites.contains(item),
                enabled: _favorites.contains(item) || !full,
                onTap: () => _toggleFavorite(item),
              ),
          ],
          next: _NextPill(
            key: const ValueKey('setup-next'),
            busy: _saving,
            label: '다음',
            scale: _s,
            onTap: _favorites.isEmpty ? null : _next,
          ),
        );
      case _Step.speech:
        return const SizedBox.shrink();
      case _Step.friend:
        // Laid out on its own by [_friendMade].
        return const SizedBox.shrink();
    }
  }

  /// A question's answer cards (Figma 563:1976), and under them the button
  /// that goes on once one is chosen: nothing moves on by itself, so a
  /// wrong tap is just tapped again.
  Widget _choices({
    required List<Widget> cards,
    required Widget next,
    double? width,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: width == null ? null : width * _s,
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 24 * _s,
          runSpacing: 14 * _s,
          children: [
            for (final (i, card) in cards.indexed) _Rise(index: i, child: card),
          ],
        ),
      ),
      SizedBox(height: 28 * _s),
      _Rise(index: cards.length, child: next),
    ],
  );

  Widget _answerControls() {
    switch (_input) {
      case _Input.choose:
        // Figma 584:2274: the two ways to tell the name, 50 pt apart.
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Rise(
              index: 4,
              child: _SettingButton(
                label: '말로 알려주기',
                filled: true,
                scale: _s,
                onTap: () {
                  _speakInstead();
                  _toggleListening();
                },
              ),
            ),
            SizedBox(width: 50 * _s),
            _Rise(
              index: 5,
              child: _SettingButton(
                label: '글자로 적기',
                filled: false,
                scale: _s,
                onTap: _typeInstead,
              ),
            ),
          ],
        );
      case _Input.voice:
        // Figma 364:2244: a big record button and a white one, from the
        // sides.
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _Rise(
                from: const Offset(-1, 0),
                child: _RecordButton(
                  listening: _listening,
                  onTap: _toggleListening,
                ),
              ),
              const Spacer(),
              _Rise(
                from: const Offset(1, 0),
                child: _RoundChoice(
                  label: '글자로 적기',
                  icon: Icons.keyboard_alt_outlined,
                  onTap: _typeInstead,
                ),
              ),
            ],
          ),
        );
      case _Input.text:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Rise(
              child: TextButton.icon(
                onPressed: () {
                  _speakInstead();
                  _toggleListening();
                },
                icon: const Icon(Icons.mic_rounded),
                label: const Text('말로 알려줄래요'),
                style: TextButton.styleFrom(
                  foregroundColor: BogleColors.blueStrong,
                  minimumSize: const Size(0, 58),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 24),
            _Rise(
              index: 1,
              child: PrimaryButton(
                label: '다음',
                icon: Icons.arrow_forward_rounded,
                onPressed: _canGoOn ? _next : null,
              ),
            ),
          ],
        );
    }
  }

  /// Figma 250:2845 / 299:3933 (the friend says hello) and 299:4128 (the
  /// ways onward), laid out on the 1194 × 834 frame below the top bar:
  /// "친구가 되었어요!" above the friend while it talks in the box at the
  /// bottom; then the friend rises, the line settles under it and the two
  /// buttons take the box's place.
  Widget _friendMade() => LayoutBuilder(
    builder: (context, box) {
      if (BogleViewport.of(context).scrollScene(box.biggest)) {
        final u = _s.clamp(.8, 1.2);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
          child: Column(
            children: [
              Text(
                '친구가 되었어요!',
                style: TextStyle(
                  fontFamily: bogleQuestionFont,
                  fontSize: 36 * u,
                  color: BogleColors.text,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: math.min(528.8 * u, box.maxWidth - 56),
                child: _friendFigure(),
              ),
              const SizedBox(height: 24),
              if (_farewell)
                _farewellRow(u, wrap: true)
              else
                SizedBox(
                  height: _greetingHeight(box.maxWidth - 56, u),
                  child: _dialogue(u, expanded: true),
                ),
            ],
          ),
        );
      }
      // Frame x maps across the width; frame y from the top bar's foot
      // (115) to the bottom edge maps down this area. Sizes keep their
      // shape at the smaller of the two scales.
      final sx = box.maxWidth / 1194, sy = box.maxHeight / (834 - 115);
      final u = math.min(sx, sy);
      Rect at(double x, double y, double w, double h) => Rect.fromCenter(
        center: Offset(x * sx, (y - 115) * sy),
        width: w * u,
        height: h * u,
      );
      final motion = MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 640);
      final farewell = _farewell;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedPositioned.fromRect(
            duration: motion,
            curve: Curves.easeInOutCubic,
            rect: at(597.5, farewell ? 365.8 : 513.5, 528.8, 297.343),
            child: _Hop(key: ValueKey(_step), child: _friendFigure()),
          ),
          AnimatedPositioned.fromRect(
            duration: motion,
            curve: Curves.easeInOutCubic,
            rect: at(596.5, farewell ? 586 : 260, 700, 40),
            child: Center(
              child: Semantics(
                header: true,
                child: Text(
                  '친구가 되었어요!',
                  style: TextStyle(
                    fontFamily: bogleQuestionFont,
                    fontSize: 36 * u,
                    height: 40 / 36,
                    letterSpacing: -1.08 * u,
                    color: BogleColors.text,
                  ),
                ),
              ),
            ),
          ),
          if (farewell)
            Positioned.fromRect(
              rect: at(597, 740, 854, 88),
              child: _farewellRow(u),
            )
          else
            Positioned.fromRect(
              rect: at(597, 732, 900, 104),
              child: _dialogue(u),
            ),
        ],
      );
    },
  );

  /// Figma's box: white at 80 %, 6 pt corners, the line in the logo's
  /// lavender; ▶ reads the next one.
  double _greetingHeight(double width, double u) {
    final painter = TextPainter(
      text: TextSpan(
        text: keepWords(_greetings[_line]),
        style: TextStyle(
          fontFamily: bogleDisplayFont,
          fontSize: 28 * u,
          height: 40 / 28,
          letterSpacing: -0.84 * u,
        ),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: math.max(1, width - 120 * u));
    final height = math.max(104 * u, painter.height + 32 * u);
    painter.dispose();
    return height;
  }

  Widget _dialogue(double u, {bool expanded = false}) {
    final line = _greetings[_line];
    return _Rise(
      child: Semantics(
        button: true,
        label: '$line 다음',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: () => setState(() => _line++),
          child: Container(
            key: const ValueKey('greeting-box'),
            decoration: _figmaBox(Colors.white),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Types out like a friend talking.
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 60 * u),
                  child: Center(
                    child: TweenAnimationBuilder<int>(
                      key: ValueKey(line),
                      tween: IntTween(begin: 0, end: line.characters.length),
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : Duration(milliseconds: 38 * line.characters.length),
                      // Whole words to a line, as in the balloons.
                      builder: (context, n, _) => Text(
                        keepWords(line.characters.take(n).toString()),
                        textAlign: TextAlign.center,
                        maxLines: expanded ? null : 2,
                        style: TextStyle(
                          fontFamily: bogleDisplayFont,
                          fontSize: 28 * u,
                          height: 40 / 28,
                          letterSpacing: -0.84 * u,
                          color: BogleColors.logo,
                        ),
                      ),
                    ),
                  ),
                ),
                // Figma "Polygon 5", turned to point onward.
                Positioned(
                  right: 26 * u,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: RotatedBox(
                      quarterTurns: 1,
                      child: SvgPicture.asset(
                        'assets/figma/dialogue_next.svg',
                        width: 21.65 * u,
                        height: 18.75 * u,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Figma 299:4128's two 402 × 88 buttons, 50 apart.
  /// The ways onward, in the app's own rounded buttons with their icons
  /// (kept from before the Figma pass), where Figma 299:4128 puts them.
  Widget _farewellRow(double u, {bool wrap = false}) {
    final friend = _friend!;
    final buttons = <Widget>[
      _Rise(
        index: 1,
        child: _BigButton(
          label: '${friend.name}의 집으로 가기',
          icon: Icons.home_rounded,
          filled: true,
          onTap: () => _goTo(
            FriendScreen(repository: widget.repository, friend: friend),
          ),
        ),
      ),
      if (!wrap) const SizedBox(width: 40),
      _Rise(
        index: 2,
        child: _BigButton(
          label: '친구 보관함으로 가기',
          icon: Icons.auto_awesome_motion_rounded,
          filled: false,
          onTap: () => _goTo(ArchiveScreen(repository: widget.repository)),
        ),
      ),
    ];
    if (wrap) {
      return Wrap(
        key: _farewellButtons,
        spacing: 24,
        runSpacing: 20,
        alignment: WrapAlignment.center,
        children: buttons,
      );
    }
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          key: _farewellButtons,
          mainAxisSize: MainAxisSize.min,
          children: buttons,
        ),
      ),
    );
  }

  /// Figma's box and buttons: 80 % fill, 6 pt corners, a faint all-round
  /// shadow.
  static BoxDecoration _figmaBox(Color color) => BoxDecoration(
    color: color.withValues(alpha: .8),
    borderRadius: BorderRadius.circular(6),
    boxShadow: figmaShadow,
  );
}
