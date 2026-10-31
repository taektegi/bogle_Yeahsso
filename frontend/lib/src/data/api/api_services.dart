import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart' show listEquals, compute;
import 'package:crypto/crypto.dart';
import 'package:characters/characters.dart';

import 'dart:convert';
import 'dart:io';

import '../../models/character_friend.dart';
import '../character_generation.dart';
import '../character_repository.dart';
import '../chat_service.dart';
import '../local_store.dart';
import '../motion_service.dart';
import '../profile_repository.dart';
import 'api_client.dart';
import 'device_art.dart';
import 'outbox.dart';
import 'synced_character_repository.dart';

// ---------------------------------------------------------------------------
// Character generation: upload → /v1/generations → poll
// ---------------------------------------------------------------------------

/// Makes friends with the character service: uploads the drawing or photo
/// once, starts a generation and follows it every `pollAfterMs` until it
/// succeeds or fails. A retry of the same picture reuses the upload and
/// reuses its idempotency key until the server confirms a terminal failure.
class ApiCharacterGenerator implements CharacterGenerator {
  ApiCharacterGenerator(
    this.api, {
    required this.art,
    LocalStore? store,
    this.giveUpAfter = const Duration(minutes: 5),
    this.faceGiveUpAfter = const Duration(minutes: 3),
    Future<void> Function(Duration)? wait,
  }) : _store = store,
       _wait = wait ?? Future<void>.delayed;

  final ApiClient api;

  /// Where a finished friend's pictures are kept on the iPad.
  final DeviceArt art;
  final LocalStore? _store;

  /// The job to pick up after a relaunch (the service keeps jobs a day).
  static const _pendingName = 'pending_generation';

  Future<void> _remember(String? jobId, {String? sketchRevision}) async {
    try {
      await _store?.write(
        _pendingName,
        sketchRevision == null || jobId == null
            ? jobId
            : {'jobId': jobId, 'sketchRevision': sketchRevision},
      );
    } on Object {
      // Not kept: nothing to pick up after a relaunch, no harm otherwise.
    }
  }

