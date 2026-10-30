part of '../photo_capture.dart';

/// The wireframe's big rounded choices on the check screen: the periwinkle
/// one to go on, the grey one to go back.
class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  /// Working on it: a spinner instead of the words.
  final bool busy;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 320,
    height: 80,
    child: FilledButton(
      onPressed: busy ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: primary ? BogleColors.logo : const Color(0xFFE4E3DA),
        foregroundColor: primary ? Colors.white : const Color(0xFF6E6D64),
        disabledBackgroundColor: primary
            ? BogleColors.logo.withValues(alpha: .7)
            : const Color(0xFFEDECE5),
        disabledForegroundColor: Colors.white,
        elevation: 0,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: bogleDisplayFont, fontSize: 30),
      ),
      child: busy
          ? const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
              ),
            )
          : Text(label),
    ),
  );
}

class _Tweak extends StatelessWidget {
  const _Tweak({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });
  final String icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    selected: selected,
    label: label,
    excludeSemantics: true,
    child: Opacity(
      opacity: onTap == null ? .45 : 1,
      child: SizedBox(
        width: 136 * MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.8),
        child: Material(
          color: selected ? BogleColors.blueSoft : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: selected ? BogleColors.logo : BogleColors.line,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    PhotoIcon(
                      icon,
                      size: 20,
                      color: selected
                          ? BogleColors.blueStrong
                          : BogleColors.text,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        style: const TextStyle(
                          fontFamily: bogleDisplayFont,
                          fontSize: 18,
                          height: 1.3,
                          color: BogleColors.text,
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
    ),
  );
}

/// A restrained secondary action, with the same type and height as edits.
class _SubjectEntry extends StatelessWidget {
  const _SubjectEntry({super.key, required this.onTap});
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 56),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        foregroundColor: BogleColors.text,
        backgroundColor: Colors.white,
        side: const BorderSide(color: BogleColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(
          fontFamily: bogleDisplayFont,
          fontSize: 18,
          height: 1.3,
        ),
      ),
      child: const Text('대상 선택'),
    ),
  );
}
