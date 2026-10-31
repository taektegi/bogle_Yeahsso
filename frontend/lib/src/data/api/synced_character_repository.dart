import 'dart:async';

import '../../models/character_friend.dart';
import '../../models/friend_status.dart';
import '../character_repository.dart';
import 'api_client.dart';
import 'device_art.dart';
import 'outbox.dart';

/// The friends live on the iPad. The archive, the house and every other
/// screen read them from here with no network: the friends, their pictures
/// and face maps (saved as files), their care and memories.
///
/// The character service is told about changes ([Outbox]) and asked once a
/// launch for friends the iPad doesn't have yet ([pull]), such as after the
/// app was reinstalled. Its own copy is what the chat AI and the motion
/// clips use.
class SyncedCharacterRepository implements CharacterRepository {
  // 앱의 짧은 선택 문구를 서버 목록의 표시명에 연결하고, 코드는 응답에서 가져온다.
  static const _personalityLabels = {
    '호기심 많은 탐험가': '활발하고 호기심이 많아요',
    '차분하고 든든한 친구': '조용하지만 용감해요',
    '다정한 응원가': '다정하고 잘 웃어요',
    '엉뚱한 상상가': '엉뚱한 상상가예요',
  };

  SyncedCharacterRepository(
    this.api, {
    required this.local,
    required this.outbox,
    required this.art,
    this.onForget,
    this.undoWindow = const Duration(seconds: 10),
  });

  final ApiClient api;

  /// Where the friends are kept (with a store, across launches).
  final InMemoryCharacterRepository local;
  final Outbox outbox;
  final DeviceArt art;
  final Future<void> Function(String friendId)? onForget;

  /// How long a deletion can still be undone before it reaches the service.
  final Duration undoWindow;
  final _forgetTimers = <String, Timer>{};

  /// Friends the service made (and knows by this id); the starter friends
  /// and any friend made without the service stay on the iPad only.
  static bool isServiceId(String id) => _uuid.hasMatch(id);
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  /// A friend as the service describes it, with its pictures at [artPath].
  static CharacterFriend friendFrom(
    Map<String, dynamic> json, {
    required String artPath,
    String? thumbnailPath,
  }) {
    final created = json['createdAt'] as String?;
    return CharacterFriend(
      id: json['id'] as String,
      name: json['name'] as String,
      personality:
          json['personality'] as String? ??
          json['personalityLabel'] as String? ??
          '',
      introduction: json['introduction'] as String? ?? '',
      favoriteThings: [
        for (final thing in json['favoriteThings'] as List? ?? const [])
          thing as String,
      ],
      speechStyle: json['speechStyle'] as String,
      assetPath: artPath,
      thumbnailPath: thumbnailPath,
      accentHex: (json['accentArgb'] as num).toInt(),
      createdAt: created == null ? null : DateTime.parse(created).toLocal(),
      sleep: SleepSchedule(
        bedtime:
            (json['bedtime'] as num?)?.toInt() ?? const SleepSchedule().bedtime,
        wakeTime:
            (json['wakeTime'] as num?)?.toInt() ??
            const SleepSchedule().wakeTime,
      ),
    );
  }

  @override
  Future<List<CharacterFriend>> fetchFriends() => local.fetchFriends();

  /// Brings in the service's friends the iPad doesn't have: their details,
  /// and their pictures and face maps saved as files. Friends already on
  /// the iPad are left as they are (the iPad's copy is the one that counts);
  /// ones waiting to be deleted stay deleted.
  Future<int> pull() async {
    final json = await api.get('/v1/characters');
    final have = {for (final f in await local.fetchFriends()) f.id};
    var added = 0;
    for (final item in (json['items'] as List).reversed) {
      final friend = (item as Map).cast<String, dynamic>();
      final id = friend['id'] as String;
      if (have.contains(id) || await outbox.isLeaving(id)) continue;
      final artRef = ImageRef.fromJson(friend['art'] as Map<String, dynamic>);
      final thumbJson = friend['thumbnail'] as Map<String, dynamic>?;
      final kept = await art.keep(
        id,
        art: await api.download(artRef.url),
        thumbnail: thumbJson == null
            ? null
            : await api.download(ImageRef.fromJson(thumbJson).url),
        face: friend['face'],
      );
      await local.saveFriend(
        friendFrom(friend, artPath: kept.art, thumbnailPath: kept.thumbnail),
      );
      added++;
    }
    return added;
  }

