import 'package:flutter/material.dart';

import '../../theme/bogle_theme.dart';

/// Keep the room's expressive lettering on names/actions, and use the
/// app's reading face for editable text and longer conversation history.
abstract final class HouseChatType {
  static const action = TextStyle(
    fontFamily: bogleDisplayFont,
    fontSize: 18,
    height: 1.3,
    fontWeight: FontWeight.w400,
  );
  static const message = TextStyle(
    fontFamily: bogleUiFont,
    fontSize: 18,
    height: 1.55,
    fontWeight: FontWeight.w400,
    color: BogleColors.text,
  );
  static const input = TextStyle(
    fontFamily: bogleUiFont,
    fontSize: 17,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: BogleColors.text,
  );
  static const hint = TextStyle(
    fontFamily: bogleUiFont,
    fontSize: 17,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: BogleColors.muted,
  );
  static const quick = TextStyle(
    fontFamily: bogleUiFont,
    fontSize: 15,
    height: 1.25,
    fontWeight: FontWeight.w500,
    color: BogleColors.text,
  );
  static const meta = TextStyle(
    fontFamily: bogleUiFont,
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w400,
    color: BogleColors.muted,
  );
}
