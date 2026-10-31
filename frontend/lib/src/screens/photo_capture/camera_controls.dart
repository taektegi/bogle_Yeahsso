part of '../photo_capture.dart';

/// The wireframe's shutter: a white disc in a white ring.
class _Shutter extends StatefulWidget {
  const _Shutter({required this.onTap});
  final VoidCallback? onTap;
  @override
  State<_Shutter> createState() => _ShutterState();
}

class _ShutterState extends State<_Shutter> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '사진 찍기',
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('photo-shutter'),
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTap: widget.onTap,
        child: Opacity(
          opacity: enabled ? 1 : .45,
          child: Container(
            width: 78,
            height: 78,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
            ),
            child: AnimatedScale(
              scale: _down ? .84 : 1,
              duration: const Duration(milliseconds: 110),
              curve: Curves.easeOut,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The wireframe's white square: the photo library, showing the last photo.
class _LibraryButton extends StatelessWidget {
  const _LibraryButton({required this.thumbnail, required this.onTap});
  final Uint8List? thumbnail;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '사진 보관함에서 고르기',
    excludeSemantics: true,
    child: Material(
      key: const ValueKey('photo-library'),
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox.square(
          dimension: 60,
          child: thumbnail == null
              ? const Icon(
                  Icons.photo_library_rounded,
                  color: BogleColors.logo,
                  size: 28,
                )
              : Image.memory(
                  thumbnail!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
        ),
      ),
    ),
  );
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null ? .35 : 1,
        child: Material(
          color: active
              ? BogleColors.yellow
              : Colors.white.withValues(alpha: .12),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: 52,
              child: Icon(
                icon,
                size: 26,
                color: active ? BogleColors.text : Colors.white,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
