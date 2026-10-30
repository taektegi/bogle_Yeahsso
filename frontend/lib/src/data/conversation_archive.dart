import '../models/character_friend.dart';
import 'chat_service.dart';
import 'local_store.dart';

class ConversationEntry {
  const ConversationEntry(this.line, {this.speaker});
  final ChatLine line;
  final CharacterFriend? speaker;
  Map<String, Object?> toJson() => {
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
  ConversationArchive({this.store});
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
    );
  }

  final _imported = <String>{};

  Future<List<ConversationEntry>> _load(String id) async {
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
      await _save(id, [...entries, entry], imported: _imported.contains(id));
    });
    _queues[id] = next.catchError((Object _) {});
    return next;
  }
}
