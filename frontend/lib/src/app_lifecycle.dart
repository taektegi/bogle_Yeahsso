import 'package:flutter/widgets.dart';

/// Whether the app is still showing. Pulling Control Center or Notification
/// Center down, a banner, or Slide Over only makes it *inactive*: the child
/// can still see it, so animations, timers and the camera carry on. Only
/// when it is really out of sight (home screen, another app, locked) does
/// anything pause.
bool onScreen(AppLifecycleState? state) =>
    state == null ||
    state == AppLifecycleState.resumed ||
    state == AppLifecycleState.inactive;
