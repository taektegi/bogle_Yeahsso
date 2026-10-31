import 'dart:math' as math;

import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/friend_talk.dart';
import 'package:bogle_app/src/data/korean.dart';
import 'package:bogle_app/src/data/local_store.dart';
import 'package:bogle_app/src/data/starter_friends.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:flutter_test/flutter_test.dart';

class _Pick implements math.Random {
  _Pick(this.index);
  final int index;
  @override
  int nextInt(int max) => index % max;
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
}

CharacterFriend friend(String style, {List<String> favorites = const ['구름']}) =>
    CharacterFriend(
      id: 'x',
      name: '구름이',
      personality: '다정해요',
      speechStyle: style,
      favoriteThings: favorites,
      assetPath: 'unused.svg',
      accentHex: 0,
    );

void main() {
  test('음식 받침에 맞춰 이야·야, 이에요·예요, 이라니·라니를 고른다', () {
    for (final item in [
      ('밤', '밤이야', '밤이에요', '밤이라니'),
      ('도토리', '도토리야', '도토리예요', '도토리라니'),
      ('빵', '빵이야', '빵이에요', '빵이라니'),
      ('사과', '사과야', '사과예요', '사과라니'),
    ]) {
      final casual = FriendTalk(friend('반말'), random: _Pick(1));
      final polite = FriendTalk(friend('해요체'), random: _Pick(1));
      final jiyo = FriendTalk(friend('~지요!'), random: _Pick(1));
      expect(
        casual.say(TalkTopic.treat, thing: item.$1),
        startsWith('${item.$2}!'),
      );
      expect(
        polite.say(TalkTopic.treat, thing: item.$1),
        startsWith('${item.$3}!'),
      );
      expect(
        jiyo.say(TalkTopic.treat, thing: item.$1),
        startsWith('${item.$4},'),
      );
    }
  });

  test('이름·취향 조사는 받침과 공백을 고려하고 입력을 재해석하지 않는다', () {
    expect(koreanTemplate('{f:은/는} 자요', {'f': '하늘 '}), '하늘은 자요');
    expect(
      koreanTemplate('{f:과/와} {s:을/를} 먹었어.', {'f': '네모린', 's': '밤'}),
      '네모린과 밤을 먹었어.',
    );
    expect(koreanTemplate('{f}', {'f': '{f:은/는}'}), '{f:은/는}');
    final talk = FriendTalk(
      friend('반말', favorites: ['  ', '밤']),
      random: _Pick(0),
    );
    expect(talk.say(TalkTopic.likes), '밤이 제일 좋아!');
  });

  test('다정한 반말과 공손한 존댓말을 구분한다', () {
    expect(FriendTalk(friend('다정한 반말')).register, Register.casual);
    expect(FriendTalk(friend('느긋한 존댓말')).register, Register.polite);
    expect(FriendTalk(friend('공손하게')).register, Register.polite);
    expect(FriendTalk(friend('동화처럼 ~지요!')).register, Register.jiyo);
  });

  test('질문과 조용한 잠꼬대의 문장부호를 보존한다', () {
    final talk = FriendTalk(friend('느긋하게'), random: _Pick(1));
    expect(talk.say(TalkTopic.play), endsWith('?'));
    expect(talk.say(TalkTopic.sleep), endsWith('…'));
    expect(talk.say(TalkTopic.today), endsWith('~'));
  });

  test('배고프다는 대화와 먹은 뒤 반응, 애정과 취향 질문을 구분한다', () {
    final talk = FriendTalk(friend('반말'), random: _Pick(0));
    expect(talk.topicFor('나 배고파'), TalkTopic.hungry);
    expect(talk.say(talk.topicFor('나 배고파')), contains('같이 먹을까?'));
    expect(talk.say(TalkTopic.snack), contains('맛있어'));
    expect(talk.topicFor('너를 좋아해'), TalkTopic.love);
    expect(talk.topicFor('너는 뭘 좋아해?'), TalkTopic.likes);
    expect(talk.topicFor('네가 좋아하는 건 뭐야?'), TalkTopic.likes);
    expect(talk.topicFor('널 좋아하지 않아'), isNot(TalkTopic.love));
  });

  test('방문객은 자기 집에 온 것처럼 말하지 않고 초대에 답한다', () {
    for (final style in ['반말', '해요체', '~지요!']) {
      for (var choice = 0; choice < 2; choice++) {
        final text = FriendTalk(
          friend(style),
          random: _Pick(choice),
        ).say(TalkTopic.visit);
        expect(text, matches(RegExp('초대|놀러')));
        expect(text, isNot(contains('우리 집')));
        expect(text, isNot(contains('기다리고')));
      }
    }
  });

  test('모든 말투·주제를 조합해도 템플릿이나 잘못된 어미가 남지 않는다', () {
    for (final style in ['반말', '해요체', '~지요!', '느긋하게']) {
      for (final topic in TalkTopic.values) {
        for (var choice = 0; choice < 3; choice++) {
          final talk = FriendTalk(friend(style), random: _Pick(choice));
          final text = talk.say(topic, thing: '밤');
          expect(text, isNot(contains('{')), reason: '$style $topic');
          expect(text, isNot(matches(RegExp(r'밤예요|밤라니|도토리다|기뻐지요|[!?]{2}$'))));
        }
      }
    }
  });

  test('기존 민들레 소개 오타만 고치고 사용자가 쓴 소개는 유지한다', () async {
    final mindle = starterFriends().firstWhere((f) => f.id == 'mindle');
    final store = MemoryStore();
    for (final original in ['내가 민들레래!\n내가 민들레어서 행복해.', '내가 직접 지은 꽃 친구야.']) {
      await store.write('characters', {
        'friends': [mindle.copyWith(introduction: original).toJson()],
        'starters': starterFriends().map((f) => f.id).toList(),
      });
      final repo = InMemoryCharacterRepository(store: store);
      final restored = (await repo.fetchFriends()).single;
      expect(
        restored.introduction,
        original.contains('민들레어서') ? mindle.introduction : original,
      );
    }
  });
}
