import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

enum GenerationSource { drawing, photo }

/// 사진의 대상을 사용자가 확정했는지 서버에 명시한다.
enum PhotoMode { original, subject }

/// Read-only input snapshot for the character generator. Capturing pixels
/// is a frontend responsibility; nothing may silently discard them.
class GenerationInput {
  GenerationInput(
    Uint8List image, {
    required this.source,
    this.photoMode = PhotoMode.original,
    this.sketchRevision,
  }) : image = Uint8List.fromList(image).asUnmodifiableView() {
    if (source != GenerationSource.photo && photoMode != PhotoMode.original) {
      throw ArgumentError('대상 선택은 사진 입력에서만 사용할 수 있어요.');
    }
  }
  final Uint8List image;
  final GenerationSource source;
  final PhotoMode photoMode;

  /// 기기 안에서만 쓰는 초안 식별자. AI 요청에는 보내지 않는다.
  final String? sketchRevision;
}

/// What a generation hands to setup: the new friend's artwork and colour.
class GeneratedArt {
  const GeneratedArt({
    required this.assetPath,
    this.accentHex = defaultAccent,
    this.jobId,
    this.thumbnailPath,
    this.sketchRevision,
  });

  /// An asset path, a file on the device or an http(s) URL (see
  /// `art_source.dart`).
  final String assetPath;
  final int accentHex;

  /// The character service's job, which the new friend is made from
  /// (`POST /v1/characters` takes it). Null for local generation.
  final String? jobId;

  /// A small copy of the artwork, when the generator made one.
  final String? thumbnailPath;
  final String? sketchRevision;

  /// The friend's colour until a generator picks one from the artwork.
  static const defaultAccent = 0xFFBDCFFF;
}

/// One run of the generator. Only its [result], never an animation timer,
/// advances the UI.
abstract interface class CharacterGenerationJob {
  /// Completes with the artwork, or with an error ([GenerationCancelled]
  /// after [cancel]).
  Future<GeneratedArt> get result;
  void cancel();
}

class GenerationCancelled implements Exception {}

/// The generator could not make a friend. [message] can be shown as it is;
/// when [retryable] is false the same picture will not work, so the child
/// is asked for another one rather than offered a retry.
class GenerationError implements Exception {
  const GenerationError(this.code, this.message, {required this.retryable});
  final String code;
  final String message;
  final bool retryable;

  @override
  String toString() => 'GenerationError($code)';
}

/// Turns a child's drawing or photo into a friend's artwork. The character
/// service (upload, then `POST /v1/generations` and polling) implements
/// this; until it is connected, [LocalCharacterGenerator] does.
abstract interface class CharacterGenerator {
  CharacterGenerationJob start(GenerationInput input);

  /// A generation the app was closed during (or that finished without
  /// becoming a friend), to pick up again; null when there is none.
  Future<CharacterGenerationJob?> unfinished();

  /// The friend made from job [jobId] exists: nothing to pick up any more.
  Future<void> finished(String jobId);

  /// 작업 [jobId]의 얼굴 좌표가 아직 오는 중이면, 다 받거나 없다고 확정되거나
  /// 기다리기를 그만둘 때 끝나는 future. 기다릴 것이 없으면 null이다.
  /// 친구 설정을 마친 뒤 표정까지 갖춘 친구로 만나게 하려고 쓴다.
  Future<void>? faceStillComing(String jobId);
}

/// Without a character service the child's own picture becomes the friend:
/// a drawing cut to its strokes, a photo as it is. Kept in the app's
/// temporary folder for this session, like the rest of the local data.
class LocalCharacterGenerator implements CharacterGenerator {
  const LocalCharacterGenerator({this.folder});

  /// Where the pictures are kept; the app's temporary folder (this session
  /// only) when null.
  final Directory? folder;

  @override
  CharacterGenerationJob start(GenerationInput input) =>
      _LocalJob(_save(input));

