import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bogle_app/src/data/api/api_client.dart';
import 'package:bogle_app/src/data/api/api_services.dart';
import 'package:bogle_app/src/data/api/device_art.dart';
import 'package:bogle_app/src/data/api/outbox.dart';
import 'package:bogle_app/src/data/api/synced_character_repository.dart';
import 'package:bogle_app/src/data/character_generation.dart';
import 'package:bogle_app/src/data/art_source.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/local_store.dart';
import 'package:bogle_app/src/data/motion_service.dart';
import 'package:bogle_app/src/data/profile_repository.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:bogle_app/src/screens/house/face_map.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/api_fixtures.dart';

Future<Directory> tempFolder() async {
  final folder = await Directory.systemTemp.createTemp('bogle_api_test_');
  addTearDown(() => folder.delete(recursive: true));
  return folder;
}

/// The pieces of the app wired to [service], kept in [store] and [folder].
class Wired {
  Wired(this.service, this.store, Directory folder)
    : art = DeviceArt(Directory('${folder.path}/art')) {
    api = service.api();
    outbox = Outbox(api, store: store);
    characters = SyncedCharacterRepository(
      api,
      local: InMemoryCharacterRepository(store: store),
      outbox: outbox,
      art: art,
      undoWindow: const Duration(milliseconds: 80),
    );
  }
  final FakeService service;
  final LocalStore store;
  final DeviceArt art;
  late final ApiClient api;
  late final Outbox outbox;
  late final SyncedCharacterRepository characters;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiClient', () {
    test('signs in once and signs every request', () async {
      final service = FakeService({'GET /v1/me': (_) => json(me())});
      final api = service.api();

      await api.get('/v1/me');
      await api.get('/v1/me');

      expect(service.tokens, 1);
      expect(
        service.to('/v1/me').map((r) => r.headers['Authorization']),
        everyElement('Bearer token-1'),
      );
    });

    test(
      'an expired token is refreshed once and the request retried',
      () async {
        final service = FakeService({'GET /v1/me': (_) => json(me())});
        final api = service.api();
        await api.get('/v1/me');
        service.expireNextToken = true;

        expect((await api.get('/v1/me'))['nickname'], '별빛');
        expect(service.tokens, 2);
      },
    );

