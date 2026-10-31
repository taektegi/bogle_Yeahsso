import '../models/character_friend.dart';
import 'chat_service.dart';
import 'local_store.dart';

class ConversationEntry {
  const ConversationEntry(this.line, {this.speaker, this.serverId});
  final String? serverId;
  final ChatLine line;
  final CharacterFriend? speaker;
  Map<String, Object?> toJson() => {
    if (serverId != null) 'serverId': serverId,
    'mine': line.mine,
    'text': line.text,
    if (speaker case final friend?)
      'speaker': {
        'id': friend.id,
        'name': friend.name,
        'asset': friend.assetPath,
        'accent': friend.accentHex,
      },
  };
  factory ConversationEntry.fromJson(Map json) {
    final who = json['speaker'];
    return ConversationEntry(
      (mine: json['mine'] as bool, text: json['text'] as String),
      serverId: json['serverId'] as String?,
      speaker: who is Map
          ? CharacterFriend(
              id: who['id'] as String,
              name: who['name'] as String,
              assetPath: who['asset'] as String,
              accentHex: who['accent'] as int,
              personality: '',
              favoriteThings: const [],
              speechStyle: '',
            )
          : null,
    );
  }
}

/// A device's complete room conversation, including scripted/visitor lines.
/// Separate from the AI transport: offline replies are history too.
class ConversationArchive {
  ConversationArchive({this.store}) {
    _instances.removeWhere((ref) => ref.target == null);
    _instances.add(WeakReference(this));
  }
  static final _instances = <WeakReference<ConversationArchive>>[];
  static Object? _scope(LocalStore? store) =>
      store is FileStore ? store.folder.absolute.path : store;
  static final _forgotten = <(Object?, String)>{};
  static void allow(String id, {LocalStore? store}) =>
      _forgotten.remove((_scope(store), id));
  static void discardCached(String id, {LocalStore? store}) {
    _forgotten.add((_scope(store), id));
    for (final ref in _instances) {
      if (_scope(ref.target?.store) != _scope(store)) continue;
      ref.target?._memory.remove(id);
      ref.target?._imported.remove(id);
      ref.target?._delivered.remove(id);
    }
  }

  final LocalStore? store;
  final _queues = <String, Future<void>>{};
  final _memory = <String, List<ConversationEntry>>{};
  static const limit = 500;
  String _key(String id) => 'conversation-${Uri.encodeComponent(id)}';

  List<ConversationEntry> _decode(Object saved) => [
    for (final row in saved as List)
      _relocate(ConversationEntry.fromJson(row as Map)),
  ];
  ConversationEntry _relocate(ConversationEntry entry) {
    final storage = store;
    final who = entry.speaker;
    if (storage is! FileStore || who == null) return entry;
    return ConversationEntry(
      entry.line,
      speaker: who.withArt(storage.relocate(who.assetPath)),
      serverId: entry.serverId,
    );
  }

  final _imported = <String>{};

  Future<List<ConversationEntry>> _load(String id) async {
    if (_forgotten.contains((_scope(store), id))) return [];
    if (_memory[id] case final cached?) return List.of(cached);
    final restored = await readDocument(store, _key(id), (saved) {
      final doc = saved is Map ? saved : null;
      final entries = _decode(doc == null ? saved : doc['entries'] as Object);
      return (entries, doc?['serverImported'] == true);
    });
    final entries = restored?.$1 ?? <ConversationEntry>[];
    if (restored?.$2 == true) _imported.add(id);
    _memory[id] = entries;
    return List.of(entries);
  }

  Future<void> _save(
    String id,
    List<ConversationEntry> entries, {
    required bool imported,
  }) async {
    if (_forgotten.contains((_scope(store), id))) return;
    final bounded = entries.length > limit
        ? entries.sublist(entries.length - limit)
        : entries;
    await store?.write(_key(id), {
      'entries': [for (final entry in bounded) entry.toJson()],
      'serverImported': imported,
    });
    _memory[id] = List.of(bounded);
    if (imported) _imported.add(id);
  }

  final _delivered = <String, List<ServerChatLine>>{};

