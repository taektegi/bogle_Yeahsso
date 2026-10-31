import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bogle_app/src/data/api/api_services.dart';
import 'package:bogle_app/src/data/api/device_art.dart';
import 'package:bogle_app/src/data/app_services.dart';
import 'package:bogle_app/src/data/character_generation.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/local_store.dart';
import 'package:bogle_app/src/data/photo_preparation.dart';
import 'package:bogle_app/src/screens/create_studio_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'photo_capture_test.dart' show FakeCamera;
import 'photo_preparation_test.dart' show photograph;
import 'support/api_fixtures.dart';

class _Generator implements CharacterGenerator {
  GenerationInput? input;
  @override
  Future<void>? faceStillComing(String jobId) => null;
  @override
  CharacterGenerationJob start(GenerationInput input) {
    this.input = input;
    return _Job();
  }

  @override
  Future<void> finished(String id) async {}
  @override
  Future<CharacterGenerationJob?> unfinished() async => null;
}

class _Job implements CharacterGenerationJob {
  @override
  Future<GeneratedArt> get result => Completer<GeneratedArt>().future;
  @override
  void cancel() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final paper in [false, true]) {
    testWidgets('사진 정리 → 스튜디오 → 생성에서 paper=$paper 조건 보존', (tester) async {
      tester.view.physicalSize = const Size(1366, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final original = (await tester.runAsync(() => photograph()))!;
      final cutout = (await tester.runAsync(
        () => photograph(background: Colors.transparent),
      ))!;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(PhotoPreparation.channel, (
        call,
      ) async {
        expect(call.arguments['paper'], paper);
        return cutout;
      });
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(PhotoPreparation.channel, null),
      );
      final repo = InMemoryCharacterRepository();
      final generator = _Generator();
      await tester.pumpWidget(
        AppServicesScope(
          services: AppServices.local(characters: repo, generator: generator),
          child: MaterialApp(
            home: CreateStudioScreen(
              repository: repo,
              camera: FakeCamera.new,
              pickPhoto: () async => original,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take a photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('photo-library')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('photo-prepare')));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      if (paper) {
        await tester.tap(find.text('종이에 그린 그림'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('정리해 보기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('정리한 사진 사용'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('photo-use')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(generator.input!.source, GenerationSource.photo);
      expect(
        generator.input!.photoMode,
        paper ? PhotoMode.original : PhotoMode.subject,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

  test('같은 픽셀도 일반 사진과 선택 사진의 요청 키를 구분하고 재시작 시 조건 보존', () async {
    final dir = await Directory.systemTemp.createTemp('bogle-subject-');
    addTearDown(() => dir.delete(recursive: true));
    final requests = <Map>[];
    final keys = <String?>[];
    final service = FakeService({
      'POST /v1/assets': (_) =>
          json(image('source-1', 'https://cdn.test/source.png'), 201),
      'POST /v1/generations': (request) {
        requests.add(jsonDecode(request.body) as Map);
        keys.add(request.headers['Idempotency-Key']);
        return json({
          'error': {'code': 'service_unavailable', 'retryable': true},
        }, 503);
      },
    });
    final bytes = await pngBytes();
    final store = MemoryStore();
    final generator = ApiCharacterGenerator(
      service.api(),
      art: DeviceArt(dir),
      store: store,
    );
    for (final mode in PhotoMode.values) {
      await expectLater(
        generator
            .start(
              GenerationInput(
                bytes,
                source: GenerationSource.photo,
                photoMode: mode,
              ),
            )
            .result,
        throwsA(isA<GenerationError>()),
      );
    }
    expect(requests.first['photoMode'], isNull);
    expect(requests.last['photoMode'], 'subject');
    final originalKeys = <String?>{}, subjectKeys = <String?>{};
    for (var i = 0; i < requests.length; i++) {
      (requests[i]['photoMode'] == 'subject' ? subjectKeys : originalKeys).add(
        keys[i],
      );
    }
    expect(originalKeys, hasLength(1));
    expect(subjectKeys, hasLength(1));
    expect(originalKeys.single, isNot(subjectKeys.single));
    final countBeforeResume = requests.length;
    final deferred = await ApiCharacterGenerator(
      service.api(),
      art: DeviceArt(dir),
      store: store,
    ).unfinished();
    expect(
      requests,
      hasLength(countBeforeResume),
    ); // 이어서 만들기를 누르기 전에는 유료 요청 없음.
    await expectLater(deferred!.result, throwsA(isA<GenerationError>()));
    expect(requests.last['photoMode'], 'subject');
    expect(keys.last, subjectKeys.single);
  });

  test('그림 입력에 대상 선택 상태를 넣을 수 없다', () {
    expect(
      () => GenerationInput(
        Uint8List(0),
        source: GenerationSource.drawing,
        photoMode: PhotoMode.subject,
      ),
      throwsArgumentError,
    );
  });
}
