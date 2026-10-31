part of '../house_widgets.dart';

/// Over the window while the friend's own scenery is still being made; the
/// room shows its default view till then.
class WindowPendingNotice extends StatelessWidget {
  const WindowPendingNotice({super.key, this.scale = 1});

  static const message = '친구에게 어울리는 배경을 만들고 있어요…';

  final double scale;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: message,
    excludeSemantics: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: BogleColors.cream.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: BogleColors.blueSoft),
        boxShadow: [
          BoxShadow(
            color: BogleColors.logo.withValues(alpha: .16),
            blurRadius: 12 * scale,
            offset: Offset(0, 3 * scale),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 22 * scale,
          vertical: 12 * scale,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 18 * scale,
              child: CircularProgressIndicator(
                strokeWidth: 2.4 * scale,
                color: BogleColors.logo,
              ),
            ),
            SizedBox(width: 12 * scale),
            Flexible(
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: bogleUiFont,
                  fontSize: 18 * scale,
                  fontWeight: FontWeight.w600,
                  color: BogleColors.text,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
