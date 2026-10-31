import 'package:flutter/material.dart';

import '../theme/bogle_theme.dart';

/// Shared shell for notices, editors and settings. Content can specialize;
/// typography, chrome, spacing and the close target stay consistent.
class BogleDialogFrame extends StatelessWidget {
  const BogleDialogFrame({super.key, required this.child, this.width = 560});
  final Widget child;
  final double width;
  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      textTheme: Theme.of(context).textTheme.apply(fontFamily: bogleUiFont),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: BogleColors.logo,
          foregroundColor: Colors.white,
          minimumSize: const Size(100, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: bogleDisplayFont,
            fontSize: 20,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: BogleColors.text,
          minimumSize: const Size(80, 48),
          textStyle: const TextStyle(
            fontFamily: bogleDisplayFont,
            fontSize: 20,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      chipTheme: Theme.of(context).chipTheme.copyWith(
        selectedColor: BogleColors.blueSoft,
        backgroundColor: Colors.white,
        side: const BorderSide(color: BogleColors.line),
        shape: const StadiumBorder(),
      ),
    ),
    child: Dialog(
      backgroundColor: BogleColors.cream,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: BogleColors.blueSoft),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(width: width, child: child),
    ),
  );
}

class BogleDialogHeader extends StatelessWidget {
  const BogleDialogHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.closeLabel = '닫기',
  });
  final String title, closeLabel;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 20, 16, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontFamily: bogleDisplayFont,
                        fontSize: 28,
                        height: 1.3,
                        color: BogleColors.text,
                      ),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontFamily: bogleUiFont,
                        fontSize: 14,
                        height: 1.5,
                        color: BogleColors.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: closeLabel,
              onPressed: () => Navigator.maybePop(context),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.close_rounded, color: BogleColors.muted),
            ),
          ],
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 28),
        child: Divider(height: 1, color: BogleColors.blueSoft),
      ),
    ],
  );
}

/// Body scrolls while title/actions remain available above the keyboard.
class BogleDialog extends StatelessWidget {
  const BogleDialog({
    super.key,
    required this.title,
    this.icon,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.width = 560,
  });
  final String title;
  final String? subtitle;

  /// Compatibility for callers; decorative badges are intentionally omitted.
  final IconData? icon;
  final Widget child;
  final List<Widget> actions;
  final double width;
  @override
  Widget build(BuildContext context) => BogleDialogFrame(
    width: width,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BogleDialogHeader(title: title, subtitle: subtitle),
        const SizedBox(height: 16),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 4),
            child: DefaultTextStyle.merge(
              style: const TextStyle(
                fontFamily: bogleUiFont,
                color: BogleColors.text,
                height: 1.5,
              ),
              child: child,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: 12,
            overflowSpacing: 8,
            children: actions,
          ),
        ),
      ],
    ),
  );
}

class BogleDialogCard extends StatelessWidget {
  const BogleDialogCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: BogleColors.line),
    ),
    child: child,
  );
}
