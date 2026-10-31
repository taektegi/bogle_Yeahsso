import '../models/character_friend.dart';

/// One line of a chat: the child's ([mine]) or the friend's.
typedef ChatLine = ({bool mine, String text});

/// The friend's side of a chat in its house. The chat service
/// (`POST /v1/characters/{id}/messages`) implements this; it may answer null
/// (asleep, offline, nothing to say), and the friend then answers from its
/// own lines (`friend_talk.dart`), as it does with [LocalChatService].
abstract interface class ChatService {
  Future<String?> replyTo(CharacterFriend friend, String text);

  /// What was said before, oldest first, so a visit picks up where the last
  /// one ended. Empty when nothing is kept.
  Future<List<ChatLine>> history(CharacterFriend friend);
}

/// No chat service: every answer comes from the friend's own lines, and a
/// chat lasts for the visit.
class LocalChatService implements ChatService {
  const LocalChatService();
  @override
  Future<String?> replyTo(CharacterFriend friend, String text) =>
      Future.value();

  @override
  Future<List<ChatLine>> history(CharacterFriend friend) =>
      Future.value(const []);
}
