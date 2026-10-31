import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/character_friend.dart';
import '../screens/house/house_widgets.dart';

/// Figma 230:3907's soft glass edge, adapted to the circular portrait.
/// The centre keeps the measured colour so glass highlights never wash out
/// pale artwork. The character itself is never blurred or recoloured.
class CharacterPreviewSurface extends StatelessWidget {
  const CharacterPreviewSurface({
    super.key,
    required this.friend,
    required this.child,
  });

  final CharacterFriend friend;
  final Widget child;

  static Color backdrop(Color accent, ArtLook? look) =>
      cardColorFor(Color.lerp(accent, const Color(0xFFA8B6CC), .7)!, look);

  @override
  Widget build(BuildContext context) => FutureBuilder<ArtLook?>(
    future: artLookOf(friend.assetPath),
    initialData: measuredArtLook(friend.assetPath),
    builder: (context, snapshot) {
      final color = backdrop(Color(friend.accentHex), snapshot.data);
      final contrast = MediaQuery.highContrastOf(context);
      final surface = DecoratedBox(
        key: const ValueKey('character-preview-material'),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: contrast ? color : null,
          gradient: contrast
              ? null
              : RadialGradient(
                  colors: [color, color, color.withValues(alpha: .82)],
                  stops: const [0, .84, 1],
                ),
          border: contrast
              ? Border.all(color: const Color(0xFF68748C), width: 2)
              : null,
        ),
        child: CustomPaint(
          foregroundPainter: contrast ? null : const _GlassRim(),
          child: child,
        ),
      );
      return DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF545C79).withValues(alpha: .09),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipOval(
          child: contrast
              ? surface
              : BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: surface,
                ),
        ),
      );
    },
  );
}

/// Fixed light, following the reference's top/bottom inner reflections.
/// Only the narrow rim is shaded; there is no shader or animated distortion.
class _GlassRim extends CustomPainter {
  const _GlassRim();

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawOval(
      bounds.deflate(4),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x50FFFFFF), Color(0x00545C79), Color(0x30545C79)],
          stops: [0, .48, 1],
        ).createShader(bounds),
    );
    canvas.drawOval(
      bounds.deflate(.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xF2FFFFFF),
            Color(0x50FFFFFF),
            Color(0x18FFFFFF),
            Color(0xD9FFFFFF),
          ],
          stops: [0, .35, .62, 1],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_GlassRim oldDelegate) => false;
}
