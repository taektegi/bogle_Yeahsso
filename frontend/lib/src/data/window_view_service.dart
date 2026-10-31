import '../models/character_friend.dart';
import 'window_view.dart';

/// Optional scenery generation. House, chat and care do not depend on it.
abstract interface class WindowViewService {
  bool supports(CharacterFriend friend);
  Future<WindowView?> load(
    CharacterFriend friend, {
    bool regenerate = false,
    bool Function()? active,
  });
}
