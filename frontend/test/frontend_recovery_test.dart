import 'dart:io';

import 'package:bogle_app/src/data/app_services.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/conversation_archive.dart';
import 'package:bogle_app/src/data/local_store.dart';
import 'package:bogle_app/src/data/starter_friends.dart';
import 'package:bogle_app/src/screens/friend_screen.dart';
import 'package:bogle_app/src/screens/house/chat_panel.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:bogle_app/src/util/art_cache.dart';
import 'package:bogle_app/src/widgets/bogle_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('손상된 기본 파일은 마지막 정상 저장본으로 읽고 이후 저장도 복구한다', () async {
    final dir = await Directory.systemTemp.createTemp('bogle-recovery');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileStore(dir);
    await store.write('friends', {'name': '첫 친구'});
    await store.write('friends', {'name': '두 번째 친구'});
    await File('${dir.path}/friends.json').writeAsString('{broken');
    final reopened = FileStore(dir);
    expect(await reopened.read('friends'), {'name': '첫 친구'});
    await reopened.write('friends', {'name': '복구한 친구'});
    expect(await FileStore(dir).read('friends'), {'name': '복구한 친구'});
    expect(
      await File('${dir.path}/friends.json.bak').readAsString(),
      contains('첫 친구'),
    );
  });

  test('정상 저장본이 없으면 원본을 덮어쓰거나 새 사용자로 취급하지 않는다', () async {
    final dir = await Directory.systemTemp.createTemp('bogle-preserve');
    addTearDown(() => dir.delete(recursive: true));
    final bad = File('${dir.path}/friends.json');
    await bad.writeAsString('unreadable-original');
    final store = FileStore(dir);
    await expectLater(
      store.read('friends'),
      throwsA(isA<StoreRecoveryException>()),
    );
    await expectLater(
      store.write('friends', {'empty': true}),
      throwsA(isA<StoreRecoveryException>()),
    );
    expect(await bad.readAsString(), 'unreadable-original');
    expect(await store.read('new-user'), isNull);
  });

  test('형식이 깨진 캐릭터 문서를 기본 친구로 덮어쓰지 않는다', () async {
    final store = MemoryStore();
    const broken = {'friends': 'invalid-shape'};
    await store.write('characters', broken);
    final repo = InMemoryCharacterRepository(store: store);
    await expectLater(
      repo.fetchFriends(),
      throwsA(isA<StoreRecoveryException>()),
    );
    await expectLater(
      repo.saveFriend(starterFriends().first),
      throwsA(isA<StoreRecoveryException>()),
    );
    expect(await store.read('characters'), broken);
  });

  test('기본 파일이 유실되어도 정상 백업을 찾는다', () async {
    final dir = await Directory.systemTemp.createTemp('bogle-missing');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileStore(dir);
    await store.write('draft', {'ink': 'kept'});
    await File('${dir.path}/draft.json').delete();
    expect(await FileStore(dir).read('draft'), {'ink': 'kept'});
  });

  test('로컬 대화는 재실행 후에도 순서와 손님 정보를 유지하며 동시 저장이 누락되지 않는다', () async {
    final store = MemoryStore();
    final log = ConversationArchive(store: store);
    final friends = starterFriends();
    await Future.wait([
      log.append(
        'house',
        ConversationEntry((mine: false, text: '어서 와!'), speaker: friends.first),
      ),
      log.append(
        'house',
        ConversationEntry((
          mine: false,
          text: '초대해 줘서 고마워!',
        ), speaker: friends[1]),
      ),
      log.append('house', const ConversationEntry((mine: true, text: '같이 놀자'))),
    ]);
    final restored = await ConversationArchive(store: store).read('house');
    expect(restored.map((e) => e.line.text), ['어서 와!', '초대해 줘서 고마워!', '같이 놀자']);
    expect(restored[1].speaker!.id, friends[1].id);
    expect(restored[1].speaker!.assetPath, friends[1].assetPath);
    expect(await log.read('another-house'), isEmpty);
  });

  test('서버에서 읽은 과거 기록은 현재 기록과 겹치지 않게 저장한다', () async {
    final store = MemoryStore();
    final log = ConversationArchive(store: store);
    const now = ConversationEntry((mine: true, text: '지금 이야기'));
    await log.append('house', now);
    await log.prepend('house', [
      const ConversationEntry((mine: false, text: '예전 이야기')),
      now,
    ]);
    expect(
      (await ConversationArchive(
        store: store,
      ).read('house')).map((e) => e.line.text),
      ['예전 이야기', '지금 이야기'],
    );
  });

  test('캐시는 최근 항목을 유지하며 바이트 한도와 캐릭터 삭제를 반영한다', () {
    final cache = ArtCache<String, String>(2, maxWeight: 10);
    cache['one'] = 'one';
    cache.setWeight('one', 4);
    cache['two'] = 'two';
    cache.setWeight('two', 4);
    expect(cache['one'], 'one');
    cache['three'] = 'three';
    cache.setWeight('three', 4);
    expect(cache.keys, ['one', 'three']);
    cache['huge'] = 'huge';
    cache.setWeight('huge', 20);
    expect(cache, isEmpty);
    cache['deleted-art'] = 'image';
    evictArtwork('deleted-art');
    expect(cache.containsKey('deleted-art'), isFalse);
  });

  testWidgets('이전 이야기에서 집주인과 손님의 아바타가 섞이지 않는다', (tester) async {
    final friends = starterFriends();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBogleTheme(),
        home: Scaffold(
          body: ChatPanel(
            friend: friends.first,
            lines: const [
              (mine: false, text: '어서 와!'),
              (mine: false, text: '고마워!'),
            ],
            speakers: [friends.first, friends[1]],
            enabled: true,
            readOnly: true,
            onSend: (_, _) {},
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final assets = tester
        .widgetList<FriendArtwork>(find.byType(FriendArtwork))
        .map((e) => e.assetPath)
        .toList();
    expect(assets.where((a) => a == friends[1].thumbnail), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('집을 나갔다 돌아와도 로컬 채팅이 이전 이야기에 남는다', (tester) async {
    tester.view.physicalSize = const Size(1194, 834);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = AppServices.local();
    final friend = (await services.characters.fetchFriends()).first;
    Future<void> open() async {
      await tester.pumpWidget(
        AppServicesScope(
          services: services,
          child: MaterialApp(
            theme: buildBogleTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: FriendScreen(
              repository: services.characters,
              friend: friend,
              clock: () => DateTime(2026, 10, 30, 14),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await open();
    await tester.tap(find.bySemanticsLabel('대화하기'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('house-chat-field')),
      '우리의 저장된 이야기',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('보내기'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await open();
    await tester.tap(find.bySemanticsLabel('대화하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이전 이야기'));
    await tester.pumpAndSettle();
    final panel = tester.widget<ChatPanel>(find.byType(ChatPanel));
    expect(panel.lines.any((e) => e.mine && e.text == '우리의 저장된 이야기'), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('글자 200%와 키보드에서도 입력 받침은 화면 안에 머문다', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = AppServices.local();
    final friend = (await services.characters.fetchFriends()).first;
    await tester.pumpWidget(
      AppServicesScope(
        services: services,
        child: MaterialApp(
          theme: buildBogleTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: FriendScreen(
            repository: services.characters,
            friend: friend,
            clock: () => DateTime(2026, 10, 30, 14),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('대화하기'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    final dock = tester.getRect(find.byKey(const ValueKey('chat')));
    expect(dock.top, greaterThanOrEqualTo(0));
    expect(dock.bottom, lessThanOrEqualTo(468));
    expect(tester.takeException(), isNull);
    tester.view.resetViewInsets();
    await tester.pumpWidget(const SizedBox());
  });
}
