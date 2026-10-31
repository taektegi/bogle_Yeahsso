import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../models/character_friend.dart';
import '../local_store.dart';
import '../window_view.dart';
import '../window_view_service.dart';
import 'api_client.dart';
import 'synced_character_repository.dart';

/// Saves complete pairs by stable asset id, never by expiring signed URL.
/// Existing pairs stay usable offline, after failures and after iOS moves the
/// data container during an update. Failed jobs require an explicit retry.
class ApiWindowViews implements WindowViewService {
  ApiWindowViews(
    this.api, {
    required this.store,
    this.pollLimit = 240,
    this.wait = Future<void>.delayed,
  });

  final ApiClient api;
  final FileStore store;
  final int pollLimit;
  final Future<void> Function(Duration) wait;

  @override
  bool supports(CharacterFriend friend) =>
      SyncedCharacterRepository.isServiceId(friend.id);

  Future<WindowView?> _cached(String id) async {
    final json = await store.read('window-$id');
    if (json is! Map) return null;
    final day = json['day'], night = json['night'];
    if (day is! String ||
        !_name.hasMatch(day) ||
        (night != null && (night is! String || !_name.hasMatch(night)))) {
      return null;
    }
    final d = File('${store.art.path}/$day');
    final n = night == null ? null : File('${store.art.path}/$night');
    try {
      await _validate(await d.readAsBytes());
      if (n != null) await _validate(await n.readAsBytes());
      return WindowView(day: d.path, night: n?.path);
    } on Exception {
      return null;
    }
  }

  static final _name = RegExp(r'^window-[a-zA-Z0-9-]+\.png$');
  static final _id = RegExp(r'^[a-zA-Z0-9-]{1,64}$');

  @override
  Future<WindowView?> load(
    CharacterFriend friend, {
    bool regenerate = false,
    bool Function()? active,
  }) async {
    if (!supports(friend)) return null;
    bool alive() => active?.call() ?? true;
    final cached = await _cached(friend.id);
    if (!alive() || (cached != null && !regenerate)) return cached;
    final path = '/v1/characters/${friend.id}/window-view';
    var state = await api.get(path);
    if (!alive()) return cached;
    if (state['status'] == 'missing' || regenerate) {
      state = await api.post(
        path,
        body: {'regenerate': regenerate},
        idempotencyKey: api.newKey(),
      );
    }
    for (var attempt = 0; attempt <= pollLimit && alive(); attempt++) {
      if (regenerate && state['status'] == 'failed') {
        throw const ApiException(
          statusCode: 200,
          code: 'background_failed',
          message: '새 배경을 만들지 못했어요. 기존 풍경을 유지할게요.',
          retryable: true,
        );
      }
      final day = state['day'], night = state['night'];
      if (day is Map &&
          (night == null || night is Map) &&
          state['status'] != 'queued' &&
          state['status'] != 'processing') {
        final view = await _keep(friend.id, day, night);
        return alive() ? view : cached;
      }
      switch (state['status']) {
        case 'failed':
        case 'cancelled':
          final error = state['error'];
          throw ApiException(
            statusCode: 200,
            code: 'background_failed',
            message: error is Map && error['message'] is String
                ? error['message'] as String
                : '배경을 만들지 못했어요.',
            retryable: true,
          );
        case 'succeeded':
          throw const FormatException('배경 파일을 확인할 수 없어요.');
      }
      if (attempt == pollLimit) break;
      // Clamp server advice so malformed responses cannot spin or block forever.
      final delay = (state['pollAfterMs'] as num? ?? 2000).toInt().clamp(
        1000,
        5000,
      );
      await wait(Duration(milliseconds: delay));
      if (!alive()) return cached;
      state = await api.get(path);
    }
    if (!alive()) return cached;
    throw const ApiException(
      statusCode: 0,
      code: 'background_pending',
      message: '배경을 아직 만들고 있어요. 잠시 뒤 다시 확인해 주세요.',
      retryable: true,
    );
  }

  Future<WindowView> _keep(String friendId, Map day, Map? night) async {
    final refs = [day, ?night];
    final files = <File>[];
    final bytes = <Uint8List>[];
    for (final ref in refs) {
      final id = ref['assetId'];
      if (id is! String ||
          !_id.hasMatch(id) ||
          ref['contentType'] != 'image/png') {
        throw const FormatException('잘못된 배경 이미지예요.');
      }
      final file = File('${store.art.path}/window-$id.png');
      // Decode the downloaded data, not merely its content-type or extension.
      final data = await api.download(ref['url'] as String);
      await _validate(data);
      files.add(file);
      bytes.add(data);
    }
    await store.art.create(recursive: true);
    for (var i = 0; i < files.length; i++) {
      final temporary = File('${files[i].path}.tmp');
      await temporary.writeAsBytes(bytes[i], flush: true);
      await temporary.rename(files[i].path);
    }
    final previous = await store.read('window-$friendId');
    await store.write('window-$friendId', {
      'day': files[0].uri.pathSegments.last,
      'night': files.length > 1 ? files[1].uri.pathSegments.last : null,
    });
    // Only remove replaced files after the new complete pair is persisted.
    if (previous is Map) {
      for (final name in [previous['day'], previous['night']]) {
        if (name is String && _name.hasMatch(name)) {
          final old = File('${store.art.path}/$name');
          if (!files.any((f) => f.path == old.path) && await old.exists()) {
            await old.delete();
          }
        }
      }
    }
    return WindowView(
      day: files[0].path,
      night: files.length > 1 ? files[1].path : null,
    );
  }

  Future<void> forget(String friendId) async {
    if (!_id.hasMatch(friendId)) return;
    final saved = await store.read('window-$friendId');
    await store.write('window-$friendId', null);
    if (saved is! Map) return;
    for (final name in [saved['day'], saved['night']]) {
      if (name is! String || !_name.hasMatch(name)) continue;
      try {
        final file = File('${store.art.path}/$name');
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // A busy file may be removed on a later cleanup; never undo deletion.
      }
    }
  }

  static Future<void> _validate(Uint8List bytes) async {
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < 24 ||
        bytes.length > 30 * 1024 * 1024 ||
        [for (var i = 0; i < 8; i++) bytes[i] != signature[i]].contains(true)) {
      throw const FormatException('배경은 PNG여야 해요.');
    }
    final header = ByteData.sublistView(bytes);
    if (header.getUint32(16) != 2048 || header.getUint32(20) != 576) {
      throw const FormatException('배경 크기를 확인해 주세요.');
    }
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      if (codec.frameCount != 1) throw const FormatException('배경은 한 장이어야 해요.');
      final frame = await codec.getNextFrame();
      frame.image.dispose();
    } finally {
      codec.dispose();
    }
  }
}