  @override
  Future<CharacterGenerationJob?> unfinished() async {
    // 앱이 꺼지기 전에 받지 못한 얼굴 좌표도 다시 받으러 간다.
    unawaited(_resumeFaces());
    final pending = await _store?.read(_pendingName);
    final id = pending is Map ? pending['jobId'] : pending;
    final revision = pending is Map ? pending['sketchRevision'] : null;
    if (id is! String && !(pending is Map && pending['requestKey'] is String)) {
      return null;
    }
    if (id is! String) {
      return _DeferredGeneration(() async {
        final Map<String, dynamic> state;
        try {
          state = await api.post(
            '/v1/generations',
            body: {
              'sourceAssetId': (pending as Map)['sourceAssetId'],
              'sourceType': pending['sourceType'],
              if (pending['photoMode'] != null)
                'photoMode': pending['photoMode'],
            },
            idempotencyKey: pending['requestKey'] as String,
          );
        } on ApiException catch (error) {
          if (error.statusCode == 404 || error.statusCode == 410) {
            await _remember(null);
          }
          throw GenerationError(
            error.code,
            error.message,
            retryable: error.retryable,
          );
        }
        final job = _ApiGenerationJob(
          this,
          null,
          jobId: state['jobId'] as String,
          first: state,
          sketchRevision: revision is String ? revision : null,
        )..run();
        return job;
      });
    }
    final Map<String, dynamic> state;
    try {
      state = await api.get('/v1/generations/$id');
    } on ApiException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 410) {
        await _remember(null);
      }
      return null;
    }
    if (state['status'] case 'failed' || 'cancelled') {
      await _remember(null);
      return null;
    }
    return _ApiGenerationJob(
      this,
      null,
      jobId: state['jobId'] as String? ?? id as String?,
      first: state,
      sketchRevision: revision is String ? revision : null,
    )..run();
  }

  @override
  Future<void> finished(String jobId) async {
    final used = _jobInputs.remove(jobId);
    if (used != null) {
      _attempts.remove(used.$1);
      _uploads.remove(used.$1);
      final input = used.$2.target;
      if (input != null) _completed[input] = null;
    }
    final pending = await _store?.read(_pendingName);
    if ((pending is Map ? pending['jobId'] : pending) == jobId) {
      await _remember(null);
    }
  }

  final Duration giveUpAfter;

  /// 그림보다 늦게 오는 얼굴 좌표를 기다리는 시간. 서버는 최대 2분 안에 분석을 끝낸다.
  final Duration faceGiveUpAfter;
  final Future<void> Function(Duration) _wait;
  final _inputHashes = Expando<Future<String>>();
  final _uploads = <String, Future<String>>{};
  final _attempts = <String, String>{};
  Future<String> _inputKey(GenerationInput input) =>
      _inputHashes[input] ??= compute(
        _imageDigest,
        input.image,
      ).then((hash) => '${input.source.name}-${input.photoMode.name}-$hash');

  Future<void> _clearAttempt(
    GenerationInput input, {
    bool forgetSource = false,
  }) async {
    final digest = await _inputKey(input);
    _attempts.remove(digest);
    if (forgetSource) _uploads.remove(digest);
  }

  final _completed = Expando<String>();
  final _jobInputs = <String, (String, WeakReference<GenerationInput>)>{};

  // -------------------------------------------------------------------------
  // 얼굴 좌표는 그림보다 늦게 온다. 서버는 그림이 완성되면 바로 succeeded를
  // 알리고(faceStatus: pending) 얼굴 분석을 이어서 한다. 아이는 그동안 친구
  // 설정을 하고, 앱은 뒤에서 작업을 다시 조회해 좌표가 오면 그림 옆
  // (`<jobId>.face.json`)에 둔다. 좌표가 끝내 없어도 친구는 몸 전체로 움직인다.
  // -------------------------------------------------------------------------

  /// 아직 얼굴 좌표를 받지 못한 작업. 앱을 다시 켜면 이어서 묻는다.
  static const _pendingFacesName = 'pending_faces';
  final _followingFaces = <String, Future<void>>{};
  Future<void> _facesKept = Future.value();

  /// 작업 [jobId]의 얼굴 좌표가 오거나 없다고 확정될 때까지 조회하고,
  /// 오면 친구 그림 옆에 저장한다. 예외를 밖으로 던지지 않는다.
  Future<void> followFace(String jobId) =>
      _followingFaces[jobId] ??= _followFace(jobId).whenComplete(() {
        // 화살표 함수로 쓰면 제거한 future를 돌려줘 자기 자신을 기다리게 된다.
        _followingFaces.remove(jobId);
      });

  @override
  Future<void>? faceStillComing(String jobId) => _followingFaces[jobId];

  Future<void> _followFace(String jobId) async {
    final deadline = DateTime.now().add(faceGiveUpAfter);
    var delay = const Duration(seconds: 2);
    var misses = 0;
    try {
      while (true) {
        await _wait(delay);
        final Map<String, dynamic> state;
        try {
          state = await api.get('/v1/generations/$jobId');
          misses = 0;
        } on ApiException catch (e) {
          // 작업이 지워졌거나(404) 계속 연결되지 않으면 그만둔다.
          if (!e.retryable || ++misses > 5) break;
          if (DateTime.now().isAfter(deadline)) break;
          continue;
        }
        if (state['faceStatus'] != 'pending') {
          if (state['faceStatus'] == 'ready' && state['face'] != null) {
            await art.keepFace(jobId, state['face'] as Object);
          }
          break;
        }
        if (DateTime.now().isAfter(deadline)) break;
        delay = Duration(
          milliseconds: (state['pollAfterMs'] as num?)?.toInt() ?? 2000,
        );
      }
    } on Object {
      // 얼굴 좌표는 선택 기능이다. 받지 못해도 친구 만들기는 그대로 끝난다.
    }
    await _rememberFace(jobId, pending: false);
  }

  Future<void> _resumeFaces() async {
    for (final id in await _pendingFaces()) {
      unawaited(followFace(id));
    }
  }

  Future<List<String>> _pendingFaces() async {
    try {
      final kept = await _store?.read(_pendingFacesName);
      return [
        for (final id in kept is List ? kept : const [])
          if (id is String) id,
      ];
    } on Object {
      return [];
    }
  }

  /// 저장 목록은 한 번에 하나씩 고친다. 동시에 끝난 두 작업이 서로의 변경을 덮지 않게 한다.
  Future<void> _rememberFace(String jobId, {required bool pending}) {
    Future<void> change() async {
      try {
        final ids = await _pendingFaces()
          ..remove(jobId);
        if (pending) ids.add(jobId);
        await _store?.write(_pendingFacesName, ids);
      } on Object {
        // 저장하지 못하면 앱을 다시 켰을 때의 재조회만 빠진다.
      }
    }

    return _facesKept = _facesKept.then((_) => change());
  }

  @override
  CharacterGenerationJob start(GenerationInput input) =>
      _ApiGenerationJob(this, input, jobId: _completed[input])..run();

  /// The uploaded picture's asset id, uploading it the first time.
  Future<String> source(GenerationInput input) async {
    final digest = await _inputKey(input);
    final known = _uploads[digest];
    if (known != null) return known;
    if (_uploads.length >= 8) {
      final oldest = _uploads.keys.first;
      _uploads.remove(oldest);
      _attempts.remove(oldest);
    }
    final upload = _upload(input);
    _uploads[digest] = upload;
    try {
      return await upload;
    } catch (_) {
      _uploads.remove(digest);
      rethrow;
    }
  }

  Future<String> _upload(GenerationInput input) async {
    final bytes = await fitForUpload(input.image);
    final png = bytes.length > 4 && bytes[0] == 0x89;
    final json = await api.upload(
      '/v1/assets',
      UploadFile(
        'file',
        bytes,
        input.source == GenerationSource.drawing
            ? 'drawing.png'
            : (png ? 'photo.png' : 'photo.jpg'),
        png ? 'image/png' : 'image/jpeg',
      ),
    );
    return json['assetId'] as String;
  }
}

