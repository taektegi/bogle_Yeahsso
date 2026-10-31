import 'dart:async';
import 'art_source.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/character_friend.dart';

/// One animated clip of a friend: a transparent GIF and where the friend
/// moves within it ([box]: left, top, right, bottom as fractions).
class MotionClip {
  const MotionClip(this.url, this.box);
  final String url;
  final Rect box;
}

enum MotionClipKind { jump, wave, dance }

/// Clips for a friend made by the motion service (motion_server/), or null
/// when its drawing can't be animated (not two-legged, lined paper, ...) or
/// the service isn't reachable. The house then uses its own motions.
abstract interface class MotionService {
  Future<Map<MotionClipKind, MotionClip>?> clipsFor(CharacterFriend friend);
}

/// For builds without a motion server: every friend uses the built-in motions.
class NoMotionService implements MotionService {
  const NoMotionService();
  @override
  Future<Map<MotionClipKind, MotionClip>?> clipsFor(CharacterFriend friend) =>
      Future.value();
}

/// Shared by every screen, so each friend's clips are fetched once.
final MotionService motionService = defaultMotionService();

/// The motion service is optional: pass its address at build time with
/// `--dart-define=MOTION_SERVER=http://<mac-ip>:8000` (motion_server/run.sh
/// prints it). Without it the app never makes a network request.
MotionService defaultMotionService() {
  const base = String.fromEnvironment('MOTION_SERVER');
  return base.isEmpty ? const NoMotionService() : HttpMotionService(base);
}

class HttpMotionService implements MotionService {
  HttpMotionService(
    this.base, {
    this.poll = const Duration(seconds: 2),
    this.giveUpAfter = const Duration(minutes: 3),
    this.loadDrawing = drawingAsPng,
  });

  final String base;
  final Duration poll;
  final Duration giveUpAfter;

  /// The drawing to send for an asset path; replaceable in tests.
  final Future<List<int>> Function(String assetPath) loadDrawing;

  /// One request per friend for the life of the app.
  final _cache = <String, Future<Map<MotionClipKind, MotionClip>?>>{};

  @override
  Future<Map<MotionClipKind, MotionClip>?> clipsFor(CharacterFriend friend) =>
      _cache[friend.id] ??= _fetch(friend).catchError((Object _) {
        // Offline or the server failed: try again next time.
        _cache.remove(friend.id);
        return null;
      });

  Future<Map<MotionClipKind, MotionClip>?> _fetch(
    CharacterFriend friend,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final png = await loadDrawing(friend.assetPath);
      final created = await _upload(client, png);
      final id = created['id'] as String;
      final deadline = DateTime.now().add(giveUpAfter);
      // The upload only says where the job is; its clips come from status
      // (a drawing rendered before is "ready" straight away).
      var state = await _get(client, '$base/motions/$id');
      while (state['status'] == 'queued' || state['status'] == 'working') {
        if (DateTime.now().isAfter(deadline)) return null;
        await Future<void>.delayed(poll);
        state = await _get(client, '$base/motions/$id');
      }
      if (state['status'] != 'ready') return null;
      final clips = (state['clips'] as Map).cast<String, dynamic>();
      return {
        for (final kind in MotionClipKind.values)
          if (clips[kind.name] case {
            'url': final String url,
            'box': final List box,
          })
            kind: MotionClip(
              url,
              Rect.fromLTRB(
                (box[0] as num).toDouble(),
                (box[1] as num).toDouble(),
                (box[2] as num).toDouble(),
                (box[3] as num).toDouble(),
              ),
            ),
      };
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> _upload(HttpClient client, List<int> png) async {
    const boundary = 'bogle-motion-boundary';
    final request = await client.postUrl(Uri.parse('$base/motions'));
    request.headers.contentType = ContentType(
      'multipart',
      'form-data',
      parameters: {'boundary': boundary},
    );
    request
      ..add(
        utf8.encode(
          '--$boundary\r\n'
          'Content-Disposition: form-data; name="image"; filename="drawing.png"\r\n'
          'Content-Type: image/png\r\n\r\n',
        ),
      )
      ..add(png)
      ..add(utf8.encode('\r\n--$boundary--\r\n'));
    return _json(await request.close());
  }

  Future<Map<String, dynamic>> _get(HttpClient client, String url) async =>
      _json(await (await client.getUrl(Uri.parse(url))).close());

  Future<Map<String, dynamic>> _json(HttpClientResponse response) async {
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw HttpException('motion service ${response.statusCode}: $body');
    }
    return (jsonDecode(body) as Map).cast<String, dynamic>();
  }
}

/// The friend's drawing as a PNG on white paper, which is what the drawing
/// models were trained on. Photographs go as they are; cut-out art
/// (vector, or a PNG on a clear ground) is laid on white first.
Future<List<int>> drawingAsPng(String assetPath) async {
  if (isPhotographedArt(assetPath)) return loadArtBytes(assetPath);
  const target = 900.0;
  final Size size;
  final void Function(Canvas canvas, double scale) draw;
  final disposers = <void Function()>[];
  if (isSvgArt(assetPath)) {
    final info = await vg.loadPicture(artSvgLoader(assetPath), null);
    size = info.size;
    draw = (canvas, scale) => canvas
      ..scale(scale)
      ..drawPicture(info.picture);
    disposers.add(info.picture.dispose);
  } else {
    final codec = await ui.instantiateImageCodec(await loadArtBytes(assetPath));
    final art = (await codec.getNextFrame()).image;
    codec.dispose();
    size = Size(art.width.toDouble(), art.height.toDouble());
    draw = (canvas, scale) => canvas
      ..scale(scale)
      ..drawImage(
        art,
        Offset.zero,
        Paint()..filterQuality = FilterQuality.high,
      );
    disposers.add(art.dispose);
  }
  final scale = target / math.max(size.width, size.height);
  final w = (size.width * scale).ceil() + 80;
  final h = (size.height * scale).ceil() + 80;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF),
    )
    ..translate(40, 40);
  draw(canvas, scale);
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  picture.dispose();
  for (final dispose in disposers) {
    dispose();
  }
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}
