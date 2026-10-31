import 'dart:convert';
import 'dart:io';
import 'package:bogle_app/src/data/api/api_services.dart';
import 'package:bogle_app/src/data/api/device_art.dart';
import 'package:bogle_app/src/data/api/outbox.dart';
import 'package:bogle_app/src/data/character_generation.dart';
import 'package:bogle_app/src/data/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/api_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<Directory> folder() async {
    final dir = await Directory.systemTemp.createTemp('bogle-interop');
    addTearDown(() => dir.delete(recursive: true));
    return dir;
  }

  test('422의 잘못된 필드만 제외하고 이름·수면 시간은 재전송한다', () async {
    final bodies = <Map>[];
    final service = FakeService({
      'PATCH /v1/characters/$friendId': (request) {
        final body = jsonDecode(request.body) as Map;
        bodies.add(body);
        if (body.containsKey('introduction')) {
          return json({
            'error': {
              'code': 'validation_error',
              'fieldErrors': {'introduction': 'string_too_long'},
            },
          }, 422);
        }
        return json(serverFriend(name: body['name'] as String));
      },
    });
    final outbox = Outbox(service.api(), store: MemoryStore());
    addTearDown(outbox.dispose);
    await outbox.patchCharacter(friendId, {
      'name': '꼬마 별',
      'introduction': '잘못된 소개',
      'bedtime': 1200,
      'wakeTime': 400,
    });
    await outbox.flush();
    expect(bodies, hasLength(2));
    expect(bodies.last, {'name': '꼬마 별', 'bedtime': 1200, 'wakeTime': 400});
    expect(await outbox.pending, 0);
    expect(outbox.notice.value, isNotNull);
  });
  test('친구 저장을 완료한 뒤 같은 사진으로 새로 만들면 새 요청을 시작한다', () async {
    final service = FakeService({
      'POST /v1/assets': (_) =>
          json(image('source-1', 'https://cdn.test/source.png'), 201),
      'POST /v1/generations': (_) => json(generationSucceeded()),
    });
    final generator = ApiCharacterGenerator(
      service.api(),
      art: DeviceArt(await folder()),
    );
    final input = GenerationInput(
      await pngBytes(),
      source: GenerationSource.photo,
    );
    await generator.start(input).result;
    await generator.finished(jobId);
    await generator.start(input).result;
    expect(service.to('/v1/assets'), hasLength(2));
    expect(
      service
          .to('/v1/generations')
          .map((r) => r.headers['Idempotency-Key'])
          .toSet(),
      hasLength(2),
    );
  });

  test('만료 410은 이어서 만들기 기록을 지우고 503은 남긴다', () async {
    for (final status in [410, 503]) {
      final store = MemoryStore();
      await store.write('pending_generation', jobId);
      final service = FakeService({
        'GET /v1/generations/$jobId': (_) => json({
          'error': {
            'code': status == 410
                ? 'generation_expired'
                : 'service_unavailable',
            'retryable': status == 503,
          },
        }, status),
      });
      final generator = ApiCharacterGenerator(
        service.api(),
        art: DeviceArt(await folder()),
        store: store,
      );
      expect(await generator.unfinished(), isNull);
      expect(
        await store.read('pending_generation'),
        status == 410 ? isNull : jobId,
      );
    }
  });
  test('통신 실패 후 동일 이미지의 새 입력 객체도 업로드·멱등 키를 재사용한다', () async {
    final keys = <String?>[];
    final service = FakeService({
      'POST /v1/assets': (_) =>
          json(image('source-1', 'https://cdn.test/source.png'), 201),
      'POST /v1/generations': (request) {
        keys.add(request.headers['Idempotency-Key']);
        return json({
          'error': {'code': 'service_unavailable', 'retryable': true},
        }, 503);
      },
    });
    final store = MemoryStore();
    final generator = ApiCharacterGenerator(
      service.api(),
      art: DeviceArt(await folder()),
      store: store,
    );
    final bytes = await pngBytes();
    for (var i = 0; i < 2; i++) {
      await expectLater(
        generator
            .start(GenerationInput(bytes, source: GenerationSource.photo))
            .result,
        throwsA(isA<GenerationError>()),
      );
    }
    expect(keys.toSet(), hasLength(1));
    expect(service.to('/v1/assets'), hasLength(1));
    expect(
      (await store.read('pending_generation') as Map)['requestKey'],
      keys.first,
    );
    await generator.unfinished();
    expect(keys.toSet(), hasLength(1));
  });
}
