import 'korean.dart';
import 'speech_style.dart';

/// The answers a child picks from when setting up a new friend
/// (docs: 캐릭터 설정 객관식 구성안): one personality, one or two
/// favourite things and one 말투, each a short name. What is stored is
/// what the character service already takes: favourite things and 말투
/// are its fixed values, and personality is free text.
const personalityChoices = ['호기심 많은 탐험가', '차분하고 든든한 친구', '다정한 응원가', '엉뚱한 상상가'];

class FavoriteChoice {
  const FavoriteChoice({
    required this.label,
    required this.value,
    required this.thing,
  });

  /// "아삭한 사과", on its card.
  final String label;

  /// "사과": what the service takes.
  final String value;

  /// "아삭한 사과", as a noun in a sentence ("…를 좋아해").
  final String thing;
}

const favoriteChoices = [
  FavoriteChoice(label: '아삭한 사과', value: '사과', thing: '아삭한 사과'),
  FavoriteChoice(label: '친구와 놀기', value: '친구랑 놀기', thing: '친구와 놀기'),
  FavoriteChoice(label: '산책하기', value: '산책', thing: '산책하기'),
  FavoriteChoice(label: '구름 구경하기', value: '구름', thing: '구름 구경'),
  FavoriteChoice(label: '포근한 낮잠', value: '낮잠', thing: '포근한 낮잠'),
  FavoriteChoice(label: '그림 그리기', value: '그림', thing: '그림 그리기'),
  FavoriteChoice(label: '노래 부르기', value: '노래', thing: '노래 부르기'),
  FavoriteChoice(label: '바다 구경하기', value: '바다', thing: '바다 구경'),
];

/// At most this many favourite things, so the friend's taste stays clear.
const maxFavorites = 2;

class SpeechChoice {
  const SpeechChoice({
    required this.value,
    required this.label,
    required this.sample,
  });

  /// 기존 한국어 값 또는 새 느낌·높임 조합의 서버 저장 값.
  final String value;
  final String label;

  /// 같은 상황을 문장 길이·리듬·어휘·말끝으로 구분한 비교 예문.
  final String sample;
}

final speechChoices = <SpeechChoice>[
  SpeechChoice(value: '반말', label: '친구처럼 편하게', sample: '오늘은 뭐 하고 놀까?'),
  SpeechChoice(value: '해요체', label: '공손하고 부드럽게', sample: '오늘은 뭐 하고 놀까요?'),
  SpeechChoice(value: '~지요!', label: '동화 속 친구처럼', sample: '오늘은 뭐 하고 놀지요?'),
  for (final manner in SpeechManner.values)
    for (final polite in [false, true])
      SpeechChoice(
        value: SpeechProfile(manner, polite: polite).value,
        label: SpeechProfile(manner, polite: polite).label,
        sample: SpeechProfile(
          manner,
          polite: polite,
        ).preview(SpeechSample.play),
      ),
];

/// The 말투 named [value], or null for one not on the list.
SpeechChoice? speechChoiceOf(String value) {
  for (final choice in speechChoices) {
    if (choice.value == value) return choice;
  }
  return null;
}

/// "구름 구경과 그림 그리기": one or two things, joined.
String _things(List<FavoriteChoice> favorites) => favorites.length < 2
    ? favorites.first.thing
    : '${particle(favorites[0].thing, '과', '와')} ${favorites[1].thing}';

/// The friend's introduction from what was chosen: "구름 구경과 그림
/// 그리기를 좋아하는 엉뚱한 상상가예요."
String introductionFor(String personality, List<FavoriteChoice> favorites) =>
    '${particle(_things(favorites), '을', '를')} 좋아하는 '
    '$personality${hasBatchim(personality) ? '이에요' : '예요'}.';
