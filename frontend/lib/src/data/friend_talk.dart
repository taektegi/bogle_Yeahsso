import 'dart:math' as math;

import '../models/character_friend.dart';
import 'korean.dart';
import 'speech_style.dart';
import '../util/art_cache.dart';

enum TalkTopic {
  greet,
  today,
  likes,
  play,
  love,
  snack,
  hungry,
  sleep,
  wake,
  pet,
  asleep,

  /// Given its favourite snack; `{f}` is the snack.
  treat,

  /// A friend it invited has just hopped in; `{f}` is the guest.
  welcome,

  /// A visitor thanking the host for the invitation.
  visit,

  /// Seeing the guest off; `{f}` is the guest.
  bye,
  other,
}

/// Quick replies a child can tap instead of typing.
const quickTalks = [
  (TalkTopic.today, '오늘 뭐 했어?'),
  (TalkTopic.likes, '뭘 좋아해?'),
  (TalkTopic.play, '같이 놀자!'),
  (TalkTopic.love, '사랑해!'),
];

/// Frontend preview: scripted lines shaped by the friend's 말투 and favorite
/// things. A generation service can replace this behind the same call.
class FriendTalk {
  FriendTalk(this.friend, {math.Random? random})
    : _random = random ?? math.Random();
  final CharacterFriend friend;
  final math.Random _random;

  // Shared per character so visitors and re-entered rooms keep their turn.
  // Bounded, session-only history; it never changes the saved character.
  static final _petTurns = ArtCache<(String, String), _DialogueTurn>(128);

  int _pick(TalkTopic topic, int length) {
    if (topic != TalkTopic.pet) return _random.nextInt(length);
    final key = (friend.id, friend.speechStyle);
    final turn = _petTurns[key] ??= _DialogueTurn();
    return turn.next(length, _random);
  }

  String get _favorite {
    final things = friend.favoriteThings
        .map((f) => f.trim())
        .where((f) => f.isNotEmpty)
        .toList();
    return things.isEmpty ? '반짝이는 것' : things[_random.nextInt(things.length)];
  }

  // 서버가 없거나 끊겼을 때도 위험·고통 신호에는 일반 놀이 대사를 쓰지 않는다.
  static final _worrying = RegExp(
    r'아파(?!트)|아프다|아픈데|다쳤|다쳐|(?:한테|에게)맞(?:았|아서|고)|때렸|때려|'
    r'죽고싶|죽을래|자살|살기싫|괴롭혀|괴롭힘|피가나|혼자있어|무서워서',
  );

  String? careReply(String text) {
    if (!_worrying.hasMatch(text.replaceAll(RegExp(r'\s+'), ''))) return null;
    return switch (register) {
      Register.casual => '그랬구나, 많이 힘들었겠다. 엄마 아빠나 선생님께 꼭 말해 줘. 나는 언제나 네 편이야.',
      Register.polite =>
        '그랬군요, 많이 힘들었겠어요. 엄마 아빠나 선생님께 꼭 말해 주세요. 저는 언제나 친구 편이에요.',
      Register.jiyo => '많이 힘들었겠어요. 엄마 아빠나 선생님께 꼭 말해 주세요. 저는 언제나 친구 편이지요.',
    };
  }

  TalkTopic topicFor(String text) {
    bool has(List<String> words) => words.any(text.contains);
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    if (RegExp(r'(?:너|널|너를)좋아해|네가좋아(?:요)?(?:[!?.~…]|$)').hasMatch(compact)) {
      return TalkTopic.love;
    }
    if (has(['안녕', '하이', '반가'])) return TalkTopic.greet;
    if (has(['오늘', '뭐 했', '뭐했'])) return TalkTopic.today;
    if (has(['좋아하', '좋아해', '취미'])) return TalkTopic.likes;
    if (has(['놀자', '놀아', '게임', '숨바꼭질'])) return TalkTopic.play;
    if (has(['사랑', '좋아!', '최고', '예뻐', '귀여워'])) return TalkTopic.love;
    if (has(['배고', '먹', '간식'])) return TalkTopic.hungry;
    if (has(['졸려', '자자', '잘자', '잘 자'])) return TalkTopic.sleep;
    return TalkTopic.other;
  }