/// The service takes PNG or JPEG up to 10 MiB, each side 64–4096 px.
/// Anything bigger is scaled down (as a PNG) to fit.
Future<Uint8List> fitForUpload(
  Uint8List bytes, {
  int maxBytes = 9 * 1024 * 1024,
  int maxSide = 4096,
}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final width = descriptor.width, height = descriptor.height;
  descriptor.dispose();
  buffer.dispose();
  if (math.min(width, height) < 64) {
    throw const GenerationError(
      'invalid_source_image',
      '사진이나 그림을 조금 더 넓게 골라 주세요.',
      retryable: false,
    );
  }
  final supported =
      (bytes.length >= 8 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4e &&
          bytes[3] == 0x47) ||
      (bytes.length >= 3 &&
          bytes[0] == 0xff &&
          bytes[1] == 0xd8 &&
          bytes[2] == 0xff);
  if (supported &&
      bytes.length <= maxBytes &&
      math.max(width, height) <= maxSide) {
    return bytes;
  }
  var side = math.min(maxSide, math.max(width, height));
  while (true) {
    final scale = side / math.max(width, height);
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: math.max(1, (width * scale).round()),
      targetHeight: math.max(1, (height * scale).round()),
    );
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    if (math.min(image.width, image.height) < 64) {
      image.dispose();
      throw const GenerationError(
        'invalid_source_image',
        '사진이나 그림을 조금 더 넓게 골라 주세요.',
        retryable: false,
      );
    }
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final out = png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
    if (out.length <= maxBytes || side <= 512) return out;
    side = (side * .75).round();
  }
}