    test("the service's errors arrive with their code and message", () async {
      final service = FakeService({
        'POST /v1/characters': (_) => json({
          'error': {
            'code': 'validation_error',
            'message': '입력값을 확인해 주세요.',
            'retryable': false,
            'fieldErrors': {'name': 'string_too_long'},
          },
        }, 422),
      });

      await expectLater(
        service.api().post('/v1/characters', body: {}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'validation_error')
              .having((e) => e.fieldErrors, 'fieldErrors', {
                'name': 'string_too_long',
              }),
        ),
      );
    });

    test('a read is tried once more after a passing problem, after the wait '
        'the service asks for', () async {
      var calls = 0;
      final service = FakeService({
        'GET /v1/me': (_) => ++calls == 1
            ? http.Response.bytes(
                utf8.encode(
                  jsonEncode({
                    'error': {
                      'code': 'service_unavailable',
                      'message': '잠시 후 다시 시도해 주세요.',
                      'retryable': true,
                    },
                  }),
                ),
                503,
                headers: {'retry-after': '2'},
              )
            : json(me()),
      });
      final waits = <Duration>[];

      final answer = await service
          .api(wait: (d) async => waits.add(d))
          .get('/v1/me');

      expect(answer['nickname'], '별빛');
      expect(waits, [const Duration(seconds: 2)]);
    });

    test('a write without an idempotency key is never sent twice', () async {
      final service = FakeService({
        'PATCH /v1/me': (_) => json({
          'error': {'code': 'service_unavailable', 'retryable': true},
        }, 503),
      });

      await expectLater(
        service.api().patch('/v1/me', {'nickname': '별빛'}),
        throwsA(isA<ApiException>()),
      );
      expect(service.to('/v1/me'), hasLength(1));
    });

    test('keys are UUID v4', () {
      expect(
        FakeService({}).api().newKey(),
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });
  });

  group('Outbox', () {
    test('edits to one friend go out as one request', () async {
      final service = FakeService({
        'PATCH /v1/characters/$friendId': (r) => json(serverFriend()),
      });
      service.offline = true;
      final outbox = Outbox(service.api(), store: MemoryStore());

      await outbox.patchCharacter(friendId, {'name': '뭉게'});
      await outbox.patchCharacter(friendId, {'bedtime': 1260});
      await outbox.flush(); // still offline: nothing goes
      service.offline = false;
      service.requests.clear(); // the tries made while offline
      await outbox.flush();

      final sent = service.to('/v1/characters/$friendId');
      expect(sent, hasLength(1));
      expect(jsonDecode(sent.single.body), {'name': '뭉게', 'bedtime': 1260});
      expect(await outbox.pending, 0);
    });

    test(
      'what the service could not hear yet is sent after a relaunch',
      () async {
        final store = MemoryStore();
        final service = FakeService({'PATCH /v1/me': (_) => json(me())})
          ..offline = true;
        final before = Outbox(service.api(), store: store);
        await before.patchProfile({'nickname': '별빛'});
        await before.flush();
        expect(await before.pending, 1);
        before.dispose();

        service.offline = false;
        final after = Outbox(service.api(), store: store);
        await after.flush();

        expect(
          service.to('/v1/me').where((r) => r.method == 'PATCH'),
          isNotEmpty,
        );
        expect(await after.pending, 0);
      },
    );

    test(
      'a deletion waits for its delay and can be undone until then',
      () async {
        final service = FakeService({
          'DELETE /v1/characters/$friendId': (_) => http.Response('', 204),
        });
        final outbox = Outbox(service.api(), store: MemoryStore());

        await outbox.deleteCharacter(
          friendId,
          delay: const Duration(milliseconds: 60),
        );
        await outbox.flush();
        expect(service.to('/v1/characters/$friendId'), isEmpty);
        expect(await outbox.cancelDelete(friendId), isTrue);

        await outbox.deleteCharacter(
          friendId,
          delay: const Duration(milliseconds: 60),
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(service.to('/v1/characters/$friendId').single.method, 'DELETE');
      },
    );

    test('a friend the service no longer has is deleted already; a refused '
        'edit is dropped', () async {
      final service = FakeService({
        'DELETE /v1/characters/$friendId': (_) => json({
          'error': {'code': 'not_found', 'message': '없어요.'},
        }, 404),
        'PATCH /v1/characters/$otherFriendId': (_) => json({
          'error': {'code': 'validation_error', 'message': '확인해 주세요.'},
        }, 422),
      });
      final outbox = Outbox(service.api(), store: MemoryStore());

      await outbox.deleteCharacter(friendId);
      await outbox.patchCharacter(otherFriendId, {'name': ''});
      await outbox.flush();

      expect(await outbox.pending, 0);
    });
  });

  group('SyncedCharacterRepository', () {
    test('the archive reads the iPad; it never asks the service', () async {
      final wired = Wired(FakeService({}), MemoryStore(), await tempFolder());

      final friends = await wired.characters.fetchFriends();

      expect(friends.map((f) => f.name), [
        '뭉글이',
        '뚜치',
        '네모린',
        '뽀직뽀직',
        '민들레',
        '귤이',
      ]);
      expect(wired.service.requests, isEmpty);
    });

    test('friends on the service but not on the iPad are brought in, '
        'pictures and face maps saved as files', () async {
      final service = FakeService({
        'GET /v1/characters': (_) => json({
          'items': [
            serverFriend(),
            serverFriend(id: otherFriendId, name: '먼저'),
          ],
          'nextCursor': null,
        }),
      });
      final wired = Wired(service, MemoryStore(), await tempFolder());

      expect(await wired.characters.pull(), 2);
      expect(await wired.characters.pull(), 0); // already here

      final friends = await wired.characters.fetchFriends();
      expect(friends.map((f) => f.name), [
        '뭉글이',
        '뚜치',
        '네모린',
        '뽀직뽀직',
        '민들레',
        '귤이',
        '먼저',
        '구름이',
      ]);
      final cloud = friends.last;
      expect(File(cloud.assetPath).existsSync(), isTrue);
      expect(File(cloud.thumbnail).existsSync(), isTrue);
      expect(cloud.thumbnail, isNot(cloud.assetPath));
      expect(cloud.sleep, const SleepSchedule(bedtime: 1320, wakeTime: 360));
      // The generator's picture has clear margins: it's shown cut to the
      // figure, and its face map (812 × 1024 in the fixture) moves with it.
      final crop = (await artCropOf(cloud.assetPath))!;
      final map = await faceMapFor(cloud.assetPath);
      expect(
        map!.mouth!.center,
        const Offset(405, 360) - Offset(crop.left * 812, crop.top * 1024),
      );
      expect(
        File(cloud.assetPath.replaceFirst('.png', '.face.json')).existsSync(),
        isTrue,
      );
    });

    test('a new friend is made on the service and kept on the iPad with the '
        "generator's pictures", () async {
      final service = FakeService({
        'POST /v1/characters': (_) => json(serverFriend(), 201),
      });
      final wired = Wired(service, MemoryStore(), await tempFolder());

      final made = await wired.characters.createFriend(
        const NewFriend(
          name: '구름이',
          personality: '엉뚱해요',
          favoriteThings: ['구름'],
          speechStyle: '해요체',
          assetPath: '/kept/job.png',
          thumbnailPath: '/kept/job.thumb.png',
          accentHex: 0xFFBDCFFF,
          generationJobId: jobId,
        ),
      );

      final sent = service.to('/v1/characters').single;
      expect(sent.headers['Idempotency-Key'], isNotEmpty);
      expect(jsonDecode(sent.body)['generationJobId'], jobId);
      expect(made.id, friendId);
      expect(made.assetPath, '/kept/job.png');
      expect((await wired.characters.fetchFriends()).last.id, friendId);
    });

    test('the introduction setup wrote from the answers replaces the '
        "service's own", () async {
      final service = FakeService({
        'POST /v1/characters': (_) => json(serverFriend(), 201),
        'PATCH /v1/characters/$friendId': (_) => json(serverFriend()),
      });
      final wired = Wired(service, MemoryStore(), await tempFolder());
      const introduction = '구름 구경을 좋아하는 엉뚱한 상상가예요.';

      final made = await wired.characters.createFriend(
        const NewFriend(
          name: '구름이',
          personality: '엉뚱한 상상가, 상상 놀이를 제안해요',
          favoriteThings: ['구름'],
          speechStyle: '반말',
          assetPath: '/kept/job.png',
          accentHex: 0xFFBDCFFF,
          introduction: introduction,
          generationJobId: jobId,
        ),
      );
      await wired.outbox.flush();

      expect(made.introduction, introduction);
      expect(
        (await wired.characters.fetchFriends()).last.introduction,
        introduction,
      );
      expect(jsonDecode(service.to('/v1/characters/$friendId').single.body), {
        'introduction': introduction,
      });
    });

    test(
      'an edit is saved on the iPad at once and sends only what changed',
      () async {
        final service = FakeService({
          'GET /v1/characters': (_) => json({
            'items': [serverFriend()],
          }),
          'PATCH /v1/characters/$friendId': (_) => json(serverFriend()),
        });
        final wired = Wired(service, MemoryStore(), await tempFolder());
        await wired.characters.pull();
        final friend = (await wired.characters.fetchFriends()).last;

        await wired.characters.saveFriend(
          friend.copyWith(
            name: '뭉게',
            sleep: const SleepSchedule(bedtime: 1260, wakeTime: 360),
            memories: 3,
          ),
        );
        await wired.outbox.flush();

        final saved = (await wired.characters.fetchFriends()).last;
        expect((saved.name, saved.memories), ('뭉게', 3));
        expect(jsonDecode(service.to('/v1/characters/$friendId').single.body), {
          'name': '뭉게',
          'bedtime': 1260,
        });
      },
    );

    test('a deletion is undoable; one not undone reaches the service even '
        'if the app closes first', () async {
      final store = MemoryStore();
      final folder = await tempFolder();
      final service = FakeService({
        'GET /v1/characters': (_) => json({
          'items': [serverFriend()],
        }),
        'DELETE /v1/characters/$friendId': (_) => http.Response('', 204),
      });
      final wired = Wired(service, store, folder);
      await wired.characters.pull();

      final deleted = await wired.characters.deleteFriend(friendId);
      expect(
        (await wired.characters.fetchFriends()).map((f) => f.id),
        isNot(contains(friendId)),
      );
      await wired.characters.restoreFriend(deleted!);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(service.to('/v1/characters/$friendId'), isEmpty);
      expect(
        (await wired.characters.fetchFriends()).map((f) => f.id),
        contains(friendId),
      );

      // Deleted, and the app closes before the undo runs out.
      await wired.characters.deleteFriend(friendId);
      wired.outbox.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final relaunched = Wired(service, store, folder);
      await relaunched.outbox.flush();
      expect(service.to('/v1/characters/$friendId').single.method, 'DELETE');
    });
  });

  group('ApiCharacterGenerator', () {
    FakeService generating({required List<Map<String, dynamic>> states}) {
      var polls = 0;
      return FakeService({
        'POST /v1/assets': (_) =>
            json(image('src-1', 'https://cdn.test/src.png'), 201),
        'POST /v1/generations': (_) => json(states.first, 202),
        'GET /v1/generations/$jobId': (_) =>
            json(states[(++polls).clamp(0, states.length - 1)]),
        'POST /v1/generations/$jobId/cancel': (_) =>
            json({'jobId': jobId, 'status': 'cancelled'}),
      });
    }

    test('follows the job and keeps the finished friend on the iPad', () async {
      final service = generating(
        states: [
          generationWaiting('queued'),
          generationWaiting('processing'),
          generationSucceeded(),
        ],
      );
      final folder = await tempFolder();
      final waits = <Duration>[];
      final generator = ApiCharacterGenerator(
        service.api(),
        art: DeviceArt(folder),
        wait: (d) async => waits.add(d),
      );

      final art = await generator
          .start(
            GenerationInput(await pngBytes(), source: GenerationSource.drawing),
          )
          .result;

      expect(art.jobId, jobId);
      expect(art.accentHex, 4294945450);
      expect(art.assetPath, '${folder.path}/$jobId.png');
      expect(File(art.assetPath).existsSync(), isTrue);
      expect(File(art.thumbnailPath!).existsSync(), isTrue);
      expect(waits, [const Duration(seconds: 2), const Duration(seconds: 2)]);
      expect((await faceMapFor(art.assetPath))?.mouth, isNotNull);
    });

    test(
      "a refusal comes back with the service's words and no retry",
      () async {
        final service = generating(
          states: [generationFailed('generation_rejected', retryable: false)],
        );
        final generator = ApiCharacterGenerator(
          service.api(),
          art: DeviceArt(await tempFolder()),
          wait: (_) async {},
        );

        await expectLater(
          generator
              .start(
                GenerationInput(
                  await pngBytes(),
                  source: GenerationSource.photo,
                ),
              )
              .result,
          throwsA(
            isA<GenerationError>()
                .having((e) => e.code, 'code', 'generation_rejected')
                .having((e) => e.retryable, 'retryable', false),
          ),
        );
      },
    );

    test(
      'a retry of the same picture reuses its upload with a new key',
      () async {
        final service = generating(
          states: [generationFailed('generation_unavailable', retryable: true)],
        );
        final generator = ApiCharacterGenerator(
          service.api(),
          art: DeviceArt(await tempFolder()),
          wait: (_) async {},
        );
        final input = GenerationInput(
          await pngBytes(),
          source: GenerationSource.drawing,
        );

        for (var i = 0; i < 2; i++) {
          await expectLater(
            generator.start(input).result,
            throwsA(isA<GenerationError>()),
          );
        }

        expect(service.to('/v1/assets'), hasLength(1));
        final keys = service
            .to('/v1/generations')
            .map((r) => r.headers['Idempotency-Key']);
        expect(keys.toSet(), hasLength(2));
      },
    );

    test(
      'cancelling asks the service and never hands over the artwork',
      () async {
        final service = generating(states: [generationWaiting('queued')]);
        final started = Completer<void>();
        final generator = ApiCharacterGenerator(
          service.api(),
          art: DeviceArt(await tempFolder()),
          wait: (_) {
            if (!started.isCompleted) started.complete();
            return Completer<void>().future;
          },
        );
        final job = generator.start(
          GenerationInput(await pngBytes(), source: GenerationSource.drawing),
        );
        final outcome = expectLater(
          job.result,
          throwsA(isA<GenerationCancelled>()),
        );
        await started.future;

        job.cancel();
        await outcome;
        await Future<void>.delayed(Duration.zero);

        expect(service.to('/v1/generations/$jobId/cancel'), hasLength(1));
      },
    );

    test('a job started before the app closed is picked up, and dropped once '
        'its friend is made', () async {
      final store = MemoryStore();
      final folder = await tempFolder();
      final service = generating(
        states: [generationWaiting('queued'), generationSucceeded()],
      );
      ApiCharacterGenerator(
        service.api(),
        art: DeviceArt(folder),
        store: store,
        wait: (_) => Completer<void>().future, // the app closes mid-wait
      ).start(
        GenerationInput(
          await pngBytes(),
          source: GenerationSource.drawing,
          sketchRevision: 'submitted-sketch-1',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final after = ApiCharacterGenerator(
        service.api(),
        art: DeviceArt(folder),
        store: store,
      );
      final job = await after.unfinished();
      final art = await job!.result;
      expect(art.jobId, jobId);
      expect(art.sketchRevision, 'submitted-sketch-1');
      expect(File(art.assetPath).existsSync(), isTrue);

      await after.finished(jobId);
      expect(await after.unfinished(), isNull);
    });
  });

  group('chat, motion and profile', () {
    final remote = CharacterFriend.fromJson({
      'id': friendId,
      'name': '구름이',
      'speechStyle': '해요체',
      'assetPath': '/kept/art.png',
      'accentHex': 0xFFBDCFFF,
    });
    final starter = CharacterFriend.fromJson({
      ...remote.toJson(),
      'id': 'mungle',
    });

    test(
      'the service answers for its friends; starters answer themselves',
      () async {
        final service = FakeService({
          'POST /v1/characters/$friendId/messages': (r) => json({
            'userMessage': message(
              'user',
              jsonDecode(r.body)['text'] as String,
            ),
            'assistantMessage': message('assistant', '구름 구경했어요!'),
          }),
        });
        final chat = ApiChatService(service.api());

        expect(await chat.replyTo(remote, '오늘 뭐 했어?'), '구름 구경했어요!');
        expect(await chat.replyTo(starter, '안녕'), isNull);
      },
    );

    test('the chat so far comes back oldest first', () async {
      final service = FakeService({
        'GET /v1/characters/$friendId/messages': (_) => json({
          'items': [
            message('assistant', '구름 구경했어요!'),
            message('user', '오늘 뭐 했어?'),
          ],
          'nextCursor': null,
        }),
      });

      expect(await ApiChatService(service.api()).history(remote), [
        (mine: true, text: '오늘 뭐 했어?'),
        (mine: false, text: '구름 구경했어요!'),
      ]);
    });

    test('an asleep friend leaves the answer to the app', () async {
      final service = FakeService({
        'POST /v1/characters/$friendId/messages': (_) => json({
          'error': {'code': 'character_asleep', 'message': '자고 있어요.'},
        }, 409),
      });

      expect(await ApiChatService(service.api()).replyTo(remote, '안녕'), isNull);
    });

    test(
      'ready clips are kept on the iPad and played from there next time',
      () async {
        var asks = 0;
        final service = FakeService({
          'GET /v1/characters/$friendId/motion': (_) => json(
            ++asks < 2
                ? {'status': 'working', 'reason': null, 'clips': {}}
                : motionReady(),
          ),
        });
        final folder = await tempFolder();
        final motion = ApiMotionService(
          service.api(),
          folder: folder,
          poll: Duration.zero,
        );

        final clips = await motion.clipsFor(remote);
        final again = await ApiMotionService(
          service.api(),
          folder: folder,
        ).clipsFor(remote);

        expect(clips!.keys, [MotionClipKind.jump]);
        expect(File(clips[MotionClipKind.jump]!.url).existsSync(), isTrue);
        expect(
          clips[MotionClipKind.jump]!.box,
          const Rect.fromLTRB(.1, .05, .9, .95),
        );
        expect(
          again![MotionClipKind.jump]!.url,
          clips[MotionClipKind.jump]!.url,
        );
        expect(service.to('/v1/characters/$friendId/motion'), hasLength(2));
      },
    );

    test('art that cannot be animated uses the app motions', () async {
      final service = FakeService({
        'GET /v1/characters/$friendId/motion': (_) => json({
          'status': 'unsupported',
          'reason': 'not_humanoid',
          'clips': {},
        }),
      });

      expect(await ApiMotionService(service.api()).clipsFor(remote), isNull);
    });

    test(
      'the profile is kept on the iPad and the service hears what changed',
      () async {
        final store = MemoryStore();
        final service = FakeService({
          'GET /v1/characters': (_) => json({
            'items': [serverFriend()],
          }),
          'GET /v1/me': (_) => json(me(nickname: '새벽')),
          'PATCH /v1/me': (_) => json(me()),
        });
        final wired = Wired(service, store, await tempFolder());
        await wired.characters.pull();
        final profile = SyncedProfileRepository(
          wired.api,
          local: InMemoryProfileRepository(store: store),
          characters: wired.characters,
          outbox: wired.outbox,
          store: store,
        );

        await profile.pull(); // a fresh install takes the service's settings
        expect((await profile.fetchProfile()).nickname, '새벽');
        expect((await profile.fetchProfile()).friendNotifications, isFalse);

        final cloud = (await wired.characters.fetchFriends()).last;
        await profile.saveProfile(
          (await profile.fetchProfile()).copyWith(
            nickname: '별빛',
            bio: '구름이 좋아요.',
            interests: ['상상 놀이'],
            profileColor: 'mint',
            avatar: cloud.assetPath,
          ),
        );
        await wired.outbox.flush();

        expect((await profile.fetchProfile()).nickname, '별빛');
        final patch = service
            .to('/v1/me')
            .where((r) => r.method == 'PATCH')
            .single;
        expect(jsonDecode(patch.body), {
          'nickname': '별빛',
          'bio': '구름이 좋아요.',
          'interests': ['상상 놀이'],
          'profileColor': 'mint',
          'avatarCharacterId': friendId,
        });
        await profile.pull(); // already set up: the iPad's profile stays
        expect((await profile.fetchProfile()).nickname, '별빛');
      },
    );
  });
}