  /// Each line is written out in every register instead of gluing an
  /// ending on, so "~지요" reads naturally (기쁘지요, not 기뻐지요).
  /// `{f}` is a favorite thing.
  static const _lines = <TalkTopic, List<_Line>>{
    TalkTopic.greet: [
      (
        '안녕! 우리 집에 와 줘서 기뻐',
        '안녕하세요! 우리 집에 와 줘서 기뻐요',
        '안녕하세요! 우리 집에 와 주니 정말 기쁘지요',
      ),
      ('또 만났다! 기다리고 있었어', '또 만났네요! 기다리고 있었어요', '또 만났지요! 계속 기다리고 있었지요'),
    ],
    TalkTopic.today: [
      ('오늘은 창밖 구름을 세었어', '오늘은 창밖 구름을 세었어요', '오늘은 창밖 구름을 하나하나 세었지요'),
      (
        '좋아하는 것들을 떠올리며 방을 정리했어',
        '좋아하는 것들을 떠올리며 방을 정리했어요',
        '좋아하는 것들을 떠올리며 방을 정리했지요',
      ),
    ],
    TalkTopic.likes: [
      ('{f:이/가} 제일 좋아', '{f:이/가} 제일 좋아요', '{f:이/가} 제일 좋지요'),
      ('{f:을/를} 생각하면 신나', '{f:을/를} 생각하면 신나요', '{f:을/를} 생각하면 신나지요'),
    ],
    TalkTopic.play: [
      (
        '좋아! 숨바꼭질을 하자! 내가 먼저 숨을게',
        '좋아요! 숨바꼭질을 해요! 제가 먼저 숨을게요',
        '좋지요! 숨바꼭질이라면 내가 먼저 숨지요',
      ),
      ('빙글빙글 춤추기 놀이 어때?', '빙글빙글 춤추기 놀이 어때요?', '빙글빙글 춤추기 놀이가 딱이지요'),
    ],
    TalkTopic.love: [
      ('나도 네가 정말 좋아', '함께 있으면 저도 정말 행복해요', '나도 네가 정말 좋지요'),
      ('헤헤, 마음이 몽글몽글해졌어', '헤헤, 마음이 몽글몽글해졌어요', '헤헤, 마음이 몽글몽글해졌지요'),
    ],
    TalkTopic.snack: [
      ('냠냠! 너무 맛있어', '냠냠! 너무 맛있어요', '냠냠! 정말 맛있지요'),
      ('배가 든든해졌어, 고마워', '배가 든든해졌어요, 고마워요', '고마워요, 배가 든든해졌지요'),
    ],
    TalkTopic.hungry: [
      ('간식이 생각나네. 같이 먹을까?', '간식이 생각나요. 같이 먹을까요?', '간식을 함께 먹으면 더 맛있지요'),
      ('어떤 간식을 좋아해?', '어떤 간식을 좋아해요?', '어떤 간식을 좋아하는지 궁금하지요'),
    ],
    TalkTopic.treat: [
      (
        '우와, {f}! 내가 제일 좋아하는 거야',
        '우와, {f}! 제가 제일 좋아하는 거예요',
        '우와, {f}! 제일 좋아하는 거지요',
      ),
      (
        '{f:이야/야}! 어떻게 알았어?',
        '{f:이에요/예요}! 어떻게 알았어요?',
        '{f:이라니/라니}, 제가 좋아하는 걸 잘 알지요',
      ),
    ],
    TalkTopic.welcome: [
      ('어서 와, {f}! 같이 놀자', '어서 와요, {f}! 같이 놀아요', '어서 와요, {f}! 같이 놀면 즐겁지요'),
      ('{f}, 놀러 와 줘서 고마워', '{f}, 놀러 와 줘서 고마워요', '{f}, 놀러 와 줘서 정말 고맙지요'),
    ],
    TalkTopic.visit: [
      ('초대해 줘서 고마워! 같이 놀자', '초대해 줘서 고마워요! 같이 놀아요', '초대해 주니 고맙지요! 같이 놀아요'),
      ('놀러 왔어! 오늘도 신나게 놀자', '놀러 왔어요! 오늘도 즐겁게 놀아요', '놀러 왔지요! 같이 놀면 즐겁겠지요'),
    ],
    TalkTopic.bye: [
      ('{f}, 잘 가! 또 놀러 와', '{f}, 잘 가요! 또 놀러 와요', '{f}, 오늘 정말 즐거웠지요'),
      ('{f}, 내일 또 만나', '{f}, 내일 또 만나요', '{f}, 내일 또 만나지요'),
    ],
    TalkTopic.sleep: [
      ('잘 자… 좋은 꿈 꿀게', '잘 자요… 좋은 꿈 꿀게요', '이제 잘 시간이지요… 좋은 꿈 꿀게요'),
      ('포근하다… 쿨쿨…', '포근해요… 쿨쿨…', '포근하지요… 쿨쿨…'),
    ],
    TalkTopic.wake: [
      ('잘 잤다! 기운이 번쩍 났어', '잘 잤어요! 기운이 번쩍 났어요', '푹 잤지요! 기운이 번쩍 났지요'),
      ('좋은 아침! 다시 놀 수 있어', '좋은 아침이에요! 다시 놀 수 있어요', '좋은 아침이지요! 이제 다시 놀 수 있지요'),
    ],
    TalkTopic.pet: [
      ('간지러워', '간지러워요', '간지럽지요'),
      ('헤헤, 또 쓰다듬어 줘', '헤헤, 또 쓰다듬어 주세요', '헤헤, 쓰다듬어 주니 좋지요'),
      ('기분 좋아', '기분 좋아요', '기분이 참 좋지요'),
      ('손이 따뜻해', '손이 따뜻해요', '손이 참 따뜻하지요'),
      ('마음이 편안해졌어', '마음이 편안해졌어요', '마음이 편안해졌지요'),
      ('나도 토닥토닥 해 줄게', '저도 토닥토닥 해 드릴게요', '나도 토닥토닥 해 주고 싶지요'),
      ('잠깐 곁에서 쉬어 갈래?', '잠깐 곁에서 쉬어 갈래요?', '곁에서 쉬면 더 포근하지요'),
      ('반가워서 웃음이 났어', '반가워서 웃음이 났어요', '반가워서 웃음이 나지요'),
      ('네 손이 오니까 금방 알아봤어', '손이 다가오니까 금방 알아봤어요', '반가운 손길은 금방 알아보지요'),
      ('같이 있으니 포근하다', '같이 있으니 포근해요', '같이 있으니 참 포근하지요'),
      ('조금 가까이 와도 돼', '조금 가까이 와도 돼요', '조금 가까이 와도 괜찮지요'),
      ('우리 고개를 같이 흔들어 볼까?', '우리 고개를 같이 흔들어 볼까요?', '고개를 같이 흔들면 재미있겠지요'),
      ('간지러워서 가만히 못 있겠어', '간지러워서 가만히 못 있겠어요', '간지러우면 웃음이 나지요'),
      ('오늘도 만나서 좋아', '오늘도 만나서 좋아요', '오늘도 만나니 반갑지요'),
      ('작게 인사할게, 안녕', '작게 인사할게요, 안녕하세요', '작은 인사도 반갑지요'),
      ('네 곁에 앉아 있을래', '곁에 앉아 있을게요', '곁에 앉아 있으면 좋겠지요'),
      ('이렇게 놀아도 재미있네', '이렇게 놀아도 재미있네요', '이렇게 놀아도 재미있지요'),
    ],
    TalkTopic.other: [
      ('우와, 그런 생각을 했구나', '우와, 그런 생각을 했군요', '우와, 멋진 생각이지요'),
      ('그 이야기 더 해 줘', '그 이야기 더 해 주세요', '그다음 이야기도 궁금하지요'),
      ('너랑 이야기하면 즐거워', '같이 이야기하면 즐거워요', '너랑 이야기하면 즐겁지요'),
    ],
  };

