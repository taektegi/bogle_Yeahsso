import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bogle_app/src/data/api/api_client.dart';
import 'package:bogle_app/src/data/api/api_window_views.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:bogle_app/src/data/local_store.dart';
import 'package:bogle_app/src/data/window_view.dart';
import 'package:bogle_app/src/screens/house/house_widgets.dart';
import 'package:bogle_app/src/widgets/character_preview_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class Session implements AuthSession {
  @override
  Future<String> accessToken() async => 'mock';
  @override
  Future<String> refresh() => accessToken();
}

Future<Uint8List> scenery() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xFFC9DDF0), BlendMode.src);
  canvas.drawRect(
    const Rect.fromLTWH(0, 300, 2048, 276),
    Paint()..color = const Color(0xFFA9C0AB),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(2048, 576);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const id = '01234567-0123-4567-89ab-012345678901';
  const friend = CharacterFriend(
    id: id,
    name: '민들레',
    personality: '밝아요',
    favoriteThings: [],
    speechStyle: '반말',
    assetPath: 'unused.png',
    accentHex: 0xFFCFDAEC,
  );
  Map<String, dynamic> ref(String id) => {
    'assetId': id,
    'url': 'https://images.test/$id',
    'contentType': 'image/png',
    'width': 2048,
    'height': 576,
  };

  test(
    'completed pair persists by filename and works offline after moving the container',
    () async {
      final folder = await Directory.systemTemp.createTemp('window-cache-');
      addTearDown(() => folder.delete(recursive: true));
      final data = await scenery();
      var polls = 0, posts = 0, downloads = 0;
      final api = ApiClient(
        baseUrl: 'https://api.test',
        session: Session(),
        client: MockClient((request) async {
          if (request.url.host == 'images.test') {
            downloads++;
            return http.Response.bytes(data, 200);
          }
          if (request.method == 'POST') {
            posts++;
            expect(request.headers['Idempotency-Key'], isNotEmpty);
            return http.Response(jsonEncode({'status': 'queued'}), 202);
          }
          polls++;
          return http.Response(
            jsonEncode(
              polls == 1
                  ? {'status': 'missing'}
                  : {
                      'status': 'succeeded',
                      'day': ref('day-1'),
                      'night': ref('night-1'),
                    },
            ),
            200,
          );
        }),
      );
      final service = ApiWindowViews(
        api,
        store: FileStore(folder),
        wait: (_) async {},
      );
      final view = await service.load(friend);
      expect(posts, 1);
      expect(downloads, 2);
      expect(WindowView.image(view!.day), isA<FileImage>());
      final moved = Directory('${folder.path}/new-container');
      await moved.create();
      await Directory('${folder.path}/art').rename('${moved.path}/art');
      await File(
        '${folder.path}/window-$id.json',
      ).rename('${moved.path}/window-$id.json');
      final offline = ApiWindowViews(
        ApiClient(
          baseUrl: 'https://api.test',
          session: Session(),
          client: MockClient(
            (_) async => throw StateError('must use offline cache'),
          ),
        ),
        store: FileStore(moved),
      );
      final cached = await offline.load(friend);
      expect(cached!.day, startsWith(moved.path));
      await offline.forget(id);
      expect(await File(cached.day).exists(), false);
    },
  );

  test('failed generation is not automatically re-enqueued', () async {
    final folder = await Directory.systemTemp.createTemp('window-fail-');
    addTearDown(() => folder.delete(recursive: true));
    var posts = 0;
    final service = ApiWindowViews(
      ApiClient(
        baseUrl: 'https://api.test',
        session: Session(),
        client: MockClient((request) async {
          if (request.method == 'POST') posts++;
          return http.Response(
            jsonEncode({
              'status': 'failed',
              'error': {'message': 'Please retry'},
            }),
            200,
          );
        }),
      ),
      store: FileStore(folder),
    );
    await expectLater(service.load(friend), throwsA(isA<ApiException>()));
    expect(posts, 0);
  });

  test('invalid night output cannot publish half a pair', () async {
    final folder = await Directory.systemTemp.createTemp('window-invalid-');
    addTearDown(() => folder.delete(recursive: true));
    final data = await scenery();
    final service = ApiWindowViews(
      ApiClient(
        baseUrl: 'https://api.test',
        session: Session(),
        client: MockClient((request) async {
          if (request.url.host == 'images.test') {
            return http.Response.bytes(
              request.url.path.contains('night') ? [1, 2, 3] : data,
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'status': 'succeeded',
              'day': ref('day-1'),
              'night': ref('night-1'),
            }),
            200,
          );
        }),
      ),
      store: FileStore(folder),
    );
    await expectLater(service.load(friend), throwsA(isA<FormatException>()));
    expect(await FileStore(folder).read('window-$id'), isNull);
    expect(await File('${folder.path}/art/window-day-1.png').exists(), false);
  });

  test(
    'pale artwork gets a measured backdrop while dark text stays readable',
    () {
      final ArtLook look = (
        natural: const Size(100, 100),
        drawn: const Rect.fromLTWH(0, 0, 1, 1),
        clearGround: true,
        body: const Offset(.5, .5),
        fill: .8,
        colors: [(Colors.white, .6), (Colors.black, .4)],
      );
      final color = CharacterPreviewSurface.backdrop(
        const Color(0xFFF1F0DA),
        look,
      );
      expect((1.05) / (color.computeLuminance() + .05), greaterThan(1.7));
      expect((color.computeLuminance() + .05) / (.01 + .05), greaterThan(4.5));
    },
  );
}
