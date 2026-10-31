import 'package:flutter/material.dart';

import '../theme/bogle_theme.dart';
import 'bogle_dialog.dart';

/// The top-bar notice uses the same lettering and quiet cream surface as
/// the app. No nested cards or repeated empty-state illustrations.
class BogleNewsDialog extends StatelessWidget {
  const BogleNewsDialog({super.key});

  @override
  Widget build(BuildContext context) => BogleDialogFrame(
    key: const ValueKey('bogle-news-dialog'),
    width: 460,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BogleDialogHeader(title: '알림', closeLabel: '알림 닫기'),
        Flexible(
          child: Scrollbar(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: 28,
                vertical: MediaQuery.sizeOf(context).height < 480 ? 16 : 52,
              ),
              child: const Text(
                '아직 새로운 소식이 없어요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: bogleBodyFont,
                  fontSize: 22,
                  height: 1.5,
                  color: BogleColors.text,
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: BogleColors.logo,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 52),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontFamily: bogleDisplayFont,
                fontSize: 20,
                height: 1.2,
              ),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ),
      ],
    ),
  );
}
