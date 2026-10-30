import 'package:flutter/material.dart';

import '../../theme/bogle_theme.dart';
import '../../widgets/bogle_widgets.dart';
import '../house/house_widgets.dart' show TrimmedFriendArtwork;

/// My page tokens, from the 마이페이지 design (and Figma 254:3589): section
/// and item titles in the display font, white cards with a hairline
/// border, periwinkle (#8BA2FF) chips and tiles, blue hairline dividers.
abstract final class ProfileStyle {
  static const border = Color(0xFFE7E9F1);

  /// Behind the art on friend and order tiles.
  static const tile = Color(0xFFA3B4FF);

  /// Lines inside the order card, and the frame round an earlier order.
  static const rule = Color(0xFFBAC7FF);
  static const chipFill = Color(0xFFEFF2FB);
  static const chipText = Color(0xFF5D6577);
  static const subtle = Color(0xFF8A90A0);
  static const link = Color(0xFF6883F5);
  static const statusFill = Color(0xFFE4EAFF);

  static const sectionTitle = TextStyle(
    fontFamily: bogleDisplayFont,
    fontSize: 28,
    height: 1.2,
    color: BogleColors.text,
  );

  /// A friend's or an order's name, a column's heading.
  static const displayTitle = TextStyle(
    fontFamily: bogleDisplayFont,
    fontSize: 21,
    height: 1.2,
    color: BogleColors.text,
  );
  static const itemTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: BogleColors.text,
  );
  static const label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: subtle,
  );
  static const value = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: BogleColors.text,
  );
  static const price = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: BogleColors.text,
  );
}

class ProfileCard extends StatelessWidget {
  const ProfileCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 18,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: ProfileStyle.border),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF3A4A8C).withValues(alpha: .04),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );
}

/// "내 캐릭터 …… 보유 캐릭터 12개 [캐릭터 만들기]" style section header.
class ProfileSection extends StatelessWidget {
  const ProfileSection({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, box) {
          final titleWidget = Semantics(
            header: true,
            child: Text(title, style: ProfileStyle.sectionTitle),
          );
          if (box.maxWidth < 720 &&
              MediaQuery.textScalerOf(context).scale(16) > 24) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleWidget,
                if (trailing != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: trailing!,
                  ),
              ],
            );
          }
          return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Expanded(child: titleWidget),
                ?trailing,
              ],
            ),
          );
        },
      ),
      const SizedBox(height: 10),
      child,
    ],
  );
}

/// "전체 주문 내역 보기 ›"
class ProfileLink extends StatelessWidget {
  const ProfileLink({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      foregroundColor: ProfileStyle.link,
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        const SizedBox(width: 2),
        const Icon(Icons.chevron_right_rounded, size: 20),
      ],
    ),
  );
}

/// Filled (#8BA2FF) or outlined pill button.
class ProfileButton extends StatelessWidget {
  const ProfileButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.filled = false,
    this.large = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool filled;

  /// The design's bigger pill ("개인 정보 수정").
  final bool large;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      foregroundColor: filled ? Colors.white : BogleColors.logo,
      backgroundColor: filled ? BogleColors.logo : Colors.white,
      side: BorderSide(color: BogleColors.logo, width: large ? 2 : 1.5),
      shape: const StadiumBorder(),
      minimumSize: Size(0, large ? 48 : 44),
      padding: EdgeInsets.symmetric(horizontal: large ? 30 : 20),
      textStyle: TextStyle(
        fontFamily: bogleBodyFont,
        fontSize: large ? 16 : 15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    );
    return OutlinedButton(
      style: style,
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 6)],
          Text(label),
        ],
      ),
    );
  }
}

/// Small option chip ("기본형", "M사이즈(30cm)").
class OptionChip extends StatelessWidget {
  const OptionChip(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
    decoration: BoxDecoration(
      color: BogleColors.logo,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      maxLines: 1,
      softWrap: false,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),
  );
}

/// Status chip ("배송중", "배송완료"): filled periwinkle, as in the design;
/// [strong] false gives the light one.
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.strong = true});
  final String label;
  final bool strong;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(
      color: strong ? BogleColors.logo : ProfileStyle.statusFill,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: strong ? Colors.white : ProfileStyle.link,
      ),
    ),
  );
}

/// Character art on a soft pastel tile.
class ArtTile extends StatelessWidget {
  const ArtTile({
    super.key,
    required this.asset,
    required this.size,
    this.color = const Color(0xFFEEF1FB),
    this.radius = 14,
  });
  final String asset;
  final double size;
  final Color color;
  final double radius;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    padding: EdgeInsets.all(size * .1),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: FriendArtwork(assetPath: asset),
  );
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.asset,
    required this.size,
    this.label,
  });
  final String asset;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    padding: EdgeInsets.all(size * .16),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: const Color(0xFFEEF1FB),
      border: Border.all(color: Colors.white, width: 4),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF3A4A8C).withValues(alpha: .08),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: TrimmedFriendArtwork(assetPath: asset, semanticsLabel: label),
  );
}

class ProfileEmptyState extends StatelessWidget {
  const ProfileEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.onPressed,
  });
  final IconData icon;
  final String title;
  final String message;
  final String? action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 36, color: BogleColors.logo),
        const SizedBox(height: 12),
        Text(title, textAlign: TextAlign.center, style: ProfileStyle.itemTitle),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: ProfileStyle.subtle),
        ),
        if (action != null) ...[
          const SizedBox(height: 16),
          ProfileButton(label: action!, onPressed: onPressed),
        ],
      ],
    ),
  );
}

String formatWon(int won) {
  final digits = won.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return '$out원';
}

/// 이름도 함께 표시해 색만으로 선택을 구분하지 않는다.
const profileColors = [
  ('blue', '하늘빛', BogleColors.logo),
  ('mint', '풀잎빛', BogleColors.mint),
  ('pink', '꽃잎빛', BogleColors.pink),
  ('yellow', '햇살빛', BogleColors.yellow),
];
Color profileAccent(String value) => profileColors
    .firstWhere((c) => c.$1 == value, orElse: () => profileColors.first)
    .$3;
