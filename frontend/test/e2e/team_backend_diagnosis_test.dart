// 팀 main과 release의 실제 HTTP 연동을 관찰한다. 앱의 요청은 수정하지 않는다.
import 'dart:convert';
import 'dart:io';

import 'package:bogle_app/src/data/api/api_client.dart';
import 'package:bogle_app/src/data/api/synced_character_repository.dart';
import 'package:bogle_app/src/data/app_services.dart';
import 'package:bogle_app/src/data/character_generation.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

final _url = Platform.environment['BOGLE_DIAGNOSTIC_URL'];

class ObservedClient extends http.BaseClient {
  final inner = http.Client();
  final requests = <Map<String, Object?>>[];
  String? dropNextPath;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await inner.send(request);
    // 본문·헤더·토큰·서명 URL은 기록하지 않는다.
    requests.add({
      'method': request.method,
      'path': request.url.path,
      'status': response.statusCode,
    });
    if (request.method == 'POST' &&
        request.url.path == dropNextPath &&
        response.statusCode >= 200 &&
        response.statusCode < 300) {
      dropNextPath = null;
      await response.stream.drain<void>();
      throw http.ClientException('diagnostic response loss');
    }
    return response;
  }

  @override
  void close() => inner.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '관찰: release Dart 클라이언트 → 팀 FastAPI → 실제 PostgreSQL',
    () async {
      HttpOverrides.global = null;
      final root = await Directory.systemTemp.createTemp(
        'bogle-team-diagnostic-',
      );
      final client = ObservedClient();
      final config = ApiConfig(
        apiUrl: _url!,
        supabaseUrl: _url!,
        anonKey: 'local-only',
        email: 'diagnostic@bogle.test',
        password: 'local-only',
      );
      final api = ApiClient(
        baseUrl: _url!,
        client: client,
        session: SupabasePasswordSession(config, client: client),
      );
      final services = AppServices.remote(
        config,
        store: FileStore(root),
        client: client,
      );
      final observations = <Map<String, Object?>>[];
      void observe(String name, Map<String, Object?> details) =>
          observations.add({'case': name, ...details});
      addTearDown(() async {
        services.sync!.outbox.dispose();
        client.close();
        final output = Platform.environment['BOGLE_DIAGNOSTIC_REPORT'];
        if (output != null) {
          await File(output).writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'observations': observations,
              'requests': client.requests,
            }),
          );
        }
        await root.delete(recursive: true);
      });

      final choices = await api.get('/v1/personality-types');
      final choice = (choices['items'] as List).first as Map;
      observe('personality_list', {
        'status': 200,
        'count': (choices['items'] as List).length,
      });
      final serverFriends = <Map<String, dynamic>>[];
      for (final source in GenerationSource.values) {
        final bytes = await api.download(
          '$_url/diagnostic/input/${source.name}',
        );
        final art = await services.generator
            .start(GenerationInput(bytes, source: source))
            .result;
        expect(await File(art.assetPath).exists(), isTrue);
        observe('${source.name}_generate_download', {
          'pngOnDisk': true,
          'jobIdPresent': art.jobId != null,
          'faceOnDisk': await File(
            art.assetPath.replaceAll('.png', '.face.json'),
          ).exists(),
        });

        // 첫 요청은 앱의 createFriend를 그대로 호출한다.
        try {
          await services.characters.createFriend(
            NewFriend(
              name: '진단친구',
              personality: choice['label'] as String,
              favoriteThings: const ['그림'],
              speechStyle: '해요체',
              assetPath: art.assetPath,
              accentHex: art.accentHex,
              generationJobId: art.jobId,
            ),
          );
          observe('${source.name}_app_save', {'status': 201});
        } on ApiException catch (error) {
          observe('${source.name}_app_save', {
            'status': error.statusCode,
            'code': error.code,
            'fieldErrors': error.fieldErrors,
          });
          expect(error.statusCode, 422);
          expect(error.fieldErrors.keys, contains('personalityType'));
        }

        // 이후 서버 기능은 별도 명시적인 서버 규격 요청으로 독립 확인한다.
        final body = {
          'generationJobId': art.jobId,
          'name': '진단친구',
          'personalityType': choice['code'],
          'favoriteThings': ['그림'],
          'speechStyle': '해요체',
        };
        final key = 'server-${art.jobId}';
        if (source == GenerationSource.drawing) {
          client.dropNextPath = '/v1/characters';
        }
        final saved = await api.post(
          '/v1/characters',
          body: body,
          idempotencyKey: key,
        );
        final replay = await api.post(
          '/v1/characters',
          body: body,
          idempotencyKey: key,
        );
        expect(replay['id'], saved['id']);
        serverFriends.add(saved);
        observe('${source.name}_server_save_replay', {
          'sameId': true,
          'face': saved['face'] != null,
          'responseLossInjected': source == GenerationSource.drawing,
        });
        await services.generator.finished(art.jobId!);
      }

      final repo = services.characters as SyncedCharacterRepository;
      await repo.pull();
      final friend = (await repo.fetchFriends()).firstWhere(
        (f) => f.id == serverFriends.first['id'],
      );
      expect(await File(friend.assetPath).exists(), isTrue);
      observe('server_list_to_local', {
        'downloaded': true,
        'sleepBedtime': friend.sleep.bedtime,
      });

      await repo.saveFriend(friend.copyWith(name: '수정된이름'));
      await services.sync!.outbox.flush();
      final server = await api.get('/v1/characters/${friend.id}');
      final local = (await repo.fetchFriends()).firstWhere(
        (f) => f.id == friend.id,
      );
      observe('unsupported_edit_outbox', {
        'serverNameUnchanged': server['name'] == friend.name,
        'localNameChanged': local.name == '수정된이름',
        'pending': await services.sync!.outbox.pending,
      });
      expect(server['name'], friend.name);
      expect(local.name, '수정된이름');
      expect(await services.sync!.outbox.pending, 0);

      final clips = await services.motion.clipsFor(friend);
      observe('unsupported_motion', {'fallback': clips == null});
      expect(clips, isNull);
      final answer = await services.chat.replyTo(friend, '안녕');
      expect(answer, isNotEmpty);
      final pairKey = api.newKey();
      final pairBody = {'clientMessageId': pairKey, 'text': '진단 메시지'};
      final pair = await api.post(
        '/v1/characters/${friend.id}/messages',
        body: pairBody,
      );
      final same = await api.post(
        '/v1/characters/${friend.id}/messages',
        body: pairBody,
      );
      expect(pair['assistantMessage']['id'], same['assistantMessage']['id']);
      observe('chat_replay_history', {
        'sameReply': true,
        'historyCount': (await services.chat.history(friend)).length,
      });

      await api.post('/diagnostic/control/asleep');
      final sleeping = await services.chat.replyTo(friend, '안녕');
      observe('server_sleep_guard', {'appReturnsNull': sleeping == null});
      expect(sleeping, isNull);
      await api.post('/diagnostic/control/awake');

      final otherConfig = ApiConfig(
        apiUrl: _url!,
        supabaseUrl: _url!,
        anonKey: 'local-only',
        email: 'other@bogle.test',
        password: 'local-only',
      );
      final other = ApiClient(
        baseUrl: _url!,
        client: client,
        session: SupabasePasswordSession(otherConfig, client: client),
      );
      try {
        await other.get('/v1/characters/${friend.id}');
        fail('다른 사용자의 친구가 노출됨');
      } on ApiException catch (error) {
        observe('ownership', {'status': error.statusCode});
        expect(error.statusCode, 404);
      }

      for (final mode in ['rejected', 'invalid_png', 'timeout']) {
        await api.post('/diagnostic/control/$mode');
        final bytes = await api.download('$_url/diagnostic/input/photo');
        try {
          await services.generator
              .start(GenerationInput(bytes, source: GenerationSource.photo))
              .result;
          fail('실패 입력이 성공으로 처리됨');
        } on GenerationError catch (error) {
          observe('generation_failure_$mode', {
            'code': error.code,
            'retryable': error.retryable,
          });
        }
      }
      await api.post('/diagnostic/control/success');

      final cancelInput = GenerationInput(
        await api.download('$_url/diagnostic/input/drawing'),
        source: GenerationSource.drawing,
      );
      final cancelled = services.generator.start(cancelInput);
      final cancelledResult = expectLater(
        cancelled.result,
        throwsA(isA<GenerationCancelled>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      cancelled.cancel();
      await cancelledResult;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      observe('app_generation_cancel', {'cancelled': true});

      await repo.deleteFriend(friend.id);
      final immediate = await api.get('/v1/characters/${friend.id}');
      observe('delayed_delete', {
        'serverStillPresent': immediate['id'] == friend.id,
      });
      expect(immediate['id'], friend.id);
      // 서버 직접 삭제는 별도 검증이다. 10초 복구 창을 기다리지 않는다.
      await api.delete('/v1/characters/${friend.id}');
      try {
        await api.get('/v1/characters/${friend.id}/messages');
        fail('삭제된 친구 대화가 조회됨');
      } on ApiException catch (error) {
        expect(error.statusCode, 404);
        observe('server_delete_cascade', {'historyStatus': error.statusCode});
      }
      await Future<void>.delayed(const Duration(seconds: 12));
      observe('server_counts', await api.get('/diagnostic/observations'));
    },
    skip: _url == null
        ? 'diagnostic_server 실행 후 BOGLE_DIAGNOSTIC_URL 설정'
        : false,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
