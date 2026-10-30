part of '../house_widgets.dart';

// The house's action tiles (대화하기, 간식주기, 초대하기, 배웅하기).

/// One of the care buttons: a cream tile with the icon on a tinted square
/// and its name below (Figma "Group 1261155768" / "Group 1261155767").
class HouseAction {
  const HouseAction({
    required this.icon,
    required this.label,
    required this.tint,
    this.onTap,
  });
  final Widget icon;
  final String label;

  /// The square behind the icon.
  final Color tint;
  final VoidCallback? onTap;
}

/// The care buttons along the bottom, 18 pt apart, at Figma's size times
/// [scale].
class ActionTiles extends StatelessWidget {
  const ActionTiles({super.key, required this.actions, this.scale = 1});
  final List<HouseAction> actions;
  final double scale;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (i, a) in actions.indexed) ...[
        if (i > 0) SizedBox(width: 18 * scale),
        _ActionTile(action: a, scale: scale),
      ],
    ],
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action, required this.scale});
  final HouseAction action;
  final double scale;
  @override
  Widget build(BuildContext context) {
    final enabled = action.onTap != null;
    final corner = BorderRadius.circular(15 * scale);
    return Semantics(
      button: true,
      enabled: enabled,
      label: action.label,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : .45,
        child: Material(
          color: BogleColors.cream,
          borderRadius: corner,
          child: InkWell(
            borderRadius: corner,
            onTap: action.onTap,
            child: SizedBox(
              width: 117 * scale,
              height: 109 * scale,
              child: Column(
                children: [
                  SizedBox(height: 12 * scale),
                  Container(
                    width: 64 * scale,
                    height: 64 * scale,
                    decoration: BoxDecoration(
                      color: action.tint,
                      borderRadius: BorderRadius.circular(20 * scale),
                    ),
                    alignment: Alignment.center,
                    child: action.icon,
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        action.label,
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: bogleUiFont,
                          fontSize: 15 * scale,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.15 * scale,
                          color: BogleColors.text,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
