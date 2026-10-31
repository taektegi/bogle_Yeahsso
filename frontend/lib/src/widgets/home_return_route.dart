import 'package:flutter/material.dart';

typedef HomeDeparture = ({Rect rect, Widget artwork});

/// A page whose Home action can close directly onto the existing root,
/// independently of its ordinary back transition.
class HomeReturnRoute<T> extends PageRouteBuilder<T> {
  HomeReturnRoute({
    required super.pageBuilder,
    required super.transitionsBuilder,
    required super.transitionDuration,
    required super.reverseTransitionDuration,
    required this.homeTransitionDuration,
  });

  /// How long the closing takes when Home is pressed. The transitions
  /// builder plays it too, telling it apart by [returningHome].
  final Duration homeTransitionDuration;
  HomeDeparture? Function()? captureDeparture;
  HomeDeparture? departure;
  bool get returningHome => _returningHome;

  Route<dynamic>? _previous;
  bool _returningHome = false;

  @override
  void didChangePrevious(Route<dynamic>? previousRoute) {
    super.didChangePrevious(previousRoute);
    _previous = previousRoute;
  }

  void returnHome() {
    final nav = navigator;
    if (nav == null || !isCurrent || isFirst || _returningHome) return;
    departure = captureDeparture?.call();
    _returningHome = true;
    controller?.reverseDuration = reverseTransitionDuration;
    // Keep this opaque page over the stack while removing intermediate
    // pages. Only the root is revealed during the closing; no archive
    // card remains as a destination for a character Hero flight.
    while (_previous != null && !_previous!.isFirst) {
      nav.removeRouteBelow(this);
    }
    nav.pop();
  }

  @override
  Duration get reverseTransitionDuration =>
      _returningHome ? homeTransitionDuration : super.reverseTransitionDuration;

  /// One widget tree for opening, going back and returning home: the
  /// transitions builder reads [returningHome] instead of being swapped for
  /// another. A different tree would move the page across while it is laid
  /// out, which an overlay inside it (a tooltip that is up) can't survive.
  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => super.buildTransitions(
    context,
    animation,
    secondaryAnimation,
    HeroMode(enabled: !_returningHome, child: child),
  );
}
