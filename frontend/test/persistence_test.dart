import 'dart:io';

import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/local_store.dart';
import 'package:bogle_app/src/data/order_repository.dart';
import 'package:bogle_app/src/data/profile_repository.dart';
import 'package:bogle_app/src/data/starter_friends.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:bogle_app/src/models/friend_status.dart';
import 'package:bogle_app/src/screens/house/face_map.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('friends made on the device, their care and memories outlive a '
      'relaunch', () async {
    final store = MemoryStore();
    final first = InMemoryCharacterRepository(store: store);
    final made = await first.createFriend(
      const NewFriend(
        name: '그림이',
        personality: '씩씩해요',
        favoriteThings: ['사과'],
        speechStyle: '반말',
        assetPath: '/somewhere/friend.png',
        accentHex: 0xFFBDCFFF,
      ),
    );
    await first.addMemory(made.id, '같이 놀자!');
    final status = FriendStatus(mood: 33, updatedAt: DateTime.now());
    await first.saveStatus(made.id, status);
    final mungle = (await first.fetchFriends()).first;
    await first.saveFriend(mungle.copyWith(level: 9));

    final again = InMemoryCharacterRepository(store: store);
    final friends = await again.fetchFriends();

    expect(friends.map((f) => f.name), [
      '뭉글이',
      '뚜치',
      '네모린',
      '뽀직뽀직',
      '민들레',
      '귤이',
      '그림이',
    ]);
    expect(friends.first.level, 9);
    expect(await again.fetchMemories(made.id), ['같이 놀자!']);
    expect((await again.fetchStatus(made.id)).mood, 33);
  });

  test("a starter friend always shows the app's own picture", () async {
    final store = MemoryStore();
    final first = InMemoryCharacterRepository(store: store);
    final mungle = (await first.fetchFriends()).first;
    await first.saveFriend(mungle.withArt('/old/place.svg'));

    final again = await InMemoryCharacterRepository(
      store: store,
    ).fetchFriends();

    expect(again.first.assetPath, mungle.assetPath);
  });

  test('starters added to the app move in on an iPad that already keeps '
      'friends; ones said goodbye to stay gone', () async {
    // A save from before the new starters: 뚜치 was let go, a friend made.
    final store = MemoryStore();
    final older = starterFriends().where((f) => f.id != 'dduchi').take(2);
    const made = CharacterFriend(
      id: '1b4e28ba-2fa1-11d2-883f-0016d3cca427',
      name: '구름이',
      personality: '다정한 응원가',
      favoriteThings: ['구름'],
      speechStyle: '반말',
      assetPath: '/art/cloud.png',
      accentHex: 0xFFBDCFFF,
    );
    await store.write('characters', {
      'version': 1,
      'friends': [
        for (final f in [...older, made]) f.toJson(),
      ],
    });

    final friends = await InMemoryCharacterRepository(
      store: store,
    ).fetchFriends();
    expect(friends.map((f) => f.name), [
      '뭉글이',
      '네모린',
      '구름이',
      '뽀직뽀직',
      '민들레',
      '귤이',
    ]);

    // Saying goodbye to a new starter is kept too.
    final repo = InMemoryCharacterRepository(store: store);
    await repo.deleteFriend('gyuri');
    final again = await InMemoryCharacterRepository(
      store: store,
    ).fetchFriends();
    expect(again.map((f) => f.id), isNot(contains('gyuri')));
    expect(again.map((f) => f.id), isNot(contains('dduchi')));
    expect(again.map((f) => f.id), containsAll(['ppojik', 'mindle']));
  });

  test('a picture whose folder moved is found again', () async {
    final home = await Directory.systemTemp.createTemp('bogle_store_');
    addTearDown(() => home.delete(recursive: true));
    final store = FileStore(home);
    await store.art.create(recursive: true);
    await File('${store.art.path}/friend-1.png').writeAsBytes([1, 2, 3]);

    expect(
      store.relocate('/old/container/bogle/art/friend-1.png'),
      '${store.art.path}/friend-1.png',
    );
    expect(
      store.relocate('assets/figma/dduchi.png'),
      'assets/figma/dduchi.png',
    );
  });

  test('a file store reads back what it wrote, and a broken file is preserved '
      'over', () async {
    final home = await Directory.systemTemp.createTemp('bogle_store_');
    addTearDown(() => home.delete(recursive: true));
    final store = FileStore(home);

    await store.write('profile', {'nickname': '별빛'});
    expect(await FileStore(home).read('profile'), {'nickname': '별빛'});

    await File('${home.path}/broken.json').writeAsString('{not json');
    await expectLater(
      store.read('broken'),
      throwsA(isA<StoreRecoveryException>()),
    );
  });

  test('orders, addresses and the profile outlive a relaunch', () async {
    final store = MemoryStore();
    final orders = InMemoryOrderRepository(store: store);
    await orders.saveAddress(
      const DeliveryAddress(
        label: '우리 집',
        recipient: '김보글',
        phone: '010-0000-0000',
        zip: '00000',
        street: '서울특별시 보글구 몽글로 1',
      ),
    );
    await orders.placeOrder(
      const ProfileOrder(
        id: 'BG261008-0001',
        product: '뭉글이 인형',
        asset: 'assets/figma/character_card.svg',
        options: ['M 사이즈 (30cm)'],
        date: '2026.10.08',
        price: 38000,
        status: ProfileOrderStatus.making,
        shipping: ShippingInfo(
          recipient: '김보글',
          address: '서울특별시 보글구 몽글로 1',
          courier: '제작이 끝나면 보내 드려요',
        ),
      ),
    );
    await InMemoryProfileRepository(
      store: store,
    ).saveProfile(const UserProfile(nickname: '별빛', orderNotifications: false));

    final later = InMemoryOrderRepository(store: store);
    final [order] = await later.fetchOrders();
    expect(order.status, ProfileOrderStatus.making);
    expect(order.shipping!.recipient, '김보글');
    expect((await later.fetchAddresses()).single.label, '우리 집');
    final profile = await InMemoryProfileRepository(
      store: store,
    ).fetchProfile();
    expect(profile.nickname, '별빛');
    expect(profile.orderNotifications, isFalse);
  });

  test('a friend keeps its sleep, level and window through JSON', () {
    final friend = CharacterFriend(
      id: 'x',
      name: '구름이',
      personality: '',
      favoriteThings: const [],
      speechStyle: '반말',
      assetPath: 'bogle-asset://a.png',
      accentHex: 0xFFBDCFFF,
      level: 3,
      sleep: const SleepSchedule(bedtime: 1200, wakeTime: 420),
    );

    final back = CharacterFriend.fromJson(friend.toJson());

    expect(back.sleep, friend.sleep);
    expect(back.level, 3);
    expect(back.assetPath, 'bogle-asset://a.png');
  });

  test('giving the same face map again keeps what was worked out from it; '
      'a different one starts over', () {
    const path = '/kept/face-test.png';
    final map = {
      'size': [100, 100],
      'mouth': [50, 70, 20, 8],
    };
    giveFaceMap(path, map);
    final first = faceMapRevision(path);

    giveFaceMap(path, {...map}); // equal, a new object
    expect(faceMapRevision(path), first);

    giveFaceMap(path, {
      ...map,
      'mouth': [40, 72, 20, 8],
    });
    expect(faceMapRevision(path), first + 1);
  });
}
