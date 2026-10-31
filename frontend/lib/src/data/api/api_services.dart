import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart' show listEquals;

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
/// starts a new job (a new `Idempotency-Key`), as the service asks.
class ApiCharacterGenerator implements CharacterGenerator {
  ApiCharacterGenerator(
    this.api, {
    required this.art,
    LocalStore? store,
    this.giveUpAfter = const Duration(minutes: 5),
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
    final pending = await _store?.read(_pendingName);
    final id = pending is Map ? pending['jobId'] : pending;
    final revision = pending is Map ? pending['sketchRevision'] : null;
    if (id is! String) return null;
    final Map<String, dynamic> state;
    try {
      state = await api.get('/v1/generations/$id');
    } on ApiException catch (e) {
      if (e.statusCode == 404) await _remember(null); // gone after a day
      return null;
    }
    if (state['status'] case 'failed' || 'cancelled') {
      await _remember(null);
      return null;
    }
    return _ApiGenerationJob(
      this,
      null,
      jobId: id,
      first: state,
      sketchRevision: revision is String ? revision : null,
    )..run();
  }

  @override
  Future<void> finished(String jobId) async {
    final pending = await _store?.read(_pendingName);
    if ((pending is Map ? pending['jobId'] : pending) == jobId) {
      await _remember(null);
    }
  }

  final Duration giveUpAfter;
  final Future<void> Function(Duration) _wait;
  final _uploads = Expando<Future<String>>();
  final _completed = Expando<String>();

  @override
  CharacterGenerationJob start(GenerationInput input) =>
      _ApiGenerationJob(this, input, jobId: _completed[input])..run();

  /// The uploaded picture's asset id, uploading it the first time.
  Future<String> source(GenerationInput input) {
    final known = _uploads[input];
    if (known != null) return known;
    final upload = _upload(input);
    _uploads[input] = upload;
    upload.catchError((Object _) {
      _uploads[input] = null; // try again next time
      return '';
    });
    return upload;
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

  ApiClient get _api => generator.api;

  @override
  Future<GeneratedArt> get result => _result.future;

  @override
  void cancel() {
    // Already finished (the loading page leaving after success): the
    // friend is still to be made from it, so nothing to cancel.
    if (_cancelled || _result.isCompleted) return;
    _cancelled = true;
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
      if (error is GenerationError || error is GenerationCancelled) {
        unawaited(generator._remember(null));
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
        started = await _api.post(
          '/v1/generations',
          body: {'sourceAssetId': source, 'sourceType': input.source.name},
          idempotencyKey: _api.newKey(),
        );
      } on ApiException catch (e) {
        throw _from(e);
      }
    }
    final id = _jobId = started['jobId'] as String? ?? _jobId!;
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
          final error = (state['error'] as Map?)?.cast<String, dynamic>();
          throw GenerationError(
            error?['code'] as String? ?? 'generation_unavailable',
            error?['message'] as String? ?? '잠시 후 다시 시도해 주세요.',
            retryable: error?['retryable'] as bool? ?? true,
          );
        case 'cancelled':
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
class ApiChatService implements ChatService {
  ApiChatService(this.api, {this.beforeReply});
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
          'text': message.length > 200 ? message.substring(0, 200) : message,
        },
        timeout: const Duration(seconds: 25),
      );
      return (json['assistantMessage'] as Map?)?['text'] as String?;
    } on ApiException catch (e) {
      if (e.code == 'character_asleep') return null;
      rethrow;
    }
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
    final saved = await local.saveProfile(profile);
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
    return saved;
  }

  /// On a fresh install the iPad has no profile yet: take the nickname and
  /// settings the service kept.
  Future<void> pull() async {
    if (await _store?.read('profile') != null) return;
    final json = await api.get('/v1/me');
    final current = await local.fetchProfile();
    await local.saveProfile(
      current.copyWith(
        nickname: json['nickname'] as String?,
        bio: json['bio'] as String?,
        interests: (json['interests'] as List?)?.cast<String>(),
        profileColor: json['profileColor'] as String?,
        friendNotifications: json['friendNotifications'] as bool?,
        orderNotifications: json['orderNotifications'] as bool?,
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
    for (final step in [outbox.flush, profile.pull, characters.pull]) {
      try {
        await step();
      } on Object {
        // Next launch.
      }
    }
  }

  Future<void> resumed() => outbox.flush();
}
