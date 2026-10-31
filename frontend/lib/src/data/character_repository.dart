import '../models/character_friend.dart';
import '../models/friend_status.dart';
import 'local_store.dart';
import 'retired_friends.dart';
import '../util/art_cache.dart';
import 'starter_friends.dart';

abstract interface class CharacterRepository {
  Future<List<CharacterFriend>> fetchFriends();

  /// A new friend from setup. The store gives it its id and creation time
  /// (the service: `POST /v1/characters`) and returns it as stored.
  Future<CharacterFriend> createFriend(NewFriend friend);

  /// Saves changes to a friend that already exists.
  Future<CharacterFriend> saveFriend(CharacterFriend friend);
  Future<void> addMemory(String friendId, String memory);

  /// Says goodbye: the friend, its house and its memories are removed.
  Future<DeletedFriend?> deleteFriend(String friendId);

  /// Restores the entire house and its position, not just the card.
  Future<void> restoreFriend(DeletedFriend deleted);
  Future<List<String>> fetchMemories(String friendId);

  /// The friend's life in its house, aged to now.
  Future<FriendStatus> fetchStatus(String friendId);
  Future<void> saveStatus(String friendId, FriendStatus status);
}

/// What setup decides about a new friend; the rest comes from the store.
class NewFriend {
  const NewFriend({
    required this.name,
    required this.personality,
    required this.favoriteThings,
    required this.speechStyle,
    required this.assetPath,
    required this.accentHex,
    this.introduction = '',
    this.generationJobId,
    this.thumbnailPath,
  });
  final String name;
  final String personality;
  final List<String> favoriteThings;
  final String speechStyle;
  final String assetPath;
  final int accentHex;
  final String introduction;

  /// The character service's job the artwork came from, if it did.
  final String? generationJobId;

  /// A small copy of the artwork, when the generator made one.
  final String? thumbnailPath;
}

class DeletedFriend {
  DeletedFriend({
    required this.friend,
    required this.index,
    required this.status,
    required List<String> memories,
  }) : memories = List.unmodifiable(memories);
  final CharacterFriend friend;
  final int index;
  final FriendStatus? status;
  final List<String> memories;
}

/// Keeps friends for this app session, starting with [starterFriends]. With
/// a [store] it keeps them across launches too: the friends made on the
/// device, their care and their memories.
class InMemoryCharacterRepository implements CharacterRepository {
  InMemoryCharacterRepository({
    List<CharacterFriend>? friends,
    LocalStore? store,
    this.storeName = 'characters',
    String Function(String path)? relocate,
  }) : _friends = List.of(friends ?? starterFriends()),
       _store = store,
       _relocate = relocate;

  final List<CharacterFriend> _friends;
  late final _retired = RetiredFriends(
    _store,
    () => [
      for (final friend in _friends) friend.assetPath,
      for (final friend in _friends)
        if (friend.thumbnailPath != null) friend.thumbnailPath!,
    ],
  );
  final Map<String, List<String>> _memories = {};
  final Map<String, FriendStatus> _status = {};
  final LocalStore? _store;
  final String Function(String path)? _relocate;

  /// The store document this repository keeps.
  final String storeName;

  Future<void>? _restoring;
  Future<void> get _ready =>
      _restoring ??= _restore().catchError((Object error, StackTrace stack) {
        _restoring = null;
        Error.throwWithStackTrace(error, stack);
      });

  Future<void> _restore() async {
    final saved = await readDocument(_store, storeName, (value) {
      final doc = value as Map;
      for (final row in doc['friends'] as List) {
        CharacterFriend.fromJson((row as Map).cast());
      }
      for (final row in (doc['status'] as Map? ?? const {}).values) {
        FriendStatus.fromJson((row as Map).cast());
      }
      for (final rows in (doc['memories'] as Map? ?? const {}).values) {
        for (final row in rows as List) {
          if (row is! String) throw const FormatException('Invalid memory');
        }
      }
      if (doc['starters'] != null) doc['starters'] as List;
      return doc;
    });
    if (saved == null) {
      await _retired.sweep().catchError((Object _) {});
      return;
    }
    try {
      final starters = {for (final f in starterFriends()) f.id: f};
      final friends = [
        for (final json in saved['friends'] as List? ?? const [])
          CharacterFriend.fromJson((json as Map).cast()),
      ];
      _friends
        ..clear()
        ..addAll([
          for (final f in friends)
            // A starter friend keeps what the child changed, but its
            // picture is always the app's own.
            if (starters[f.id] case final starter?)
              f
                  .withArt(starter.assetPath)
                  .copyWith(
                    introduction:
                        f.id == 'mindle' &&
                            f.introduction == '내가 민들레래!\n내가 민들레어서 행복해.'
                        ? starter.introduction
                        : f.introduction,
                  )
            else
              f.withArt(
                _relocate?.call(f.assetPath) ?? f.assetPath,
                thumbnail: f.thumbnailPath == null
                    ? null
                    : _relocate?.call(f.thumbnailPath!) ?? f.thumbnailPath,
              ),
        ]);
      // Starters added to the app since this was saved move in; ones the
      // child already met and said goodbye to stay gone.
      final met = {
        for (final id in saved['starters'] as List? ?? starterIdsBefore) '$id',
      };
      final arrived = [
        for (final starter in starters.values)
          if (!met.contains(starter.id) &&
              !_friends.any((f) => f.id == starter.id))
            starter,
      ];
      _friends.addAll(arrived);
      _memories
        ..clear()
        ..addAll({
          for (final MapEntry(:key, :value)
              in (saved['memories'] as Map? ?? const {}).entries)
            '$key': [for (final m in value as List) '$m'],
        });
      _status
        ..clear()
        ..addAll({
          for (final MapEntry(:key, :value)
              in (saved['status'] as Map? ?? const {}).entries)
            '$key': FriendStatus.fromJson((value as Map).cast()),
        });
      if (arrived.isNotEmpty) await _save();
      await _retired.sweep().catchError((Object _) {});
    } on Object {
      // Keep an unreadable document intact; never save starter defaults
      // over a failed restore.
      throw const StoreRecoveryException();
    }
  }

