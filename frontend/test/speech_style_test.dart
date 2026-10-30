import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:bogle_app/src/models/character_friend.dart';

import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/friend_talk.dart';
import 'package:bogle_app/src/data/speech_catalog.dart';
import 'package:bogle_app/src/data/speech_style.dart';
import 'package:bogle_app/src/widgets/speech_style_picker.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('검수 원본과 앱의 말투 사전이 같고 8가지가 각각 다른 문장을 사용한다', () async {
    expect(
      speechCatalog,
      jsonDecode(File('lib/src/data/speech_catalog.json').readAsStringSync()),
    );
    final friend = (await InMemoryCharacterRepository().fetchFriends()).first;
    final samples = <String>{};
    for (final manner in SpeechManner.values) {
      for (final polite in [false, true]) {
        final profile = SpeechProfile(manner, polite: polite);
        expect(SpeechProfile.tryParse(profile.value)!.label, profile.label);
        samples.add(profile.preview(SpeechSample.play));
        expect(profile.introduction('밤'), isNot(contains('밤예요')));
        final talk = FriendTalk(
          friend.copyWith(speechStyle: profile.value),
          random: Random(5),
        );
        for (final topic in TalkTopic.values) {
          for (final thing in ['밤', '사과', '딸기']) {
            final line = talk.say(topic, thing: thing);
            expect(line, isNotEmpty);
            expect(line, isNot(contains('{')));
            expect(line, isNot(contains('밤예요')));
          }
        }
        final care = talk.careReply('다쳤어')!;
        expect(care, contains('선생님'));
        expect(care, isNot(matches('야호|오류|준비 완료')));
      }
    }
    expect(samples, hasLength(8));
    for (final old in ['반말', '해요체', '~지요!', '느긋한 말투']) {
      expect(SpeechProfile.tryParse(old), isNull);
      expect(
        FriendTalk(friend.copyWith(speechStyle: old)).say(TalkTopic.play),
        isNotEmpty,
      );
    }
  });

  test('모든 현재·기존 말투의 터치 문구는 한 바퀴 전까지 반복하지 않는다', () async {
    final friend = (await InMemoryCharacterRepository().fetchFriends()).first;
    final styles = [
      for (final manner in SpeechManner.values)
        for (final polite in [false, true])
          SpeechProfile(manner, polite: polite).value,
      '반말',
      '해요체',
      '~지요!',
      '느긋한 말투',
    ];
    for (final style in styles) {
      final profile = SpeechProfile.tryParse(style);
      final count = profile?.lines('pet').length ?? 17;
      expect(count, greaterThanOrEqualTo(16));
      final character = CharacterFriend.fromJson({
        ...friend.toJson(),
        'id': 'cycle-$style',
        'speechStyle': style,
      });
      final random = Random(14);
      String? previous;
      for (var cycle = 0; cycle < 4; cycle++) {
        final seen = <String>{};
        for (var i = 0; i < count; i++) {
          // Visitors create a new talk object on each touch.
          final text = FriendTalk(character, random: random).say(TalkTopic.pet);
          expect(text, isNot(previous), reason: '$style cycle $cycle');
          expect(seen.add(text), isTrue, reason: '$style repeats within cycle');
          expect(text, isNot(contains('{')));
          previous = text;
        }
      }
    }
  });

  test('말투별 터치 반응은 어미만 바꾼 공통 문장 목록이 아니다', () {
    final pools = [
      for (final manner in SpeechManner.values)
        SpeechProfile(manner).lines('pet').toSet(),
    ];
    for (var a = 0; a < pools.length; a++) {
      expect(pools[a].length, greaterThanOrEqualTo(16));
      for (var b = a + 1; b < pools.length; b++) {
        expect(pools[a].intersection(pools[b]), isEmpty);
      }
    }
  });

  testWidgets('느낌과 말끝을 빠르게 골라도 조합이 유지되고 기존 값은 저절로 바뀌지 않는다', (tester) async {
    String? value = '~지요!';
    final changes = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBogleTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: StatefulBuilder(
                builder: (context, update) => SpeechStylePicker(
                  value: value,
                  onChanged: (v) {
                    changes.add(v);
                    update(() => value = v);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(changes, isEmpty);
    await tester.tap(find.text('편한 말'));
    expect(changes, isEmpty);
    await tester.tap(find.byKey(const ValueKey('speech-manner-robot')));
    await tester.tap(find.text('공손한 말'));
    await tester.pumpAndSettle();
    expect(value, 'robot_polite');
    await tester.tap(find.byKey(const ValueKey('speech-manner-story')));
    await tester.tap(find.text('편한 말'));
    await tester.pumpAndSettle();
    expect(value, 'story_casual');
    expect(tester.takeException(), isNull);
  });
}
