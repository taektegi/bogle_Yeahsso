import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/art_source.dart';
import '../data/character_repository.dart';
import '../data/failures.dart';
import '../data/speech_style.dart';
import '../widgets/speech_style_picker.dart';
import '../data/korean.dart';
import '../data/window_view.dart';
import '../models/character_friend.dart';
import '../theme/bogle_theme.dart';
import '../theme/bogle_viewport.dart';
import '../widgets/bogle_widgets.dart';
import '../widgets/bogle_dialog.dart';
import '../widgets/house_transition.dart';
import '../widgets/top_bar.dart';
import 'friend_screen.dart';
import 'house/house_widgets.dart';
import 'profile/profile_widgets.dart';

part 'archive/friend_house_card.dart';
part 'archive/friend_dialogs.dart';

/// Figma 243:1612: every friend as a tall card in a centred carousel. The
/// card in the middle is the one you visit; its house opens from here.
/// Bottom-corner actions let the child edit a friend or say goodbye.
class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key, required this.repository});
  final CharacterRepository repository;

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  List<CharacterFriend>? _friends;

  /// Why the friends couldn't be loaded, while there are none to show.
  String? _loadError;
  PageController? _pages;

  /// Absolute page in the looping carousel; the slot is `_page % slots`.
  int? _page;

  /// Bumped to rebuild the carousel from scratch: a swapped-in controller
  /// alone would inherit the old scroll offset, which points at a different
  /// card once the list has changed.
  int _generation = 0;
  bool _deleting = false;
  final _messages = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The house's window view is a large picture: have it ready before a
    // card opens, so the opening doesn't stop to decode it.
    for (final view in [WindowView.aquarium.day, WindowView.aquarium.night!]) {
      precacheImage(AssetImage(view), context);
    }
  }

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  CharacterFriend? get _centred {
    final friends = _friends, page = _page;
    if (friends == null || friends.isEmpty || page == null) return null;
    final slot = page % friends.length;
    return slot < friends.length ? friends[slot] : null;
  }

  /// Keep the repository's order and preserve the centred friend on reload.
  Future<void> _load({String? focus}) async {
    final keep = focus ?? _centred?.id;
    final List<CharacterFriend> friends;
    try {
      friends = await widget.repository.fetchFriends();
    } catch (error) {
      if (!mounted) return;
      final message = failureMessage(error, '잠시 후 다시 시도해 주세요.');
      // Friends already on screen stay; only an empty archive says so.
      if (_friends == null) {
        setState(() => _loadError = message);
      } else {
        _say(message);
      }
      return;
    }
    if (!mounted) return;
    _loadError = null;
    // Each drawing's shape, read ahead: a friend flying into its house is
    // drawn true to it from the first frame to the last.
    for (final f in friends) {
      artLookOf(f.assetPath);
    }
    final before = _friends;
    // The same friends in the same order, the same one in the middle (back
    // from a house): refresh the cards where they are. Rebuilding the
    // carousel would make it jump just as the friend lands in its card.
    if (before != null &&
        _centred?.id == keep &&
        before.map((f) => f.id).join() == friends.map((f) => f.id).join()) {
      setState(() => _friends = friends);
      return;
    }
    setState(() {
      _friends = friends;
      final at = friends.indexWhere((f) => f.id == keep);
      _focus(at < 0 ? 0 : at);
    });
  }

  /// Rebuilds the carousel centred on [index] (after the list changed).
  void _focus(int index) {
    final friends = _friends;
    if (friends == null) return;
    _page = friends.length * 500 + index;
    _generation++;
    final old = _pages;
    _pages = null;
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  /// Floats just above the bottom button instead of covering it.
  void _say(String message, {SnackBarAction? action}) {
    final side = ((MediaQuery.sizeOf(context).width - 560) / 2).clamp(
      16.0,
      double.infinity,
    );
    _messages.currentState
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(
              fontFamily: bogleBodyFont,
              fontSize: 20,
              height: 1.4,
              color: BogleColors.text,
            ),
          ),
          action: action,
          // Flutter measures the action without text scaling when deciding
          // whether to wrap it. Give large text its own row instead.
          actionOverflowThreshold:
              MediaQuery.textScalerOf(context).scale(14) > 20 ? 0 : .25,
          // Actions persist by default in Flutter. Allow time to undo, then
          // dismiss through the framework's normal animation and lifecycle.
          persist: false,
          duration: Duration(seconds: action == null ? 4 : 6),
          backgroundColor: BogleColors.cream,
          elevation: 3,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(side, 0, side, 104),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: BogleColors.blueSoft),
          ),
        ),
      );
  }

  Future<void> _delete(CharacterFriend friend) async {
    if (_deleting) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => _GoodbyeDialog(friend: friend),
    );
    if (sure != true || !mounted) return;
    _deleting = true;
    DeletedFriend? deleted;
    try {
      deleted = await widget.repository.deleteFriend(friend.id);
    } catch (_) {
      if (mounted) _say('친구와 작별하지 못했어요. 다시 시도해 주세요.');
      return;
    } finally {
      _deleting = false;
    }
    if (deleted == null || !mounted) return;
    final snapshot = deleted;
    final index = _friends!.indexOf(friend);
    final rest = _friends!.where((f) => f.id != friend.id).toList();
    await _load(
      focus: rest.isEmpty ? null : rest[index.clamp(0, rest.length - 1)].id,
    );
    if (!mounted) return;
    // A way back, in case a small finger tapped the wrong friend.
    _say(
      '${particle(friend.name, '과', '와')} 작별했어요',
      action: SnackBarAction(
        label: '다시 데려오기',
        textColor: BogleColors.blueStrong,
        backgroundColor: BogleColors.blueSoft,
        onPressed: () async {
          try {
            await widget.repository.restoreFriend(snapshot);
            if (mounted) await _load(focus: friend.id);
          } catch (_) {
            if (mounted) _say('친구를 데려오지 못했어요. 다시 시도해 주세요.');
          }
        },
      ),
    );
  }

  Future<void> _edit(CharacterFriend friend) async {
    final changed = await showDialog<CharacterFriend>(
      context: context,
      builder: (context) => _EditFriendDialog(friend: friend),
    );
    if (changed == null) return;
    try {
      await widget.repository.saveFriend(changed);
    } catch (error) {
      if (mounted) _say(failureMessage(error, '바꾼 내용을 저장하지 못했어요.'));
      return;
    }
    if (mounted) await _load(focus: changed.id);
  }

  /// The card in the middle, which opens into its friend's house.
  final _openingCard = GlobalKey(debugLabel: 'archive-opening-card');
  bool _visiting = false;

  /// Into the friend's house: the middle card opens up into it (see
  /// [houseRoute]); without the card on screen, the page just slides in.
  Future<void> _visit(CharacterFriend friend) async {
    if (_visiting) return;
    _visiting = true;
    try {
      // Resolve the canvas before the destination Hero is measured. The
      // plain, rigged and face-overlay versions then keep the same footprint,
      // including on a cold first visit with a slowly loading rig.
      if (!artAspects.containsKey(friend.assetPath)) {
        await artLookOf(friend.assetPath);
      }
      if (!mounted ||
          _centred?.id != friend.id ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      final house = FriendScreen(repository: widget.repository, friend: friend);
      final card =
          _openingCard.currentContext?.findRenderObject() as RenderBox?;
      await Navigator.of(context).push(
        card == null || !card.hasSize
            ? bogleRoute<void>(house)
            : houseRoute<void>(
                house,
                from: card.localToGlobal(Offset.zero) & card.size,
                // The card's own colour, so the house opens out of it.
                color: friendCardColor(
                  friend,
                  measuredArtLook(friend.assetPath),
                ),
              ),
      );
      if (mounted) await _load();
    } finally {
      _visiting = false;
    }
  }

  @override
  Widget build(BuildContext context) => withBogleBodyFont(
    context,
    font: bogleUiFont,
    ScaffoldMessenger(
      key: _messages,
      child: Scaffold(
        backgroundColor: BogleColors.cream,
        body: Column(
          children: [
            AppTopBar(
              key: const ValueKey('archive-header'),
              repository: widget.repository,
              title: 'Friends',
            ),
            Expanded(
              child: SafeArea(
                top: false,
                child: Padding(
                  // The carousel runs to the screen's edges, as in Figma.
                  padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
                  child: Column(children: [Expanded(child: _body())]),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _body() {
    final friends = _friends;
    if (friends == null && _loadError != null) {
      return Center(
        child: ProfileEmptyState(
          icon: Icons.cloud_off_rounded,
          title: '친구들을 불러오지 못했어요',
          message: _loadError!,
          action: '다시 불러오기',
          onPressed: () {
            setState(() => _loadError = null);
            _load();
          },
        ),
      );
    }
    if (friends == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (friends.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.house_rounded, size: 56, color: BogleColors.logo),
            SizedBox(height: 12),
            Text(
              '아직 집에 사는 친구가 없어요',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: BogleColors.text,
              ),
            ),
            SizedBox(height: 6),
            Text(
              '그림을 그리면 친구가 찾아와 여기에 집을 지어요.',
              style: TextStyle(fontSize: 16, color: BogleColors.muted),
            ),
            SizedBox(height: 12),
            Text('상단 홈으로 돌아가 새로운 친구를 그려 보세요.'),
          ],
        ),
      );
    }
    // Only existing friends belong in this carousel.
    final slots = friends.length;
    final page = _page ??= slots * 500;
    final current = page % slots;
    return LayoutBuilder(
      builder: (context, box) {
        // The dots and the visit button take about 110 pt; the card is
        // Figma's 268 × 468, 58 pt from its neighbours.
        final cardH = math
            .min(
              box.maxHeight - 125,
              468 *
                  MediaQuery.sizeOf(context).height /
                  BogleViewport.reference.height,
            )
            .clamp(
              math.min(320.0, math.max(120.0, box.maxHeight - 125)),
              math.min(720.0, math.max(120.0, box.maxHeight - 125)),
            )
            .toDouble();
        final cardW = cardH * _FriendHouseCard.aspect;
        final gap = 58 * cardW / 268;
        final fraction = ((cardW + gap) / box.maxWidth).clamp(.2, .9);
        if (_pages == null ||
            (_pages!.viewportFraction - fraction).abs() > .001) {
          final old = _pages;
          _pages = PageController(
            viewportFraction: fraction,
            initialPage: page,
          );
          if (old != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
          }
        }
        final pages = _pages!;
        return Column(
          children: [
            Expanded(
              child: SizedBox(
                height: cardH + 30 * cardW / 268,
                child: KeyedSubtree(
                  key: ValueKey(_generation),
                  child: PageView.builder(
                    key: const ValueKey('archive-carousel'),
                    controller: pages,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (context, i) => AnimatedBuilder(
                      animation: pages,
                      builder: (context, child) {
                        final at =
                            pages.hasClients && pages.position.haveDimensions
                            ? pages.page ?? page.toDouble()
                            : page.toDouble();
                        final d = (at - i).abs().clamp(0.0, 1.0);
                        // As in Figma, the neighbours keep their size and
                        // colour; the one in the middle sits 10 pt lower.
                        return Center(
                          child: Transform.translate(
                            offset: Offset(0, 10 * cardW / 268 * (1 - d)),
                            child: child,
                          ),
                        );
                      },
                      // Every friend is read out once: the loop can show a
                      // card at both edges, so only one side counts.
                      child: ExcludeSemantics(
                        excluding:
                            i - page < -(slots ~/ 2) ||
                            i - page > (slots - 1) ~/ 2,
                        child: SizedBox(
                          key: i == page ? _openingCard : null,
                          width: cardW,
                          height: cardH,
                          child: _FriendHouseCard(
                            key: i == page
                                ? const ValueKey('archive-selected-card')
                                : null,
                            friend: friends[i % slots],
                            // One Hero per friend, even when the loop
                            // shows a friend twice.
                            hero: i == page,
                            onEdit: () => _edit(friends[i % slots]),
                            onDelete: () => _delete(friends[i % slots]),
                            onTap: () => i != page
                                ? pages.animateToPage(
                                    i,
                                    duration: const Duration(milliseconds: 320),
                                    curve: Curves.easeOutCubic,
                                  )
                                : _visit(friends[i % slots]),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < friends.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == current ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == current
                          ? BogleColors.logo
                          : BogleColors.logo.withValues(alpha: .25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: '${friends[current].name}의 집에 놀러 가기',
              icon: Icons.home_rounded,
              onPressed: () => _visit(friends[current]),
            ),
          ],
        );
      },
    );
  }
}
