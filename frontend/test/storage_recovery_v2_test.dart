import 'dart:io';
import 'dart:convert';
import 'package:bogle_app/src/app.dart';
import 'package:bogle_app/src/data/chat_service.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:bogle_app/src/screens/friend_screen.dart';
import 'package:bogle_app/src/data/app_services.dart';
import 'package:flutter/material.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/conversation_archive.dart';
import 'package:bogle_app/src/data/local_store.dart';
import 'package:bogle_app/src/data/order_repository.dart';
import 'package:bogle_app/src/data/starter_friends.dart';
import 'package:flutter_test/flutter_test.dart';

class CountingStore implements LocalStore {
  final inner = MemoryStore();
  int reads = 0;
  bool fail = false;
  @override
  Future<Object?> read(String name) {
    reads++;
    return inner.read(name);
  }

  @override
  Future<void> write(String name, Object? value) async {
    if (fail) throw const FileSystemException('failed');
    await inner.write(name, value);
  }
}

class RetryHistory implements ChatService {
  int calls = 0;
  @override
  Future<String?> replyTo(CharacterFriend friend, String text) async => null;
  @override
  Future<List<ChatLine>> history(CharacterFriend friend) async {
    calls++;
    if (calls == 1) throw const SocketException('offline');
    return [(mine: true, text: '서버의 예전 이야기'), (mine: false, text: '다시 만나서 좋아')];
  }
}

