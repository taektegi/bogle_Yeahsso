import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

/// What the app keeps on the device between launches: one small JSON
/// document per name (friends made here, care, memories, orders, the
/// profile). The service keeps the rest.
abstract interface class LocalStore {
  /// The document saved as [name], or null if there is none (or it can't
  /// be found). Unrecoverable read errors must be reported, never reset.
  Future<Object?> read(String name);

  Future<void> write(String name, Object? json);
}

/// Files in the app's own folder (Application Support on iOS, which the
/// system doesn't clear). Writes go to a temporary file first and are then
/// renamed, so a crash mid-write never leaves half a document; writes to
/// one name happen in order.
class FileStore implements LocalStore {
  FileStore(this.folder);
  final Directory folder;
  final _queue = <String, Future<void>>{};

  File _file(String name) => File('${folder.path}/$name.json');

  /// UI may offer a fresh document only after explaining what will be lost.
  Future<bool> Function(String name)? onRecovery;
  final _snapshots = <String, String?>{};
  final _blocked = <String>{};
  final _repair = <String>{};
  final _recoveries = <String, Future<bool>>{};

  Future<bool> _recover(String name) => _recoveries[name] ??= () async {
    try {
      if (await onRecovery?.call(name) != true) return false;
      await quarantine(name);
      return true;
    } finally {
      _recoveries.remove(name);
    }
  }();

  void _remember(String name, String? text) {
    _snapshots.remove(name);
    _snapshots[name] = text;
    while (_snapshots.length > 12 ||
        _snapshots.values.fold<int>(0, (n, s) => n + (s?.length ?? 0)) >
            8 * 1024 * 1024) {
      _snapshots.remove(_snapshots.keys.first);
    }
  }

  static Future<String> _encode(Object? json) =>
      Isolate.run(() => jsonEncode(json));

  static Future<Object?> _decode(String text) => text.length < 65536
      ? Future.value(jsonDecode(text))
      : Isolate.run(() => jsonDecode(text));

  /// Validate complete documents before choosing a snapshot, not just JSON.
  Future<T?> readValidated<T>(String name, T Function(Object) decode) async {
    await _queue[name];
    _snapshots.remove(name);
    var damaged = false;
    for (final file in [_file(name), File('${_file(name).path}.bak')]) {
      if (!await file.exists()) continue;
      final text = await file.readAsString();
      try {
        final json = await _decode(text);
        final value = json == null ? null : decode(json);
        if (file.path == _file(name).path) {
          _repair.remove(name);
        } else {
          _repair.add(name);
        }
        _remember(name, text);
        _blocked.remove(name);
        return value;
      } catch (error) {
        if (error is FileSystemException) rethrow;
        damaged = true;
      }
    }
    if (!damaged) {
      _blocked.remove(name);
      _remember(name, null);
      return null;
    }
    _blocked.add(name);
    if (await _recover(name)) return null;
    throw const StoreRecoveryException();
  }

  /// Preserve both originals before allowing an explicitly accepted reset.
  Future<void> quarantine(String name) async {
    await _queue[name];
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final originals = [_file(name), File('${_file(name).path}.bak')];
    // Copy all first: if any copy fails, neither original is removed.
    for (final file in originals) {
      if (await file.exists()) await file.copy('${file.path}.corrupt-$stamp');
    }
    for (final file in originals) {
      if (await file.exists()) await file.delete();
    }
    _remember(name, null);
    _blocked.remove(name);
    _repair.remove(name);
  }

  @override
  Future<Object?> read(String name) => readValidated(name, (value) => value);

  Future<void> _replace(File file, String text) async {
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(text, flush: true);
    await temp.rename(file.path);
  }

  @override
  Future<void> write(String name, Object? json) {
    final previous = _queue[name] ?? Future<void>.value();
    final next = previous.then((_) async {
      if (_blocked.contains(name)) throw const StoreRecoveryException();
      final text = await _encode(json);
      String? old;
      if (_snapshots.containsKey(name)) {
        old = _snapshots[name];
      } else {
        // Read within this queue without waiting on this pending write.
        var damaged = false;
        for (final file in [_file(name), File('${_file(name).path}.bak')]) {
          if (!await file.exists()) continue;
          final candidate = await file.readAsString();
          try {
            await _decode(candidate);
            old = candidate;
            if (file.path != _file(name).path) _repair.add(name);
            break;
          } on FormatException {
            damaged = true;
          }
        }
        if (old == null && damaged) throw const StoreRecoveryException();
      }
      if (old == text && !_repair.contains(name)) return;
      await folder.create(recursive: true);
      await _replace(File('${_file(name).path}.bak'), old ?? text);
      await _replace(_file(name), text);
      // Commit cache only after the primary replacement succeeds.
      _remember(name, text);
      _repair.remove(name);
    });
    _queue[name] = next.catchError((Object _) {});
    return next;
  }

  /// Where friends' pictures made on the device are kept.
  Directory get art => Directory('${folder.path}/art');

  /// A picture saved in [art] by an earlier install keeps its file name but
  /// the app's folder can move (iOS changes it on updates): find it again.
  String relocate(String path) {
    if (!path.startsWith('/') || File(path).existsSync()) return path;
    final name = path.split('/').last;
    final moved = File('${art.path}/$name');
    return moved.existsSync() ? moved.path : path;
  }
}

/// Keeps documents in memory only (tests, or when there is no folder).
class MemoryStore implements LocalStore {
  final _documents = <String, String>{};

  @override
  Future<Object?> read(String name) async {
    final text = _documents[name];
    return text == null ? null : jsonDecode(text);
  }

  @override
  Future<void> write(String name, Object? json) async =>
      _documents[name] = jsonEncode(json);
}

/// Both copies are unreadable: preserve them instead of overwriting user data.
class StoreRecoveryException implements Exception {
  const StoreRecoveryException();
  String get message =>
      '저장한 정보를 읽지 못했어요. 데이터를 지우지 말고 복구 안내에서 다시 시도하거나, 원본을 보관하고 새로 시작할 수 있어요.';
}

/// File stores can try the backup on semantic errors too; test/custom stores
/// keep the same validation contract without needing filesystem APIs.
Future<T?> readDocument<T>(
  LocalStore? store,
  String name,
  T Function(Object) decode,
) async {
  if (store is FileStore) return store.readValidated(name, decode);
  final saved = await store?.read(name);
  if (saved == null) return null;
  try {
    return decode(saved);
  } catch (_) {
    throw const StoreRecoveryException();
  }
}
