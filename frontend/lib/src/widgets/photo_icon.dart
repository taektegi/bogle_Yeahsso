import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Lucide's 24px outline icons, bundled locally with their ISC license.
class PhotoIcon extends StatelessWidget {
  const PhotoIcon(
    this.name, {
    super.key,
    this.size = 24,
    this.color = const Color(0xFF333333),
  });
  final String name;
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/icons/photo/$name.svg',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    excludeFromSemantics: true,
  );
}