  @override
  Future<CharacterFriend> createFriend(NewFriend friend) async {
    final job = friend.generationJobId;
    if (job == null) return local.createFriend(friend);
    // 같은 생성 결과를 다시 저장하거나 앱을 재실행해도 같은 요청으로 복구한다.
    final key = 'friend-$job';
    final types = await api.get('/v1/personality-types');
    final label = _personalityLabels[friend.personality] ?? friend.personality;
    final selected = (types['items'] as List)
        .cast<Map<String, dynamic>>()
        .where(
          (item) =>
              item['label'] == label || item['code'] == friend.personality,
        )
        .firstOrNull;
    if (selected == null) {
      throw const ApiException(
        statusCode: 422,
        code: 'validation_error',
        message: '성격을 다시 선택해 주세요.',
        fieldErrors: {'personalityType': '선택한 성격을 찾을 수 없어요.'},
      );
    }
    final body = {
      'generationJobId': job,
      'name': friend.name,
      'personalityType': selected['code'],
      'favoriteThings': friend.favoriteThings,
      'speechStyle': friend.speechStyle,
      'bedtime': const SleepSchedule().bedtime,
      'wakeTime': const SleepSchedule().wakeTime,
    };
    // The service writes the friend's introduction before answering (up to
    // ~10 s). The key makes a retry return the same friend, never a second.
    final json = await api.post(
      '/v1/characters',
      body: body,
      idempotencyKey: key,
      timeout: const Duration(seconds: 25),
    );
    // The pictures are already on the iPad: the generator saved them.
    final created = friendFrom(
      json,
      artPath: friend.assetPath,
      thumbnailPath: friend.thumbnailPath,
    );
    await local.saveFriend(created);
    // Setup writes an introduction from what the child chose; the service
    // picks its own when making the friend, so it hears this one after.
    if (friend.introduction.isNotEmpty &&
        friend.introduction != created.introduction) {
      return saveFriend(created.copyWith(introduction: friend.introduction));
    }
    return created;
  }

  @override
  Future<CharacterFriend> saveFriend(CharacterFriend friend) async {
    final before = (await local.fetchFriends())
        .where((f) => f.id == friend.id)
        .firstOrNull;
    await local.saveFriend(friend);
    if (isServiceId(friend.id)) {
      await outbox.patchCharacter(friend.id, {
        if (before?.name != friend.name) 'name': friend.name,
        if (before?.personality != friend.personality)
          'personality': friend.personality,
        if (before?.introduction != friend.introduction)
          'introduction': friend.introduction,
        if (before?.speechStyle != friend.speechStyle)
          'speechStyle': friend.speechStyle,
        if (before?.sleep.bedtime != friend.sleep.bedtime)
          'bedtime': friend.sleep.bedtime,
        if (before?.sleep.wakeTime != friend.sleep.wakeTime)
          'wakeTime': friend.sleep.wakeTime,
      });
    }
    return friend;
  }

  /// Gone from the iPad at once; the service hears after the undo window
  /// (even if the app closes first: the outbox keeps it).
  @override
  Future<DeletedFriend?> deleteFriend(String friendId) async {
    final deleted = await local.deleteFriend(friendId);
    if (deleted != null && isServiceId(friendId)) {
      await outbox.deleteCharacter(friendId, delay: undoWindow);
      _forgetLater(deleted.friend);
    }
    return deleted;
  }

  /// Its picture files go once the deletion can't be undone.
  void _forgetLater(CharacterFriend friend) {
    _forgetTimers.remove(friend.id)?.cancel();
    _forgetTimers[friend.id] = Timer(
      undoWindow + const Duration(seconds: 1),
      () async {
        _forgetTimers.remove(friend.id);
        final back = (await local.fetchFriends()).any((f) => f.id == friend.id);
        if (!back) {
          await art.forget(friend.assetPath);
          await onForget?.call(friend.id);
        }
      },
    );
  }

  @override
  Future<void> restoreFriend(DeletedFriend deleted) async {
    if (isServiceId(deleted.friend.id)) {
      if (!await outbox.cancelDelete(deleted.friend.id)) return;
    }
    _forgetTimers.remove(deleted.friend.id)?.cancel();
    await local.restoreFriend(deleted);
  }

  @override
  Future<List<String>> fetchMemories(String friendId) =>
      local.fetchMemories(friendId);

  @override
  Future<void> addMemory(String friendId, String memory) =>
      local.addMemory(friendId, memory);

  @override
  Future<FriendStatus> fetchStatus(String friendId) =>
      local.fetchStatus(friendId);

  @override
  Future<void> saveStatus(String friendId, FriendStatus status) =>
      local.saveStatus(friendId, status);
}
