import '../models/character_friend.dart';
import 'window_view.dart';

/// Optional scenery generation. House, chat and care do not depend on it.
abstract interface class WindowViewService {
  bool supports(CharacterFriend friend);

  /// [onWaiting] runs once when the scenery is still being made, so the
  /// house can say so while it shows its default view.
  Future<WindowView?> load(
    CharacterFriend friend, {
    bool regenerate = false,
    bool Function()? active,
    void Function()? onWaiting,
  });
}
