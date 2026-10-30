import 'package:bogle_app/src/data/friend_profile_choices.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every answer is one the character service takes', () {
    // bogle_backend_try app/friend_settings.py: FAVORITE_THINGS and the
    // speech styles; personality is free text of 1–30 letters.
    expect(
      [for (final f in favoriteChoices) f.value],
      ['사과', '친구랑 놀기', '산책', '구름', '낮잠', '그림', '노래', '바다'],
    );
    expect(speechChoices, hasLength(11));
    expect(speechChoices.map((s) => s.value).toSet(), hasLength(11));
    expect(speechChoiceOf('robot_polite')!.label, '로봇 친구처럼 · 공손한 말');
    expect(personalityChoices, hasLength(4));
    for (final p in personalityChoices) {
      expect(p.characters.length, inInclusiveRange(1, 30));
    }
  });

  test('the 말투 samples say the same thing, only the ending differs', () {
    for (final s in speechChoices.take(3)) {
      expect(s.sample, startsWith('오늘은 뭐 하고 놀'));
    }
    expect(speechChoiceOf('해요체')!.label, '공손하고 부드럽게');
    expect(speechChoiceOf('씩씩하게'), isNull);
  });

  test('the introduction follows what was chosen', () {
    final cloud = favoriteChoices[3], drawing = favoriteChoices[5];
    expect(
      introductionFor('엉뚱한 상상가', [cloud, drawing]),
      '구름 구경과 그림 그리기를 좋아하는 엉뚱한 상상가예요.',
    );
    // Particles follow the last word: 낮잠을, 사과와.
    final apple = favoriteChoices[0], nap = favoriteChoices[4];
    expect(introductionFor('호기심 많은 탐험가', [nap]), '포근한 낮잠을 좋아하는 호기심 많은 탐험가예요.');
    expect(
      introductionFor('호기심 많은 탐험가', [apple, nap]),
      startsWith('아삭한 사과와 포근한 낮잠을'),
    );
  });

  test('every introduction fits what the service keeps', () {
    for (final p in personalityChoices) {
      for (final a in favoriteChoices) {
        for (final b in favoriteChoices) {
          final chosen = a == b ? [a] : [a, b];
          // UpdateFriendIn.introduction: at most 70.
          expect(introductionFor(p, chosen).length, lessThanOrEqualTo(70));
        }
      }
    }
  });
}