  Future<void> recordExchange(
    CharacterFriend friend,
    List<ServerChatLine> lines,
  ) {
    final old = _queues[friend.id] ?? Future.value();
    final next = old.then((_) async {
      final entries = await _load(friend.id);
      final pending = <ServerChatLine>[];
      for (final line in lines) {
        if (entries.any((e) => e.serverId == line.id)) {
          if (line.line.mine) {
            final local = entries.lastIndexWhere(
              (e) => e.serverId == null && e.line == line.line,
            );
            if (local >= 0) entries.removeAt(local);
          } else {
            pending.add(line);
          }
          continue;
        }
        final at = entries.lastIndexWhere(
          (e) =>
              e.serverId == null &&
              e.line == line.line &&
              (line.line.mine || e.speaker?.id == friend.id),
        );
        if (line.line.mine && at >= 0) {
          entries[at] = ConversationEntry(
            entries[at].line,
            speaker: entries[at].speaker,
            serverId: line.id,
          );
        } else {
          entries.add(
            ConversationEntry(
              line.line,
              speaker: line.line.mine ? null : friend,
              serverId: line.id,
            ),
          );
          pending.add(line);
        }
      }
      await _save(friend.id, entries, imported: _imported.contains(friend.id));
      if (!_forgotten.contains((_scope(store), friend.id))) {
        _delivered[friend.id] = pending;
      }
    });
    _queues[friend.id] = next.catchError((Object _) {});
    return next;
  }

  Future<void> mergeServer(CharacterFriend friend, List<ServerChatLine> lines) {
    final old = _queues[friend.id] ?? Future.value();
    final next = old.then((_) async {
      final existing = await _load(friend.id);
      final known = existing.map((e) => e.serverId).whereType<String>().toSet();
      final added = [
        for (final line in lines)
          if (known.add(line.id))
            ConversationEntry(
              line.line,
              serverId: line.id,
              speaker: line.line.mine ? null : friend,
            ),
      ];
      // New server messages follow the last known server message, before any
      // more recent local greeting; first imports precede the local visit.
      final at = existing.lastIndexWhere((e) => e.serverId != null) + 1;
      existing.insertAll(at, added);
      await _save(friend.id, existing, imported: true);
    });
    _queues[friend.id] = next.catchError((Object _) {});
    return next;
  }

  Future<bool> needsServerHistory(String id) async {
    await _queues[id];
    await _load(id);
    return !_imported.contains(id);
  }

  /// Import is complete only after the combined document is durably saved.
  /// Only remove a contiguous boundary overlap; repeated words within the
  /// server conversation are genuine messages and must remain.
  Future<void> prepend(String id, List<ConversationEntry> earlier) {
    final old = _queues[id] ?? Future<void>.value();
    final next = old.then((_) async {
      final existing = await _load(id);
      if (_imported.contains(id)) return;
      var overlap = 0;
      final max = earlier.length < existing.length
          ? earlier.length
          : existing.length;
      for (var n = 1; n <= max; n++) {
        var same = true;
        for (var i = 0; i < n; i++) {
          if (earlier[earlier.length - n + i].line != existing[i].line) {
            same = false;
            break;
          }
        }
        if (same) overlap = n;
      }
      await _save(id, [
        ...earlier.take(earlier.length - overlap),
        ...existing,
      ], imported: true);
    });
    _queues[id] = next.catchError((Object _) {});
    return next;
  }

  Future<List<ConversationEntry>> read(String id) async {
    await _queues[id];
    return _load(id);
  }

  Future<void> append(String id, ConversationEntry entry) {
    final old = _queues[id] ?? Future<void>.value();
    final next = old.then((_) async {
      final entries = await _load(id);
      final delivered = _delivered[id];
      final at = delivered?.indexWhere((e) => e.line == entry.line) ?? -1;
      if (at >= 0) {
        delivered!.removeAt(at);
        return;
      }
      await _save(id, [...entries, entry], imported: _imported.contains(id));
    });
    _queues[id] = next.catchError((Object _) {});
    return next;
  }
}