class _ApiGenerationJob implements CharacterGenerationJob {
  _ApiGenerationJob(
    this.generator,
    this.input, {
    String? jobId,
    Map<String, dynamic>? first,
    String? sketchRevision,
  }) : _jobId = jobId,
       _first = first,
       _resumedSketchRevision = sketchRevision;
  final String? _resumedSketchRevision;
  String? get sketchRevision => input == null
      ? _resumedSketchRevision
      : input!.source == GenerationSource.drawing
      ? input!.sketchRevision
      : null;
  final ApiCharacterGenerator generator;

  /// The picture to make a friend from; null when picking up a job
  /// started before a relaunch.
  final GenerationInput? input;
  final Map<String, dynamic>? _first;
  final _result = Completer<GeneratedArt>();
  String? _jobId;
  bool _cancelled = false;
  bool _terminal = false;

  ApiClient get _api => generator.api;

  @override
  Future<GeneratedArt> get result => _result.future;

  @override
  void cancel() {
    // Already finished (the loading page leaving after success): the
    // friend is still to be made from it, so nothing to cancel.
    if (_cancelled || _result.isCompleted) return;
    _cancelled = true;
    if (input case final source?) unawaited(generator._clearAttempt(source));
    _result.completeError(GenerationCancelled());
    final id = _jobId;
    unawaited(generator._remember(null));
    // The service cancels only when asked; its answer doesn't matter here:
    // a cancelled attempt never moves the app on, even if it finished.
    if (id != null) {
      unawaited(
        _api
            .post('/v1/generations/$id/cancel')
            .then<void>((_) {}, onError: (Object _) {}),
      );
    }
  }

  Future<void> run() async {
    try {
      final art = await _follow();
      if (!_result.isCompleted) _result.complete(art);
    } catch (error, stack) {
      // A failed or cancelled job is not one to pick up again.
      if (error is GenerationCancelled ||
          (error is GenerationError && (!error.retryable || _terminal))) {
        await generator._remember(null);
      }
      if (input case final source?) {
        if (error is GenerationError &&
            (error.code == 'generation_expired' || error.code == 'not_found')) {
          generator._completed[source] = null;
          await generator._clearAttempt(source, forgetSource: true);
        }
      }
      if (!_result.isCompleted) _result.completeError(error, stack);
    }
  }

  static GenerationError _from(ApiException e) => GenerationError(
    e.code == 'invalid_image' ? 'invalid_source_image' : e.code,
    e.message,
    retryable: e.retryable,
  );

  /// Brings the finished friend's pictures and face map onto the iPad, so
  /// from now on it is drawn from there, with no network.
  Future<({String art, String? thumbnail})> _keep(
    String id,
    Map<String, dynamic> state,
  ) async {
    try {
      final artRef = ImageRef.fromJson(state['art'] as Map<String, dynamic>);
      final thumb = state['thumbnail'] as Map<String, dynamic>?;
      return await generator.art.keep(
        id,
        art: await _api.download(artRef.url),
        thumbnail: thumb == null
            ? null
            : await _api.download(ImageRef.fromJson(thumb).url),
        face: state['face'],
      );
    } on ApiException catch (e) {
      // The friend is made; only bringing it over failed. Trying again
      // (or picking it up next launch) fetches it anew.
      throw GenerationError(
        'generation_unavailable',
        e.message,
        retryable: true,
      );
    } on FormatException catch (e) {
      if (input case final source?) generator._completed[source] = null;
      throw GenerationError(
        'generation_invalid_result',
        e.message,
        retryable: true,
      );
    }
  }

