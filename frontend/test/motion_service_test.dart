import 'dart:convert';
import 'dart:io';

import 'package:bogle_app/src/data/motion_service.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

CharacterFriend friend(String id) => CharacterFriend(
  id: id,
  name: id,
  personality: '',
  favoriteThings: const [],
  speechStyle: '반말',
  assetPath: 'assets/figma/$id.png',
  accentHex: 0xFFB8C9FF,
);

/// Answers like motion_server/app.py: "garlic" animates after one poll,
/// anything else is not two-legged.
Future<(HttpServer, List<String>)> fakeServer([int port = 0]) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  final seen = <String>[];
  final polls = <String, int>{};
  server.listen((request) async {
    seen.add('${request.method} ${request.uri.path}');
    final body = await utf8.decoder.bind(request).join();
    final res = request.response..headers.contentType = ContentType.json;
    if (request.method == 'POST') {
      expect(request.headers.contentType!.mimeType, 'multipart/form-data');
      final id = body.contains('GARLIC') ? 'garlic' : 'blob';
      // Like the real service, the upload never lists clips, even when the
      // drawing was rendered before.
      res.write(jsonEncode({'id': id, 'status': 'ready'}));
    } else {
      final id = request.uri.pathSegments.last;
      final n = polls[id] = (polls[id] ?? 0) + 1;
      final base = 'http://${server.address.host}:${server.port}';
      res.write(
        jsonEncode(switch ((id, n)) {
          (_, 1) => {'id': id, 'status': 'working', 'clips': {}},
          ('garlic', _) => {
            'id': id,
            'status': 'ready',
            'clips': {
              for (final c in ['jump', 'wave', 'dance'])
                c: {
                  'url': '$base/motions/$id/$c.gif',
                  'box': [.2, .1, .8, .75],
                },
            },
          },
          _ => {'id': id, 'status': 'unsupported', 'reason': 'not_humanoid'},
        }),
      );
    }
    await res.close();
  });
  return (server, seen);
}

void main() {
  test('uploads the drawing, polls, and reads the clips', () async {
    final (server, seen) = await fakeServer();
    addTearDown(server.close);
    final service = HttpMotionService(
      'http://${server.address.host}:${server.port}',
      poll: const Duration(milliseconds: 10),
      loadDrawing: (asset) async =>
          utf8.encode(asset.contains('garlic') ? 'GARLIC' : 'BLOB'),
    );

    final clips = (await service.clipsFor(friend('garlic')))!;
    expect(clips.keys, MotionClipKind.values);
    expect(clips[MotionClipKind.jump]!.url, endsWith('/garlic/jump.gif'));
    expect(
      clips[MotionClipKind.jump]!.box,
      const Rect.fromLTRB(.2, .1, .8, .75),
    );
    expect(seen, [
      'POST /motions',
      'GET /motions/garlic',
      'GET /motions/garlic',
    ]);

    // Asked again: answered from memory, no new requests.
    await service.clipsFor(friend('garlic'));
    expect(seen, hasLength(3));

    // A drawing the models can't animate: null, so the house keeps its own
    // motions.
    expect(await service.clipsFor(friend('blob')), isNull);
  });

  test(
    'an unreachable service means no clips, and it tries again later',
    () async {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();
      final service = HttpMotionService(
        'http://127.0.0.1:$port',
        poll: const Duration(milliseconds: 10),
        loadDrawing: (_) async => utf8.encode('GARLIC'),
      );
      expect(await service.clipsFor(friend('garlic')), isNull);

      // Now it's up on that port: the same client asks again, because a
      // failure is not remembered.
      final (server, _) = await fakeServer(port);
      addTearDown(server.close);
      expect(await service.clipsFor(friend('garlic')), isNotNull);
    },
  );

  test('without MOTION_SERVER the app makes no requests', () async {
    expect(defaultMotionService(), isA<NoMotionService>());
    expect(await const NoMotionService().clipsFor(friend('garlic')), isNull);
  });
}
