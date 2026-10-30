/// Korean particles that change with the word before them: 이/가, 은/는,
/// 와/과 and 으로/로 all depend on whether its last syllable has a final
/// consonant (받침). Names and places come from children, so this is
/// worked out rather than written into each sentence.
library;

const _first = 0xAC00, _last = 0xD7A3;

/// The final consonant's index in the last syllable: 0 for none (or when
/// the word doesn't end in Hangul), 8 for ㄹ.
int _final(String word) {
  final spoken = word.trimRight();
  if (spoken.isEmpty) return 0;
  final c = spoken.runes.last;
  return c < _first || c > _last ? 0 : (c - _first) % 28;
}

/// Whether [word] ends in a final consonant (받침).
bool hasBatchim(String word) => _final(word) != 0;

/// [word] followed by [afterBatchim] or [otherwise]: `particle('뭉글이',
/// '과', '와')` is "뭉글이와".
String particle(String word, String afterBatchim, String otherwise) =>
    '$word${hasBatchim(word) ? afterBatchim : otherwise}';

/// "우리 집으로", "학교로", "서울로": 으로 after a 받침 other than ㄹ.
String toward(String place) {
  final end = _final(place);
  return '$place${end != 0 && end != 8 ? '으로' : '로'}';
}

/// 이름·취향을 문장에 넣을 때 받침에 맞는 조사·서술격 어미를 고른다.
/// 예: `{f:이/가}` → `구름이`, `{f:이에요/예요}` → `밤이에요`.
/// 입력값 자체는 다시 템플릿으로 해석하지 않는다.
String koreanTemplate(String template, Map<String, String> values) =>
    template.replaceAllMapped(
      RegExp(r'\{([a-zA-Z][a-zA-Z0-9_]*)(?::([^{}:/]+)\/([^{}:/]+))?\}'),
      (match) {
        final value = values[match[1]]?.trim();
        if (value == null) return match[0]!;
        return match[2] == null ? value : particle(value, match[2]!, match[3]!);
      },
    );
