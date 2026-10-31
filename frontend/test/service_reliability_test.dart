import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:bogle_app/src/screens/house/face_map.dart';
import 'package:bogle_app/src/screens/house/figure_motion.dart';
import 'api_test.dart' show Wired;
import 'package:bogle_app/src/data/api/outbox.dart';
import 'package:bogle_app/src/data/api/synced_character_repository.dart';
import 'package:bogle_app/src/data/profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bogle_app/src/data/local_store.dart';
import 'package:bogle_app/src/data/retired_friends.dart';
import 'package:bogle_app/src/data/conversation_archive.dart';
import 'package:bogle_app/src/data/api/api_services.dart';
import 'package:bogle_app/src/data/api/device_art.dart';
import 'package:bogle_app/src/data/starter_friends.dart';
import 'support/api_fixtures.dart';
import 'package:characters/characters.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<Directory> folder() async {
    final dir = await Directory.systemTemp.createTemp('service-reliability');
    addTearDown(() => dir.delete(recursive: true));
    return dir;
  }

  test('긴 이모지 대화도 보이는 200글자 경계에서 완전한 문자로 전송한다', () async {
    String? sent;
    final service = FakeService({
      'POST /v1/characters/$friendId/messages': (request) {
        sent = (jsonDecode(request.body) as Map)['text'] as String;
        return json({
          'assistantMessage': {'text': '잘 들었어'},
        });
      },
    });
    // API only sends for server UUIDs.
    final cloud = SyncedCharacterRepository.friendFrom(
      serverFriend(),
      artPath: 'unused.png',
    );
    await ApiChatService(
      service.api(),
    ).replyTo(cloud, List.filled(201, '👨‍👩‍👧').join());
    expect(sent, List.filled(200, '👨‍👩‍👧').join());
    expect(sent!.characters.length, 200);
  });
  test('서버 조회와 답변 수신이 겹쳐도 낙관적 메시지를 중복 보관하지 않는다', () async {
    final archive = ConversationArchive(store: MemoryStore());
    final friend = starterFriends().first;
    const user = (id: 'sent-user', line: (mine: true, text: '우리 이야기'));
    const reply = (id: 'sent-reply', line: (mine: false, text: '잘 듣고 있어'));
    await archive.append(friend.id, ConversationEntry(user.line));
    await archive.mergeServer(friend, [user, reply]);
    await archive.recordExchange(friend, [user, reply]);
    await archive.append(
      friend.id,
      ConversationEntry(reply.line, speaker: friend),
    );
    expect((await archive.read(friend.id)).map((e) => e.line.text), [
      '우리 이야기',
      '잘 듣고 있어',
    ]);
  });
  test('PNG 입은 입 벌림·씹기 포즈에서도 덧그리지 않는다', () async {
    for (final mouth in [-1.0, 1.0]) {
      final pose = ValueNotifier(FigurePose(mouth: mouth));
      final recorder = ui.PictureRecorder();
      FacePainter(
        const FaceMap(
          size: Size(100, 100),
          mouth: Rect.fromLTWH(35, 60, 30, 10),
        ),
        pose,
      ).paint(Canvas(recorder), const Size(100, 100));
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 100);
      final pixels = await image.toByteData();
      expect(pixels!.buffer.asUint8List().every((byte) => byte == 0), isTrue);
      pose.dispose();
      image.dispose();
      picture.dispose();
    }
  });
  test('친구 이미지 하나의 실패가 뒤의 친구·프로필 텍스트 복원을 막지 않는다', () async {
    final service = FakeService({
      'GET /v1/characters': (_) => json({
        'items': [
          serverFriend(id: otherFriendId),
          {
            ...serverFriend(),
            'art': image('bad', 'https://bad.test/unavailable'),
          },
        ],
      }),
      'GET /v1/me': (_) => json({
        ...me(nickname: '복원된 이름'),
        'bio': '복원된 소개',
        'avatarCharacterId': friendId,
      }),
    });
    final store = MemoryStore();
    final wired = Wired(service, store, await folder());
    addTearDown(wired.outbox.dispose);
    expect(await wired.characters.pull(), 1);
    final profile = SyncedProfileRepository(
      service.api(),
      local: InMemoryProfileRepository(store: store),
      characters: wired.characters,
      outbox: wired.outbox,
      store: store,
    );
    await profile.pull();
    expect((await profile.fetchProfile()).nickname, '복원된 이름');
    expect((await profile.fetchProfile()).bio, '복원된 소개');
    expect(await store.read('pending_profile_avatar'), friendId);
  });
  test('거절된 변경은 재실행 후 확인 가능하며 새 수정으로 해소된다', () async {
    final service = FakeService({
      'PATCH /v1/me': (_) => json({
        'error': {
          'code': 'validation_error',
          'fieldErrors': {'bio': 'invalid'},
        },
      }, 422),
    });
    final store = MemoryStore();
    final first = Outbox(service.api(), store: store);
    addTearDown(first.dispose);
    await first.patchProfile({'bio': '실패한 소개'});
    await first.flush();
    final reopened = Outbox(service.api(), store: store);
    addTearDown(reopened.dispose);
    expect((await reopened.rejected).single['fields'], {'bio': '실패한 소개'});
    expect(await reopened.pendingFields(null), contains('bio'));
    service.routes['PATCH /v1/me'] = (_) => json(me());
    await reopened.patchProfile({'bio': '새 소개'});
    await reopened.flush();
    expect(await reopened.rejected, isEmpty);
  });
  test('깨진 UTF-8 바이트는 읽기와 직접 쓰기 모두 정상 백업을 사용한다', () async {
    for (final readFirst in [true, false]) {
      final dir = await folder();
      await File('${dir.path}/doc.json').writeAsBytes([255, 254, 192]);
      await File('${dir.path}/doc.json.bak').writeAsString('{"kept":true}');
      final store = FileStore(dir);
      if (readFirst) expect(await store.read('doc'), {'kept': true});
      await store.write('doc', {'new': true});
      expect(
        jsonDecode(await File('${dir.path}/doc.json.bak').readAsString()),
        {'kept': true},
      );
    }
  });
  test('두 사본의 UTF-8이 깨져도 원본 보관 후 새로 시작할 수 있다', () async {
    final dir = await folder();
    for (final suffix in ['', '.bak']) {
      await File('${dir.path}/doc.json$suffix').writeAsBytes([255]);
    }
    var offered = false;
    final store = FileStore(dir)
      ..onRecovery = (_) async {
        offered = true;
        return true;
      };
    expect(await store.read('doc'), isNull);
    expect(offered, isTrue);
    expect(
      (await dir.list().toList()).where((f) => f.path.contains('.corrupt-')),
      hasLength(2),
    );
  });
  test('앱 시작의 이어 만들기 조회는 요청 키가 있어도 유료 POST를 보내지 않는다', () async {
    final store = MemoryStore();
    await store.write('pending_generation', {
      'requestKey': 'persisted-key',
      'sourceAssetId': 'source',
      'sourceType': 'photo',
    });
    final service = FakeService({
      'POST /v1/generations': (_) => json(generationSucceeded()),
    });
    final generator = ApiCharacterGenerator(
      service.api(),
      art: DeviceArt(await folder()),
      store: store,
    );
    final job = await generator.unfinished();
    expect(job, isNotNull);
    expect(service.to('/v1/generations'), isEmpty);
    expect((await job!.result).jobId, jobId);
    expect(service.to('/v1/generations'), hasLength(1));
  });
  test('재실행 후 만료된 작별의 그림·얼굴·대화·백업을 정리한다', () async {
    final dir = await folder();
    final store = FileStore(dir);
    await store.art.create();
    final path = '${store.art.path}/friend.png';
    for (final name in ['friend.png', 'friend.thumb.png', 'friend.face.json']) {
      await File('${store.art.path}/$name').writeAsString('asset');
    }
    await store.write('conversation-friend', [
      {'text': '이야기'},
    ]);
    await store.write('retired_friends', {
      'friend': {
        'paths': [path],
        'after': 0,
      },
    });
    await RetiredFriends(FileStore(dir), () => []).sweep();
    expect(await File(path).exists(), isFalse);
    expect(
      await File('${dir.path}/conversation-friend.json').exists(),
      isFalse,
    );
    expect(
      await File('${dir.path}/conversation-friend.json.bak').exists(),
      isFalse,
    );
  });
  test('되돌린 친구는 삭제 대기 기록이 남아도 그림과 대화를 보호한다', () async {
    final dir = await folder();
    final store = FileStore(dir);
    await store.art.create();
    final path = '${store.art.path}/friend.png';
    await File(path).writeAsString('asset');
    await store.write('conversation-friend', []);
    await store.write('retired_friends', {
      'friend': {
        'paths': [path],
        'after': 0,
      },
    });
    await RetiredFriends(store, () => [path]).sweep();
    expect(await File(path).exists(), isTrue);
    expect(await File('${dir.path}/conversation-friend.json').exists(), isTrue);
  });
  test('서버 메시지 ID로 동일 문구를 보존하면서 중복 가져오기를 막는다', () async {
    final store = MemoryStore();
    final archive = ConversationArchive(store: store);
    final friend = starterFriends().first;
    final lines = [
      (id: '1', line: (mine: true, text: '안녕')),
      (id: '2', line: (mine: true, text: '안녕')),
    ];
    await archive.mergeServer(friend, lines);
    await archive.mergeServer(friend, lines);
    expect((await archive.read(friend.id)).map((e) => e.line.text), [
      '안녕',
      '안녕',
    ]);
    final reopened = ConversationArchive(store: store);
    await reopened.mergeServer(friend, lines);
    expect(await reopened.read(friend.id), hasLength(2));
  });
}
