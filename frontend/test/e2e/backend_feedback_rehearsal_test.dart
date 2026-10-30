// 개인 백엔드 scripts/rehearse_flutter.py가 띄운 임시 HTTP 서버 전용 2차 검증.
import 'dart:io';

import 'package:bogle_app/src/data/api/api_client.dart';
import 'package:bogle_app/src/data/app_services.dart';
import 'package:bogle_app/src/data/character_generation.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/friend_profile_choices.dart';
import 'package:bogle_app/src/data/local_store.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:flutter_test/flutter_test.dart';

final _url = Platform.environment['BOGLE_FEEDBACK_API_URL'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '실제 Dart → FastAPI → PostgreSQL: 입력·PNG·설정·수면·대화·실패 복구',
    () async {
      HttpOverrides.global = null;
      final config = ApiConfig(
        apiUrl: _url!,
        supabaseUrl: _url!,
        anonKey: 'local-test-only',
        email: 'rehearsal@bogle.test',
        password: 'local-test-only',
      );
      final api = ApiClient(
        baseUrl: _url!,
        session: SupabasePasswordSession(config),
      );
      final folder = await Directory.systemTemp.createTemp(
        'bogle_http_rehearsal_',
      );
      addTearDown(() => folder.delete(recursive: true));
      final services = AppServices.remote(config, store: FileStore(folder));
      addTearDown(services.sync!.outbox.dispose);
      final choices = await api.get('/v1/personality-types');
      expect(
        (choices['items'] as List).map((v) => v['label']),
        personalityChoices,
      );
      final saved = <CharacterFriend>[];
      for (final source in GenerationSource.values) {
        final bytes = await api.download('$_url/test/input/${source.name}');
        final art = await services.generator
            .start(GenerationInput(bytes, source: source))
            .result;
        expect(File(art.assetPath).readAsBytesSync().take(8), [
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
        ]);
        final friend = await services.characters.createFriend(
          NewFriend(
            name: source == GenerationSource.drawing ? '그림친구' : '사진친구',
            personality: personalityChoices.first,
            favoriteThings: const ['그림'],
            speechStyle: '해요체',
            assetPath: art.assetPath,
            accentHex: art.accentHex,
            generationJobId: art.jobId,
          ),
        );
        saved.add(friend);
        final server = await api.get('/v1/characters/${friend.id}');
        expect(server['personality'], personalityChoices.first);
        expect(server['art']['contentType'], 'image/png');
        expect(server['bedtime'], const SleepSchedule().bedtime);
        await services.generator.finished(art.jobId!);
      }
      final seen = await api.get('/test/observations');
      expect(seen['sourceTypes'], containsAll(['drawing', 'photo']));
      final friend = saved.first;
      // 편집한 성격·수면을 전송하고 서버 상태와 앱의 수면 판정을 대조한다.
      final edited = friend.copyWith(
        personality: personalityChoices.last,
        sleep: const SleepSchedule(bedtime: 0, wakeTime: 0),
      );
      await services.characters.saveFriend(edited);
      final answer = await services.chat.replyTo(edited, '아파');
      expect(answer, contains('선생님'));
      expect(
        (await api.get('/v1/characters/${friend.id}'))['personality'],
        personalityChoices.last,
      );
      expect(
        (await api.get('/v1/characters/${friend.id}/status'))['asleep'],
        false,
      );
      expect(await services.chat.history(edited), isNotEmpty);
      // 서버가 자는 것으로 판단하는 일정으로 바꾸면 새 대화는 차단된다.
      final now = DateTime.now();
      final minute = now.hour * 60 + now.minute;
      final asleep = edited.copyWith(
        sleep: SleepSchedule(
          bedtime: (minute + 1439) % 1440,
          wakeTime: (minute + 60) % 1440,
        ),
      );
      await services.characters.saveFriend(asleep);
      await services.sync!.resumed();
      expect(
        (await api.get('/v1/characters/${friend.id}/status'))['asleep'],
        true,
      );
      expect(await services.chat.replyTo(asleep, '안녕'), isNull);
      // AI 출력 실패는 생성 실패로 전달되고 원본은 재사용할 수 있다.
      for (final mode in ['timeout', 'invalid_png', 'rejected']) {
        await api.post('/test/failure/$mode');
        final input = GenerationInput(
          await api.download('$_url/test/input/photo'),
          source: GenerationSource.photo,
        );
        await expectLater(
          services.generator.start(input).result,
          throwsA(
            isA<GenerationError>().having(
              (e) => e.retryable,
              'retryable',
              mode != 'rejected',
            ),
          ),
        );
        if (mode == 'timeout') {
          await api.post('/test/failure/none');
          final recovered = await services.generator.start(input).result;
          expect(File(recovered.assetPath).existsSync(), true);
        }
      }
      // 앱을 새로 열어도 파일과 저장한 친구는 남는다.
      final relaunched = AppServices.remote(config, store: FileStore(folder));
      addTearDown(relaunched.sync!.outbox.dispose);
      expect(
        (await relaunched.characters.fetchFriends()).map((v) => v.id),
        containsAll(saved.map((v) => v.id)),
      );
      expect(await services.sync!.outbox.pending, 0);
    },
    skip: _url == null ? '개인 백엔드 rehearse_flutter.py로 실행' : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