  Future<void> _save() async {
    final store = _store;
    if (store == null) return;
    try {
      await store.write(storeName, {
        'version': 1,
        'friends': [for (final f in _friends) f.toJson()],
        // Every starter has been offered by now, so a missing one was let go.
        'starters': [for (final f in starterFriends()) f.id],
        'memories': _memories,
        'status': {
          for (final MapEntry(:key, :value) in _status.entries)
            key: value.toJson(),
        },
      });
    } on Object {
      rethrow;
    }
  }

  @override
  Future<List<CharacterFriend>> fetchFriends() async {
    await _ready;
    return List.unmodifiable(_friends);
  }

  @override
  Future<CharacterFriend> createFriend(NewFriend friend) async {
    await _ready;
    final now = DateTime.now();
    final created = CharacterFriend(
      id: 'friend-${now.microsecondsSinceEpoch}',
      name: friend.name,
      personality: friend.personality,
      introduction: friend.introduction,
      favoriteThings: List.unmodifiable(friend.favoriteThings),
      speechStyle: friend.speechStyle,
      assetPath: friend.assetPath,
      thumbnailPath: friend.thumbnailPath,
      accentHex: friend.accentHex,
      createdAt: now,
    );
    _friends.add(created);
    await _save();
    return created;
  }

  @override
  Future<CharacterFriend> saveFriend(CharacterFriend friend) async {
    await _ready;
    final index = _friends.indexWhere((item) => item.id == friend.id);
    if (index < 0) {
      _friends.add(friend);
    } else {
      _friends[index] = friend;
    }
    await _save();
    return friend;
  }

  @override
  Future<DeletedFriend?> deleteFriend(String friendId) async {
    await _ready;
    final index = _friends.indexWhere((item) => item.id == friendId);
    if (index < 0) return null;
    await _retired.retire(friendId, [
      _friends[index].assetPath,
      ?_friends[index].thumbnailPath,
    ]);
    final deleted = DeletedFriend(
      friend: _friends.removeAt(index),
      index: index,
      status: _status.remove(friendId),
      memories: _memories.remove(friendId) ?? const [],
    );
    try {
      await _save();
    } catch (_) {
      _friends.insert(index, deleted.friend);
      if (deleted.status != null) _status[friendId] = deleted.status!;
      _memories[friendId] = List.of(deleted.memories);
      await _retired.cancel(friendId);
      await _save();
      rethrow;
    }
    evictArtwork(deleted.friend.assetPath);
    if (deleted.friend.thumbnailPath case final path?) evictArtwork(path);
    return deleted;
  }

  @override
  Future<void> restoreFriend(DeletedFriend deleted) async {
    await _ready;
    final id = deleted.friend.id;
    // Repeated undo must not duplicate the friend or overwrite newer care.
    if (_friends.any((f) => f.id == id)) return;
    _friends.insert(deleted.index.clamp(0, _friends.length), deleted.friend);
    if (deleted.status != null) _status[id] = deleted.status!;
    _memories[id] = List.of(deleted.memories);
    await _save();
    await _retired.cancel(id);
  }

  @override
  Future<List<String>> fetchMemories(String friendId) async {
    await _ready;
    return List.unmodifiable(_memories[friendId] ?? const []);
  }

  @override
  Future<void> addMemory(String friendId, String memory) async {
    await _ready;
    _memories.putIfAbsent(friendId, () => []).add(memory);
    await _save();
  }

  @override
  Future<FriendStatus> fetchStatus(String friendId) async {
    await _ready;
    final now = DateTime.now();
    final status = (_status[friendId] ?? FriendStatus(updatedAt: now)).aged(
      now,
    );
    return _status[friendId] = status;
  }

  @override
  Future<void> saveStatus(String friendId, FriendStatus status) async {
    await _ready;
    _status[friendId] = status;
    await _save();
  }
}