  static const _asleep = ['쿨쿨… (자고 있어요)', '음냐음냐… (아침이 되면 일어나요)'];

  /// [thing] fills `{f}` instead of a random favourite.
  String say(TalkTopic topic, {String? thing}) {
    if (topic == TalkTopic.asleep) {
      return _asleep[_random.nextInt(_asleep.length)];
    }
    final profile = SpeechProfile.tryParse(friend.speechStyle);
    if (profile != null) {
      final options = profile.lines(topic.name);
      return koreanTemplate(options[_pick(topic, options.length)], {
        'f': thing ?? _favorite,
      });
    }
    final options = _lines[topic]!;
    final line = options[_pick(topic, options.length)];
    final template = switch (register) {
      Register.casual => line.$1,
      Register.polite => line.$2,
      Register.jiyo => line.$3,
    };
    final text = koreanTemplate(template, {'f': thing ?? _favorite});
    if (RegExp(r'[.!?…。~]$').hasMatch(text)) return text;
    return '$text${friend.speechStyle.contains('느긋') ? '~' : '!'}';
  }

  /// The 말투 picked at setup: "~지요!" (동화 속 친구처럼), "해요체"
  /// (공손하고 부드럽게), "반말" (친구처럼 편하게), or a free description
  /// such as "짧고 씩씩하게".
  Register get register {
    final style = friend.speechStyle;
    final profile = SpeechProfile.tryParse(style);
    if (profile != null) {
      return profile.polite ? Register.polite : Register.casual;
    }
    if (style.contains('반말') || style.contains('해체')) return Register.casual;
    if (style.contains('지요')) return Register.jiyo;
    if (['해요', '존댓말', '존대', '공손', '정중', '다정'].any(style.contains)) {
      return Register.polite;
    }
    return Register.casual;
  }
}

typedef _Line = (String casual, String polite, String jiyo);

enum Register { casual, polite, jiyo }

/// Draw without replacement, keeping the last line out of a new cycle's
/// first draw. Removing a chosen index also works with deterministic RNGs.
class _DialogueTurn {
  final _remaining = <int>[];
  int? _last;
  int _length = 0;

  int next(int length, math.Random random) {
    if (_length != length) {
      _length = length;
      _remaining.clear();
      _last = null;
    }
    if (_remaining.isEmpty) _remaining.addAll(List.generate(length, (i) => i));
    final choices = _remaining.where((i) => length == 1 || i != _last).toList();
    final picked = choices[random.nextInt(choices.length)];
    _remaining.remove(picked);
    _last = picked;
    return picked;
  }
}
