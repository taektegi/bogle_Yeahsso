import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../data/order_catalog.dart';
import '../../models/character_friend.dart';
import '../../screens/profile/profile_widgets.dart';
import '../../theme/bogle_theme.dart';
import '../../theme/bogle_viewport.dart';
import '../../widgets/adaptive_panels.dart';
import '../../widgets/bogle_widgets.dart';
import '../../widgets/character_preview_surface.dart';
import '../house/house_widgets.dart';

part 'doll_options/friend_grid.dart';
part 'doll_options/portrait.dart';
part 'doll_options/options_form.dart';
part 'doll_options/option_controls.dart';

/// Figma 470:2336: one paper panel, a circular portrait on the left,
/// two numbered choices and a price summary on the right. Prices and
/// dimensions come from the demo catalog, not the wireframe's sample text.
class DollOptions extends StatelessWidget {
  const DollOptions({
    super.key,
    required this.friend,
    required this.order,
    required this.onChanged,
    required this.onOrder,
  });

  final CharacterFriend friend;
  final DollOrder order;
  final ValueChanged<DollOrder> onChanged;
  final VoidCallback onOrder;

  bool get _gift => order.extras.contains(DollExtra.giftWrap);

  void _packaging(bool gift) {
    final extras = {...order.extras};
    gift ? extras.add(DollExtra.giftWrap) : extras.remove(DollExtra.giftWrap);
    onChanged(order.copyWith(extras: extras));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = BogleViewport.of(context).stackPanels(box.maxWidth)
          ? (box.maxWidth / 700).clamp(.85, 1.1)
          : box.maxWidth / 1108;
      final padding = 22 * scale;
      final gap = 43 * scale;
      final textScale = scale.clamp(.9, 1.2);
      final options = _OptionsForm(
        order: order,
        gift: _gift,
        scale: scale,
        textScale: textScale,
        onSize: (size) => onChanged(order.copyWith(size: size)),
        onPackaging: _packaging,
        onOrder: onOrder,
      );
      return Container(
        key: const ValueKey('order-options-panel'),
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .8),
          borderRadius: BorderRadius.circular(6 * scale),
          boxShadow: figmaShadow,
        ),
        child: BoglePanelFlow(
          gap: gap,
          compactLeadingHeight: (240 * scale).clamp(180, 320),
          compactTrailingHeight:
              566 *
              scale *
              math.max(1, MediaQuery.textScalerOf(context).scale(1)),
          leading: _Portrait(friend: friend, textScale: textScale),
          trailing: LayoutBuilder(
            builder: (context, formBox) {
              // Keep touch targets and text readable when the keyboard,
              // Split View or larger accessibility text reduces space.
              final minimum = 566 * scale;
              final enlarged = MediaQuery.textScalerOf(context).scale(1);
              if (formBox.maxHeight < minimum || enlarged > 1.15) {
                return SingleChildScrollView(
                  child: SizedBox(
                    height: minimum * math.max(1, enlarged),
                    child: options,
                  ),
                );
              }
              return options;
            },
          ),
        ),
      );
    },
  );
}

/// The first order step, not drawn in Figma: made from 470:2336's parts so
/// it reads as the same page. The paper panel, the chosen friend's portrait
/// on the left under the question, and on the right ① 친구 선택 with every
/// friend as one of the option cards, a summary bar with the chosen friend
/// and the starting price, and the blue button on to the options.
class DollFriendPicker extends StatelessWidget {
  const DollFriendPicker({
    super.key,
    required this.friends,
    required this.selected,
    required this.onSelect,
    required this.onNext,
  });

  final List<CharacterFriend> friends;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = BogleViewport.of(context).stackPanels(box.maxWidth)
          ? (box.maxWidth / 700).clamp(.85, 1.1)
          : box.maxWidth / 1108;
      final textScale = scale.clamp(.9, 1.2);
      final friend = friends[selected];
      final motion = Duration(
        milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 240,
      );
      return Container(
        key: const ValueKey('order-pick-panel'),
        padding: EdgeInsets.all(22 * scale),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .8),
          borderRadius: BorderRadius.circular(6 * scale),
          boxShadow: figmaShadow,
        ),
        child: BoglePanelFlow(
          gap: 43 * scale,
          compactLeadingHeight: (240 * scale).clamp(180, 320),
          compactTrailingHeight: math.max(
            box.maxHeight,
            560 *
                scale *
                math.max(1, MediaQuery.textScalerOf(context).scale(1)),
          ),
          leading: KeyedSubtree(
            key: const ValueKey('order-friend-preview'),
            child: AnimatedSwitcher(
              duration: motion,
              child: _Portrait(
                key: ValueKey(friend.id),
                friend: friend,
                textScale: textScale,
                headline: friend.name,
                question: '어떤 친구를 인형으로 만들까요?',
              ),
            ),
          ),
          trailing: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Heading(
                number: 1,
                title: '친구 선택',
                note: '인형으로 만들 친구를 선택해 주세요.',
                scale: scale,
                textScale: textScale,
              ),
              SizedBox(height: 16 * scale),
              Expanded(
                child: _FriendGrid(
                  friends: friends,
                  selected: selected,
                  scale: scale,
                  textScale: textScale,
                  onSelect: onSelect,
                ),
              ),
              SizedBox(height: 22 * scale),
              _PickSummary(friend: friend, scale: scale, textScale: textScale),
              SizedBox(height: 17 * scale),
              SizedBox(
                height: math.max(48, 52 * scale),
                child: FilledButton(
                  onPressed: onNext,
                  style: FilledButton.styleFrom(
                    backgroundColor: BogleColors.logo,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5.53 * scale),
                    ),
                  ),
                  child: Text(
                    '${friend.name} 인형 만들기',
                    style: TextStyle(
                      fontFamily: bogleDisplayFont,
                      fontSize: 17.69 * textScale,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
