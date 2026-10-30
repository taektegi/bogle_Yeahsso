import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bogle_app/src/data/api/api_client.dart';
import 'package:bogle_app/src/data/api/api_services.dart';
import 'package:bogle_app/src/data/api/device_art.dart';
import 'package:bogle_app/src/data/character_generation.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/friend_talk.dart';
import 'package:bogle_app/src/data/local_store.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'api_test.dart' show Wired;
import 'support/api_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Directory> folder() async {
    final dir = await Directory.systemTemp.createTemp('bogle_feedback_');
    addTearDown(() => dir.delete(recursive: true));
    return dir;
  }

  test('기기 시간대는 매 요청에 반영된다', () async {
    var offset = const Duration(hours: -4);
    final service = FakeService({'GET /v1/me': (_) => json(me())});
    final api = ApiClient(
      baseUrl: config.apiUrl,
      session: SupabasePasswordSession(config, client: service.client),
      client: service.client,
      utcOffset: () => offset,
    );
    await api.get('/v1/me');
    offset = const Duration(hours: 9);
    await api.get('/v1/me');
    expect(
      service.to('/v1/me').map((r) => r.headers['X-Bogle-Utc-Offset-Minutes']),
      ['-240', '540'],
    );
  });

  for (final source in GenerationSource.values) {
    test('${source.name} 구분과 PNG 결과가 유지된다', () async {
      final service = FakeService({
        'POST /v1/assets': (_) =>
            json(image('src-1', 'https://cdn.test/input'), 201),
        'POST /v1/generations': (_) => json(generationSucceeded(), 202),
      });
      final generator = ApiCharacterGenerator(
        service.api(),
        art: DeviceArt(await folder()),
      );
      final made = await generator
          .start(GenerationInput(await pngBytes(), source: source))
          .result;
      expect(
        jsonDecode(service.to('/v1/generations').single.body)['sourceType'],
        source.name,
      );
      expect(File(made.assetPath).readAsBytesSync().take(8), [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ]);
    });
  }

  test('다운로드만 끊기면 AI 생성을 다시 요청하지 않는다', () async {
    final service = FakeService({
      'POST /v1/assets': (_) =>
          json(image('src-1', 'https://cdn.test/input'), 201),
      'POST /v1/generations': (_) => json(generationSucceeded(), 202),
      'GET /v1/generations/$jobId': (_) => json(generationSucceeded()),
    })..cdnFailures = 2;
    final generator = ApiCharacterGenerator(
      service.api(),
      art: DeviceArt(await folder()),
    );
    final input = GenerationInput(
      await pngBytes(),
      source: GenerationSource.drawing,
    );
    await expectLater(
      generator.start(input).result,
      throwsA(isA<GenerationError>()),
    );
    service.cdnFailures = 0;
    final made = await generator.start(input).result;
    expect(File(made.assetPath).existsSync(), isTrue);
    expect(service.to('/v1/generations'), hasLength(1));
    expect(service.to('/v1/assets'), hasLength(1));
  });

  test('PNG가 아닌 결과는 파일로 저장하지 않는다', () async {
    final dir = await folder();
    await expectLater(
      DeviceArt(dir).keep('bad', art: Uint8List.fromList([255, 216, 255])),
      throwsFormatException,
    );
    expect(await dir.list().toList(), isEmpty);
  });

  test('서버 저장 후 응답이 끊겨도 재실행 후 같은 저장 키로 복구한다', () async {
    var loseResponse = true;
    final service = FakeService({
      'POST /v1/characters': (_) {
        if (loseResponse) {
          throw http.ClientException('response lost after commit');
        }
        return json(serverFriend(), 200);
      },
    });
    const input = NewFriend(
      name: '구름이',
      personality: '엉뚱해요',
      favoriteThings: ['구름'],
      speechStyle: '해요체',
      assetPath: '/kept/job.png',
      accentHex: 0xFFBDCFFF,
      generationJobId: jobId,
    );
    final store = MemoryStore();
    final first = Wired(service, store, await folder());
    await expectLater(
      first.characters.createFriend(input),
      throwsA(isA<ApiException>()),
    );
    first.outbox.dispose();
    loseResponse = false;
    final relaunched = Wired(service, store, await folder());
    addTearDown(relaunched.outbox.dispose);
    expect((await relaunched.characters.createFriend(input)).id, friendId);
    expect(
      service
          .to('/v1/characters')
          .map((r) => r.headers['Idempotency-Key'])
          .toSet(),
      hasLength(1),
    );
    final body = jsonDecode(service.to('/v1/characters').last.body);
    expect(body['bedtime'], const SleepSchedule().bedtime);
    expect(body['wakeTime'], const SleepSchedule().wakeTime);
  });

  test('서버 없는 친구도 위험 신호에는 걱정 대사로 답한다', () {
    const friend = CharacterFriend(
      id: 'local',
      name: '구름이',
      personality: '다정해요',
      favoriteThings: ['구름'],
      speechStyle: '해요체',
      assetPath: 'test.png',
      accentHex: 0xFFBDCFFF,
    );
    final talk = FriendTalk(friend);
    for (final text in ['아파', '죽고 싶어', '친구가 괴롭혀']) {
      expect(talk.careReply(text), contains('선생님'));
    }
    for (final text in ['아파트에 살아', '정답 맞았어', '같이 놀자']) {
      expect(talk.careReply(text), isNull);
    }
  });
}
