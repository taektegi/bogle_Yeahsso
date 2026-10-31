import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bogle_app/src/data/api/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// What the character service sends, as the app's tests pretend it. The
/// contract test checks these against the service's own API description
/// (test/contract/openapi.json), so they can't drift from the real thing.

const config = ApiConfig(
  apiUrl: 'https://api.test',
  supabaseUrl: 'https://auth.test',
  anonKey: 'anon',
  email: 'demo@test',
  password: 'pw',
);

const friendId = '5d0e8f4e-1c2b-4a3d-9e8f-0a1b2c3d4e5f';
const otherFriendId = 'aaaaaaaa-1c2b-4a3d-9e8f-0a1b2c3d4e5f';
const jobId = '9b1d2c3e-4f5a-4b6c-8d7e-9f0a1b2c3d4e';

Map<String, dynamic> image(String id, String url, {int side = 1024}) => {
  'assetId': id,
  'url': url,
  'expiresAt': DateTime.now()
      .toUtc()
      .add(const Duration(hours: 1))
      .toIso8601String(),
  'contentType': 'image/png',
  'width': side,
  'height': side,
};

const face = {
  'version': 1,
  'size': [812, 1024],
  'facing': 'front',
  'head': [180, 90, 460, 400],
  'eyes': [
    [330, 260, 22],
    [480, 262, 22],
  ],
  'mouth': [405, 360, 70, 22],
  'cheeks': <List<int>>[],
};

/// `CharacterOut`.
Map<String, dynamic> serverFriend({
  String id = friendId,
  String name = '구름이',
}) => {
  'id': id,
  'name': name,
  'personalityType': 'custom',
  'personalityLabel': '엉뚱해요',
  'personality': '엉뚱해요',
  'introduction': '구름 위에서 왔어',
  'favoriteThings': ['구름'],
  'speechStyle': '해요체',
  'source': null,
  'art': image('art-$id', 'https://cdn.test/$id/art.png'),
  'thumbnail': image('thumb-$id', 'https://cdn.test/$id/thumb.png', side: 256),
  'accentArgb': 4289974783,
  'face': face,
  'bedtime': 1320,
  'wakeTime': 360,
  'createdAt': '2026-10-08T05:00:00Z',
};

/// `GenerationOut`, finished.
Map<String, dynamic> generationSucceeded() => {
  'jobId': jobId,
  'status': 'succeeded',
  'sourceAssetId': 'src-1',
  'createdAt': '2026-10-08T05:00:00Z',
  'updatedAt': '2026-10-08T05:01:00Z',
  'art': image('art-9', 'https://cdn.test/new/art.png'),
  'thumbnail': image('thumb-9', 'https://cdn.test/new/thumb.png', side: 256),
  'accentArgb': 4294945450,
  'face': face,
  'faceStatus': 'ready',
};

/// `GenerationOut`, finished while its face map is still being worked out
/// (`pending`), or finished with none (`unavailable`).
Map<String, dynamic> generationSucceededFace(String faceStatus) => {
  ...generationSucceeded(),
  'face': null,
  'faceStatus': faceStatus,
  if (faceStatus == 'pending') 'pollAfterMs': 2000,
};

/// `GenerationOut`, still going.
Map<String, dynamic> generationWaiting(String status) => {
  'jobId': jobId,
  'status': status,
  'sourceAssetId': 'src-1',
  'createdAt': '2026-10-08T05:00:00Z',
  'updatedAt': '2026-10-08T05:00:00Z',
  'pollAfterMs': 2000,
};

/// `GenerationOut`, failed.
Map<String, dynamic> generationFailed(String code, {required bool retryable}) =>
    {
      'jobId': jobId,
      'status': 'failed',
      'sourceAssetId': 'src-1',
      'createdAt': '2026-10-08T05:00:00Z',
      'updatedAt': '2026-10-08T05:01:00Z',
      'error': {
        'code': code,
        'message': '이 그림으로는 친구를 만들지 못했어요.',
        'retryable': retryable,
      },
    };

/// `MotionOut`, ready.
Map<String, dynamic> motionReady() => {
  'status': 'ready',
  'reason': null,
  'clips': {
    'jump': {
      'url': 'https://cdn.test/clips/jump.gif',
      'box': [0.1, 0.05, 0.9, 0.95],
      'expiresAt': '2026-10-08T06:00:00Z',
    },
  },
};

/// `MessageOut`.
Map<String, dynamic> message(String role, String text) => {
  'id': '0e1f2a3b-4c5d-4e6f-8a9b-0c1d2e3f4a5b',
  'role': role,
  'text': text,
  'source': role == 'assistant' ? 'ai' : null,
  'createdAt': '2026-10-08T05:00:00Z',
};

/// `ProfileOut`.
Map<String, dynamic> me({String nickname = '별빛'}) => {
  'nickname': nickname,
  'avatarCharacterId': null,
  'friendNotifications': false,
  'orderNotifications': true,
  'characterCount': 1,
};

/// A fake service: routes by "METHOD /path" and records every request.
/// Pictures on `cdn.test` come back as a small PNG.
class FakeService {
  FakeService(this.routes);
  final Map<String, FutureOr<http.Response> Function(http.Request)> routes;
  final requests = <http.Request>[];
  var tokens = 0;
  var expireNextToken = false;

  /// While set, every request to the API fails as if offline.
  var offline = false;
  int cdnFailures = 0;

  late final client = MockClient((request) async {
    requests.add(request);
    if (request.url.host == 'auth.test') {
      tokens++;
      return json({
        'access_token': 'token-$tokens',
        'refresh_token': 'refresh-$tokens',
        'expires_in': 3600,
      });
    }
    if (request.url.host == 'cdn.test') {
      if (cdnFailures > 0) {
        cdnFailures--;
        throw http.ClientException('test download interrupted');
      }
      return http.Response.bytes(await pngBytes(), 200);
    }
    if (offline) throw http.ClientException('offline');
    if (expireNextToken) {
      expireNextToken = false;
      return json({
        'error': {'code': 'unauthenticated', 'message': '로그인이 필요해요.'},
      }, 401);
    }
    final route = routes['${request.method} ${request.url.path}'];
    if (route == null) return json({}, 404);
    return route(request);
  });

  ApiClient api({Future<void> Function(Duration)? wait}) => ApiClient(
    baseUrl: config.apiUrl,
    session: SupabasePasswordSession(config, client: client),
    client: client,
    wait: wait ?? (_) async {},
  );

  List<http.Request> to(String path) =>
      requests.where((r) => r.url.path == path).toList();
}

http.Response json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

Future<Uint8List> pngBytes() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawCircle(
    const ui.Offset(50, 50),
    30,
    ui.Paint()..color = const ui.Color(0xFF8BA2FF),
  );
  final picture = recorder.endRecording();
  final img = await picture.toImage(120, 100);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}
