import 'dart:async';
import 'dart:io';
import 'local_store.dart';
import 'conversation_archive.dart';

/// Durable grace-period cleanup, shared by local and server-backed friends.
class RetiredFriends {
  RetiredFriends(this.store, this.activePaths);
  final LocalStore? store;
  final List<String> Function() activePaths;
  Timer? _timer;
  Future<void> _queue = Future.value();
  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<Map<String, dynamic>> _read() async =>
      await readDocument(
        store,
        'retired_friends',
        (v) => Map<String, dynamic>.from(v as Map),
      ) ??
      {};
  Future<void> retire(String id, List<String> paths) => _serial(() async {
    final tasks = await _read();
    tasks[id] = {
      'paths': paths,
      'after': DateTime.now()
          .add(const Duration(seconds: 12))
          .millisecondsSinceEpoch,
    };
    await store?.write('retired_friends', tasks);
    _schedule();
  });
  Future<void> cancel(String id) => _serial(() async {
    final tasks = await _read();
    tasks.remove(id);
    await store?.write('retired_friends', tasks);
    ConversationArchive.allow(id, store: store);
  });
  void _schedule() {
    if (store is! FileStore) return;
    _timer?.cancel();
    _timer = Timer(
      const Duration(seconds: 13),
      () => sweep().catchError((Object _) {}),
    );
  }

  Future<void> sweep() => _serial(() async {
    if (store is! FileStore) return;
    final files = store as FileStore;
    final tasks = await _read();
    final active = activePaths().toSet();
    for (final id in List.of(tasks.keys)) {
      final task = tasks[id] as Map;
      if ((task['after'] as int) > DateTime.now().millisecondsSinceEpoch) {
        continue;
      }
      if ((task['paths'] as List).cast<String>().any(
        (p) => active.contains(files.relocate(p)),
      )) {
        tasks.remove(id);
        continue;
      }
      for (final path in (task['paths'] as List).cast<String>()) {
        final moved = files.relocate(path);
        if (active.contains(moved) ||
            !moved.startsWith('${files.art.absolute.path}/')) {
          continue;
        }
        final stem = moved.endsWith('.png')
            ? moved.substring(0, moved.length - 4)
            : moved;
        for (final p in {moved, '$stem.thumb.png', '$stem.face.json'}) {
          if (active.contains(p)) {
            continue;
          }
          final file = File(p);
          if (await file.exists()) await file.delete();
        }
      }
      ConversationArchive.discardCached(id, store: store);
      await files.removeDocument('conversation-${Uri.encodeComponent(id)}');
      await files.removeDocument('window-$id');
      tasks.remove(id);
    }
    await store?.write('retired_friends', tasks);
    if (tasks.isNotEmpty) _schedule();
  });
}