  /// Local generation finishes at once: there is never one to pick up.
  @override
  Future<CharacterGenerationJob?> unfinished() => Future.value();

  @override
  Future<void> finished(String jobId) => Future.value();

  /// 기기 안에서 만든 친구는 얼굴 좌표를 따로 받지 않는다.
  @override
  Future<void>? faceStillComing(String jobId) => null;

  Future<GeneratedArt> _save(GenerationInput input) async {
    final png = input.image.length > 8 && input.image[0] == 0x89;
    final bytes = png && input.source == GenerationSource.drawing
        ? await trimToInk(input.image)
        : input.image;
    final home = folder;
    final Directory into;
    if (home != null) {
      into = await home.create(recursive: true);
    } else {
      into = await Directory.systemTemp.createTemp('bogle_friend_');
    }
    final file = File(
      '${into.path}/friend-${DateTime.now().microsecondsSinceEpoch}'
      '.${png ? 'png' : 'jpg'}',
    );
    await file.writeAsBytes(bytes, flush: true);
    return GeneratedArt(
      assetPath: file.path,
      sketchRevision: input.source == GenerationSource.drawing
          ? input.sketchRevision
          : null,
    );
  }
}

class _LocalJob implements CharacterGenerationJob {
  _LocalJob(Future<GeneratedArt> work) {
    work.then(
      (art) {
        if (!_result.isCompleted) _result.complete(art);
      },
      onError: (Object error, StackTrace stack) {
        if (!_result.isCompleted) _result.completeError(error, stack);
      },
    );
  }
  final _result = Completer<GeneratedArt>();

  @override
  Future<GeneratedArt> get result => _result.future;

  @override
  void cancel() {
    if (!_result.isCompleted) _result.completeError(GenerationCancelled());
  }
}

/// A drawing exported from the whole sketchbook page, cropped to its strokes
/// with a little air around them, so the friend fills its own picture.
Future<Uint8List> trimToInk(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final image = (await codec.getNextFrame()).image;
  codec.dispose();
  try {
    final rgba = await image.toByteData();
    if (rgba == null) return png;
    final w = image.width, h = image.height;
    // A whole page is millions of pixels: look for the ink off the UI thread.
    final ink = await compute(_inkBounds, (rgba.buffer.asUint8List(), w));
    if (ink == null) return png;
    final (left, top, right, bottom) = ink;
    final margin = (math.max(right - left, bottom - top) * .06).ceil() + 4;
    final crop = ui.Rect.fromLTRB(
      math.max(0, left - margin).toDouble(),
      math.max(0, top - margin).toDouble(),
      math.min(w, right + 1 + margin).toDouble(),
      math.min(h, bottom + 1 + margin).toDouble(),
    );
    if (crop.width >= w && crop.height >= h) return png;
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      image,
      crop,
      ui.Rect.fromLTWH(0, 0, crop.width, crop.height),
      ui.Paint()..filterQuality = ui.FilterQuality.none,
    );
    final picture = recorder.endRecording();
    final cropped = await picture.toImage(
      crop.width.round(),
      crop.height.round(),
    );
    picture.dispose();
    try {
      final out = await cropped.toByteData(format: ui.ImageByteFormat.png);
      return out == null
          ? png
          : out.buffer.asUint8List(out.offsetInBytes, out.lengthInBytes);
    } finally {
      cropped.dispose();
    }
  } finally {
    image.dispose();
  }
}

/// The first and last columns and rows with any ink, or null if none.
(int, int, int, int)? _inkBounds((Uint8List, int) page) {
  final (rgba, w) = page;
  final h = rgba.length ~/ (w * 4);
  var left = w, top = h, right = -1, bottom = -1;
  for (var y = 0; y < h; y++) {
    final row = y * w * 4;
    for (var x = 0; x < w; x++) {
      if (rgba[row + x * 4 + 3] == 0) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      bottom = y;
    }
  }
  return right < 0 ? null : (left, top, right, bottom);
}