void main() {
  Future<Directory> folder() async {
    final dir = await Directory.systemTemp.createTemp('bogle-v2');
    addTearDown(() => dir.delete(recursive: true));
    return dir;
  }

  testWidgets('실제 앱 복구 안내에서 보류하면 원본 유지, 승인하면 보관 후 재시작한다', (tester) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('bogle-recovery-ui'),
    ))!;
    addTearDown(() => dir.delete(recursive: true));
    final store = FileStore(dir);
    await tester.runAsync(
      () => File('${dir.path}/orders.json').writeAsString('broken'),
    );
    await tester.pumpWidget(
      BogleApp(services: AppServices.local(store: store)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    Object? failure;
    Future<void> trigger() async {
      await tester.runAsync(() async {
        store
            .read('orders')
            .then(
              (_) {},
              onError: (Object e) {
                failure = e;
              },
            );
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.pump(const Duration(milliseconds: 500));
    }

    await trigger();
    expect(find.text('저장 정보를 복구하지 못했어요'), findsOneWidget);
    expect(find.textContaining('주문·배송지·결제수단'), findsOneWidget);
    await tester.tap(find.text('나중에'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    expect(failure, isA<StoreRecoveryException>());
    expect(
      await tester.runAsync(
        () => File('${dir.path}/orders.json').readAsString(),
      ),
      'broken',
    );
    await trigger();
    await tester.tap(find.text('원본 보관 후 새로 시작'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    expect(
      await tester.runAsync(() => File('${dir.path}/orders.json').exists()),
      isFalse,
    );
    final files = await tester.runAsync(() => dir.list().toList());
    expect(files!.where((f) => f.path.contains('.corrupt-')), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('첫 방문이 오프라인이어도 다음 입장에서 서버 기록을 가져온다', (tester) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final chat = RetryHistory();
    final services = AppServices.local(chat: chat);
    final friend = (await services.characters.fetchFriends()).first;
    Future<void> open() async {
      await tester.pumpWidget(
        AppServicesScope(
          services: services,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: FriendScreen(
              repository: services.characters,
              friend: friend,
              clock: () => DateTime(2026, 10, 31, 14),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await open();
    expect(chat.calls, 1);
    expect(await services.conversations.needsServerHistory(friend.id), isTrue);
    expect(await services.conversations.read(friend.id), isNotEmpty);
    await tester.pumpWidget(const SizedBox());
    await open();
    expect(chat.calls, 2);
    expect(await services.conversations.needsServerHistory(friend.id), isFalse);
    expect(
      (await services.conversations.read(friend.id)).map((e) => e.line.text),
      contains('서버의 예전 이야기'),
    );
    await tester.pumpWidget(const SizedBox());
    await open();
    expect(chat.calls, 2);
    await tester.pumpWidget(const SizedBox());
  });

  test('명시적인 null 문서와 동일 데이터로 복구하는 쓰기도 정상 처리한다', () async {
    final dir = await folder();
    final store = FileStore(dir);
    await store.write('window', null);
    expect(await FileStore(dir).read('window'), isNull);
    await store.write('doc', {'keep': true});
    await File('${dir.path}/doc.json').writeAsString('{bad');
    final reopened = FileStore(dir);
    expect(await reopened.read('doc'), {'keep': true});
    await reopened.write('doc', {'keep': true});
    expect(jsonDecode(await File('${dir.path}/doc.json').readAsString()), {
      'keep': true,
    });
  });

  test('JSON은 정상이지만 친구 항목 구조가 깨졌으면 백업 전체를 복원한다', () async {
    final dir = await folder();
    final store = FileStore(dir);
    final repo = InMemoryCharacterRepository(store: store);
    final friend = (await repo.fetchFriends()).first;
    await repo.saveFriend(friend.copyWith(level: 7));
    await repo.saveFriend(friend.copyWith(level: 8));
    await File(
      '${dir.path}/characters.json',
    ).writeAsString('{"friends":[{"id":3}]}');
    final reopened = InMemoryCharacterRepository(store: FileStore(dir));
    expect((await reopened.fetchFriends()).first.level, 7);
    await reopened.saveFriend(friend.copyWith(level: 9));
    expect(
      (await InMemoryCharacterRepository(
        store: FileStore(dir),
      ).fetchFriends()).first.level,
      9,
    );
  });

  test('주문 복원 중 주소 구조 오류도 정상 백업을 선택한다', () async {
    final dir = await folder();
    final good = {
      'orders': [
        {'id': 'kept', 'product': '인형'},
      ],
      'addresses': [],
      'paymentMethods': [],
    };
    await File('${dir.path}/orders.json.bak').writeAsString(jsonEncode(good));
    await File('${dir.path}/orders.json').writeAsString(
      jsonEncode({
        ...good,
        'addresses': [42],
      }),
    );
    final repo = InMemoryOrderRepository(store: FileStore(dir));
    expect((await repo.fetchOrders()).single.id, 'kept');
  });

  test('복원 실패 주문은 빈 목록 저장으로 손상 원본을 덮어쓰지 않는다', () async {
    final dir = await folder();
    final file = File('${dir.path}/orders.json');
    const broken = '{"orders":[{"id":"kept"}],"addresses":[42]}';
    await file.writeAsString(broken);
    final repo = InMemoryOrderRepository(store: FileStore(dir));
    await expectLater(
      repo.fetchOrders(),
      throwsA(isA<StoreRecoveryException>()),
    );
    await expectLater(
      repo.placeOrder(
        const ProfileOrder(
          id: 'new',
          product: '인형',
          asset: '',
          options: [],
          date: '',
          price: 1,
          status: ProfileOrderStatus.preparing,
        ),
      ),
      throwsA(isA<StoreRecoveryException>()),
    );
    expect(await file.readAsString(), broken);
  });

  test('취소 시 보존하고 같은 저장소에서 다시 시도해 승인하면 격리 후 복구한다', () async {
    final dir = await folder();
    final primary = File('${dir.path}/characters.json');
    final backup = File('${primary.path}.bak');
    await primary.writeAsString('{broken');
    await backup.writeAsString('broken-backup');
    final store = FileStore(dir)..onRecovery = (_) async => false;
    final repo = InMemoryCharacterRepository(store: store);
    await expectLater(
      repo.fetchFriends(),
      throwsA(isA<StoreRecoveryException>()),
    );
    expect(await primary.readAsString(), '{broken');
    expect(await backup.readAsString(), 'broken-backup');
    store.onRecovery = (_) async => true;
    expect(await repo.fetchFriends(), hasLength(starterFriends().length));
    final preserved = await dir
        .list()
        .where((f) => f.path.contains('.corrupt-'))
        .cast<File>()
        .toList();
    expect(preserved, hasLength(2));
    expect(
      await Future.wait(preserved.map((f) => f.readAsString())),
      containsAll(['{broken', 'broken-backup']),
    );
    await repo.saveFriend(starterFriends().first.copyWith(level: 6));
    expect(
      (await InMemoryCharacterRepository(
        store: FileStore(dir),
      ).fetchFriends()).first.level,
      6,
    );
  });

  test('대화는 한 번 읽은 후 캐시를 사용하고 실패한 저장은 캐시에 확정하지 않는다', () async {
    final store = CountingStore();
    final archive = ConversationArchive(store: store);
    await archive.read('friend');
    await archive.append(
      'friend',
      const ConversationEntry((mine: true, text: '하나')),
    );
    store.fail = true;
    await expectLater(
      archive.append(
        'friend',
        const ConversationEntry((mine: true, text: '실패')),
      ),
      throwsA(isA<FileSystemException>()),
    );
    store.fail = false;
    await archive.append(
      'friend',
      const ConversationEntry((mine: true, text: '둘')),
    );
    expect((await archive.read('friend')).map((e) => e.line.text), ['하나', '둘']);
    expect(store.reads, 1);
  });

  test('인사가 저장돼도 서버 가져오기는 미완료로 남고 빈 서버 기록도 성공을 보관한다', () async {
    final store = MemoryStore();
    final archive = ConversationArchive(store: store);
    await archive.append(
      'friend',
      const ConversationEntry((mine: false, text: '안녕')),
    );
    final reopened = ConversationArchive(store: store);
    expect(await reopened.needsServerHistory('friend'), isTrue);
    await reopened.prepend('friend', []);
    expect(
      await ConversationArchive(store: store).needsServerHistory('friend'),
      isFalse,
    );
  });

  test('병합은 같은 문구의 실제 반복을 보존하고 저장 실패 후 재시도한다', () async {
    final store = CountingStore();
    final archive = ConversationArchive(store: store);
    const line = ConversationEntry((mine: true, text: '안녕'));
    await archive.append(
      'friend',
      const ConversationEntry((mine: false, text: '새 인사')),
    );
    store.fail = true;
    await expectLater(
      archive.prepend('friend', [line, line]),
      throwsA(isA<FileSystemException>()),
    );
    expect(await archive.needsServerHistory('friend'), isTrue);
    store.fail = false;
    await archive.prepend('friend', [line, line]);
    await archive.prepend('friend', [line, line]);
    await ConversationArchive(store: store).prepend('friend', [line, line]);
    expect((await archive.read('friend')).map((e) => e.line.text), [
      '안녕',
      '안녕',
      '새 인사',
    ]);
    expect(await archive.needsServerHistory('friend'), isFalse);
  });

  test('대형 JSON 인코딩·디코딩은 isolate에서 왕복하고 연속 저장을 유지한다', () async {
    final dir = await folder();
    final store = FileStore(dir);
    final text = List.filled(100000, '획').join();
    await store.write('sketchbook', {'text': text});
    expect(await FileStore(dir).read('sketchbook'), {'text': text});
    await store.write('sketchbook', {'text': '다음'});
    expect(await FileStore(dir).read('sketchbook'), {'text': '다음'});
    expect(
      jsonDecode(await File('${dir.path}/sketchbook.json.bak').readAsString()),
      {'text': text},
    );
  });
}