  Future<GeneratedArt> _follow() async {
    final Map<String, dynamic> started;
    if (_first case final first?) {
      started = first;
    } else if (_jobId case final id?) {
      // 완료된 작업을 재조회해 만료된 이미지 주소도 새로 받는다.
      try {
        started = await _api.get('/v1/generations/$id');
      } on ApiException catch (e) {
        throw _from(e);
      }
    } else {
      final input = this.input!;
      try {
        final source = await generator.source(input);
        if (_cancelled) throw GenerationCancelled();
        final digest = await generator._inputKey(input);
        final key = generator._attempts.putIfAbsent(digest, _api.newKey);
        await generator._store?.write(ApiCharacterGenerator._pendingName, {
          'requestKey': key,
          'sourceAssetId': source,
          'sourceType': input.source.name,
          if (input.photoMode == PhotoMode.subject)
            'photoMode': input.photoMode.name,
          'sketchRevision': sketchRevision,
        });
        started = await _api.post(
          '/v1/generations',
          body: {
            'sourceAssetId': source,
            'sourceType': input.source.name,
            if (input.photoMode == PhotoMode.subject)
              'photoMode': input.photoMode.name,
          },
          idempotencyKey: key,
        );
      } on ApiException catch (e) {
        throw _from(e);
      }
    }
    final id = _jobId = started['jobId'] as String? ?? _jobId!;
    if (input case final source?) {
      generator._jobInputs[id] = (
        await generator._inputKey(source),
        WeakReference(source),
      );
      while (generator._jobInputs.length > 8) {
        generator._jobInputs.remove(generator._jobInputs.keys.first);
      }
    }
    // Remembered until the friend is made, so a relaunch can pick it up.
    await generator._remember(id, sketchRevision: sketchRevision);
    if (_cancelled) {
      cancel();
      throw GenerationCancelled();
    }
    final deadline = DateTime.now().add(generator.giveUpAfter);
    var state = started;
    var misses = 0;
    while (true) {
      switch (state['status']) {
        case 'succeeded':
          // 생성은 성공했는데 다운로드만 끊긴 경우 같은 결과를 다시 받는다.
          if (input case final source?) generator._completed[source] = id;
          final kept = await _keep(id, state);
          // 얼굴 분석은 아직 진행 중일 수 있다. 기다리지 않고 설정 화면으로 가되,
          // 앱이 꺼져도 다시 물을 수 있게 먼저 기록해 둔다.
          if (state['faceStatus'] == 'pending') {
            await generator._rememberFace(id, pending: true);
            unawaited(generator.followFace(id));
          }
          return GeneratedArt(
            assetPath: kept.art,
            thumbnailPath: kept.thumbnail,
            accentHex:
                (state['accentArgb'] as num?)?.toInt() ??
                GeneratedArt.defaultAccent,
            jobId: id,
            sketchRevision: sketchRevision,
          );
        case 'failed':
          _terminal = true;
          if (input case final source?) await generator._clearAttempt(source);
          final error = (state['error'] as Map?)?.cast<String, dynamic>();
          throw GenerationError(
            error?['code'] as String? ?? 'generation_unavailable',
            error?['message'] as String? ?? '잠시 후 다시 시도해 주세요.',
            retryable: error?['retryable'] as bool? ?? true,
          );
        case 'cancelled':
          if (input case final source?) await generator._clearAttempt(source);
          throw GenerationCancelled();
      }
      if (DateTime.now().isAfter(deadline)) {
        throw const GenerationError(
          'generation_timeout',
          '친구를 만드는 데 시간이 너무 걸렸어요. 다시 해 볼까요?',
          retryable: true,
        );
      }
      await generator._wait(
        Duration(milliseconds: (state['pollAfterMs'] as num?)?.toInt() ?? 2000),
      );
      if (_cancelled) throw GenerationCancelled();
      try {
        state = await _api.get('/v1/generations/$id');
        misses = 0;
      } on ApiException catch (e) {
        // A dropped connection mid-wait doesn't end the job: keep asking.
        if (!e.retryable || ++misses > 5) throw _from(e);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Chat: /v1/characters/{id}/messages
// ---------------------------------------------------------------------------

/// The friend's answers come from the service (AI, or its own scripted
/// lines when the AI can't). Starter friends, and a friend the service says
/// is asleep, answer from the app's lines.
class ApiChatService implements ChatService, ServerChatHistory {
  ApiChatService(this.api, {this.beforeReply, this.onExchange});
  final Future<void> Function(CharacterFriend, List<ServerChatLine>)?
  onExchange;
  final ApiClient api;
  final Future<void> Function()? beforeReply;

  @override
  Future<String?> replyTo(CharacterFriend friend, String text) async {
    if (!SyncedCharacterRepository.isServiceId(friend.id)) return null;
    final message = text.trim();
    if (message.isEmpty) return null;
    await beforeReply?.call();
    try {
      final json = await api.post(
        '/v1/characters/${friend.id}/messages',
        body: {
          'clientMessageId': api.newKey(),
          'text': message.characters.take(200).toString(),
        },
        timeout: const Duration(seconds: 25),
      );
      if (onExchange != null) {
        try {
          await onExchange!(friend, [
            for (final key in ['userMessage', 'assistantMessage'])
              if (json[key] case {
                'id': final String id,
                'text': final String text,
              })
                (id: id, line: (mine: key == 'userMessage', text: text)),
          ]);
        } catch (_) {
          /* The next server import repairs missing IDs. */
        }
      }
      return (json['assistantMessage'] as Map?)?['text'] as String?;
    } on ApiException catch (e) {
      if (e.code == 'character_asleep') return null;
      rethrow;
    }
  }

  @override
  Future<List<ServerChatLine>> historyEntries(CharacterFriend friend) async {
    if (!SyncedCharacterRepository.isServiceId(friend.id)) return [];
    final newest = <ServerChatLine>[];
    String? cursor;
    final seen = <String>{};
    do {
      final page = await api.get(
        '/v1/characters/${friend.id}/messages',
        query: {'limit': '100', 'before': ?cursor},
      );
      for (final item in page['items'] as List) {
        if (item case {
          'id': final String id,
          'role': final String role,
          'text': final String text,
        }) {
          if (seen.add(id)) {
            newest.add((id: id, line: (mine: role == 'user', text: text)));
          }
        }
      }
      final next = page['nextCursor'] as String?;
      if (next == cursor) break;
      cursor = next;
    } while (cursor != null && newest.length < 500);
    return newest.take(500).toList().reversed.toList();
  }

  /// The last 30 lines, oldest first.
  @override
  Future<List<ChatLine>> history(CharacterFriend friend) async {
    if (!SyncedCharacterRepository.isServiceId(friend.id)) return const [];
    final json = await api.get(
      '/v1/characters/${friend.id}/messages',
      query: {'limit': '30'},
    );
    return [
      for (final item in (json['items'] as List).reversed)
        if (item case {'role': final String role, 'text': final String text})
          (mine: role == 'user', text: text),
    ];
  }
}

// ---------------------------------------------------------------------------
// Motion clips: /v1/characters/{id}/motion
// ---------------------------------------------------------------------------

/// Clips the service made from the friend's art, kept on the iPad once they
/// are ready: later visits play them from there, with no network. While
/// they are being made it asks again every two seconds, up to
/// [giveUpAfter]; a friend whose art can't be animated (or a starter friend)
/// uses the app's own motions.
class ApiMotionService implements MotionService {
  ApiMotionService(
    this.api, {
    this.folder,
    this.poll = const Duration(seconds: 2),
    this.giveUpAfter = const Duration(minutes: 3),
  });

  final ApiClient api;

  /// Where clips are kept (`<folder>/<friend id>/`); null keeps nothing.
  final Directory? folder;
  final Duration poll;
  final Duration giveUpAfter;
  final _asking = <String, Future<Map<MotionClipKind, MotionClip>?>>{};

  @override
  Future<Map<MotionClipKind, MotionClip>?> clipsFor(CharacterFriend friend) {
    if (!SyncedCharacterRepository.isServiceId(friend.id)) {
      return Future.value();
    }
    return _asking[friend.id] ??= _clips(friend.id).whenComplete(() {
      // A block, not an arrow: returning the removed future would make
      // this wait on itself.
      _asking.remove(friend.id);
    });
  }

  Future<Map<MotionClipKind, MotionClip>?> _clips(String id) async {
    final kept = await _kept(id);
    if (kept != null) return kept;
    try {
      return await _fetch(id);
    } on Object {
      return null; // offline or failed: the app's motions, ask next visit
    }
  }

  File? _index(String id) =>
      folder == null ? null : File('${folder!.path}/$id/clips.json');

  /// Clips saved on an earlier visit.
  Future<Map<MotionClipKind, MotionClip>?> _kept(String id) async {
    final index = _index(id);
    if (index == null || !await index.exists()) return null;
    try {
      final json = (jsonDecode(await index.readAsString()) as Map)
          .cast<String, dynamic>();
      final clips = _parse(json, (url) => url);
      final allThere = clips.values.every((c) => File(c.url).existsSync());
      return clips.isEmpty || !allThere ? null : clips;
    } on Object {
      return null;
    }
  }

  static Map<MotionClipKind, MotionClip> _parse(
    Map<String, dynamic> clips,
    String Function(String url) where,
  ) => {
    for (final kind in MotionClipKind.values)
      if (clips[kind.name] case {
        'url': final String url,
        'box': final List box,
      })
        kind: MotionClip(
          where(url),
          Rect.fromLTRB(
            (box[0] as num).toDouble(),
            (box[1] as num).toDouble(),
            (box[2] as num).toDouble(),
            (box[3] as num).toDouble(),
          ),
        ),
  };

  Future<Map<MotionClipKind, MotionClip>?> _fetch(String id) async {
    final deadline = DateTime.now().add(giveUpAfter);
    while (true) {
      final state = await api.get('/v1/characters/$id/motion');
      switch (state['status']) {
        case 'ready':
          final clips = _parse(
            (state['clips'] as Map).cast<String, dynamic>(),
            (url) => url,
          );
          return await _keep(id, clips) ?? clips;
        case 'queued' || 'working':
          if (DateTime.now().isAfter(deadline)) return null;
          await Future<void>.delayed(poll);
        default:
          return null; // unsupported or failed: the app's motions
      }
    }
  }

  /// Saves the clips on the iPad and returns them from there; null (play
  /// them from the service this once) if they couldn't be saved.
  Future<Map<MotionClipKind, MotionClip>?> _keep(
    String id,
    Map<MotionClipKind, MotionClip> clips,
  ) async {
    final index = _index(id);
    if (index == null) return null;
    try {
      await index.parent.create(recursive: true);
      final saved = <MotionClipKind, MotionClip>{};
      for (final MapEntry(key: kind, value: clip) in clips.entries) {
        final file = File('${index.parent.path}/${kind.name}.gif');
        await file.writeAsBytes(await api.download(clip.url), flush: true);
        saved[kind] = MotionClip(file.path, clip.box);
      }
      await index.writeAsString(
        jsonEncode({
          for (final MapEntry(key: kind, value: clip) in saved.entries)
            kind.name: {
              'url': clip.url,
              'box': [
                clip.box.left,
                clip.box.top,
                clip.box.right,
                clip.box.bottom,
              ],
            },
        }),
      );
      return saved;
    } on Object {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Profile: kept on the iPad, sent to /v1/me
// ---------------------------------------------------------------------------

/// The profile lives on the iPad like the friends; changes reach the
/// service through the [Outbox]. Its avatar is one of the child's friends
/// on the service (`avatarCharacterId`); a starter friend's picture, which
/// the service doesn't know, is kept on the iPad only.
class SyncedProfileRepository implements ProfileRepository {
  SyncedProfileRepository(
    this.api, {
    required this.local,
    required this.characters,
    required this.outbox,
    LocalStore? store,
  }) : _store = store;

  final ApiClient api;
  final InMemoryProfileRepository local;
  final CharacterRepository characters;
  final Outbox outbox;
  final LocalStore? _store;

  @override
  Future<UserProfile> fetchProfile() => local.fetchProfile();

  @override
  Future<UserProfile> saveProfile(UserProfile profile) async {
    final before = await local.fetchProfile();
    final friends = await characters.fetchFriends();
    final avatar = friends
        .where((f) => f.assetPath == profile.avatar)
        .firstOrNull;
    final avatarId =
        avatar != null && SyncedCharacterRepository.isServiceId(avatar.id)
        ? avatar.id
        : null;
    await outbox.patchProfile({
      if (before.nickname != profile.nickname) 'nickname': profile.nickname,
      if (before.bio != profile.bio) 'bio': profile.bio,
      if (!listEquals(before.interests, profile.interests))
        'interests': profile.interests,
      if (before.profileColor != profile.profileColor)
        'profileColor': profile.profileColor,
      if (before.friendNotifications != profile.friendNotifications)
        'friendNotifications': profile.friendNotifications,
      if (before.orderNotifications != profile.orderNotifications)
        'orderNotifications': profile.orderNotifications,
      if (before.avatar != profile.avatar) 'avatarCharacterId': avatarId,
    });
    return local.saveProfile(profile);
  }

  /// On a fresh install the iPad has no profile yet: take the nickname and
  /// settings the service kept.
  Future<void> pull() async {
    final pending = await outbox.pendingFields(null);
    final json = await api.get('/v1/me');
    final current = await local.fetchProfile();
    final avatarId = json['avatarCharacterId'];
    final friends = avatarId == null
        ? <CharacterFriend>[]
        : await characters.fetchFriends();
    final avatar = friends.where((friend) => friend.id == avatarId).firstOrNull;
    // Retry on the next sync if its picture could not be restored yet.
    await _store?.write(
      'pending_profile_avatar',
      avatarId != null && avatar == null ? avatarId : null,
    );
    await local.saveProfile(
      current.copyWith(
        avatar: pending.contains('avatarCharacterId')
            ? null
            : avatar?.assetPath,
        nickname: pending.contains('nickname')
            ? null
            : json['nickname'] as String?,
        bio: pending.contains('bio') ? null : json['bio'] as String?,
        interests: pending.contains('interests')
            ? null
            : (json['interests'] as List?)?.cast<String>(),
        profileColor: pending.contains('profileColor')
            ? null
            : json['profileColor'] as String?,
        friendNotifications: pending.contains('friendNotifications')
            ? null
            : json['friendNotifications'] as bool?,
        orderNotifications: pending.contains('orderNotifications')
            ? null
            : json['orderNotifications'] as bool?,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Keeping the iPad and the service in step
// ---------------------------------------------------------------------------

/// What the app does with the service around its own life: on launch it
/// brings in what the iPad doesn't have and sends what the service hasn't
/// heard; on coming back to the foreground it sends again.
class ServiceSync {
  ServiceSync({
    required this.characters,
    required this.profile,
    required this.outbox,
  });

  final SyncedCharacterRepository characters;
  final SyncedProfileRepository profile;
  final Outbox outbox;

  /// Never fails: offline just means next time.
  Future<void> start() async {
    for (final step in [outbox.flush, characters.pull, profile.pull]) {
      try {
        await step();
      } on Object {
        // Next launch.
      }
    }
  }

  Future<void> resumed() => start();
}

String _imageDigest(Uint8List image) => sha256.convert(image).toString();

class _DeferredGeneration implements CharacterGenerationJob {
  _DeferredGeneration(this.create);
  final Future<CharacterGenerationJob> Function() create;
  Future<GeneratedArt>? _result;
  CharacterGenerationJob? _job;
  bool _cancelled = false;
  @override
  Future<GeneratedArt> get result => _result ??= () async {
    if (_cancelled) throw GenerationCancelled();
    _job = await create();
    if (_cancelled) {
      _job!.cancel();
      throw GenerationCancelled();
    }
    return _job!.result;
  }();
  @override
  void cancel() {
    _cancelled = true;
    _job?.cancel();
  }
}
