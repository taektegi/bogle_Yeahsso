import 'dart:io';

import 'package:flutter/painting.dart';

import '../models/character_friend.dart';

/// What a friend sees out of its window (Figma 568:2335 / 568:2533): a
/// picture behind the arched window frame. New server views use one day
/// picture, with night colour applied by the room. Old day/night assets remain
/// supported; until a view is ready, the bundled scenery shows.
///
/// [day] and [night] are asset paths or http(s) URLs.
class WindowView {
  const WindowView({required this.day, this.night});

  final String day;

  /// The same place at night; without one, [day] is dimmed instead.
  final String? night;

  /// Figma's own view: the aquarium, and the same water at night.
  static const aquarium = WindowView(
    day: 'assets/figma/house_view_aquarium_day.png',
    night: 'assets/figma/house_view_aquarium_night.png',
  );

  /// Preserve server-provided scenery. Bundled friends have individual views
  /// even on devices whose saved character predates these assets.
  static WindowView forFriend(CharacterFriend friend) =>
      friend.view ??
      switch (friend.id) {
        'dduchi' => const WindowView(
          day: 'assets/figma/house_view_dduchi_day.png',
        ),
        'nemorin' => const WindowView(
          day: 'assets/figma/house_view_nemorin_day.png',
        ),
        'ppojik' => const WindowView(
          day: 'assets/figma/house_view_ppojik_day.png',
        ),
        'mindle' => const WindowView(
          day: 'assets/figma/house_view_mindle_day.png',
        ),
        'gyuri' => const WindowView(
          day: 'assets/figma/house_view_gyuri_day.png',
        ),
        _ => aquarium,
      };

  /// The picture to show; null [night] falls back to [day].
  String pick({required bool night}) => night ? (this.night ?? day) : day;

  static ImageProvider image(String source) =>
      source.startsWith('http://') || source.startsWith('https://')
      ? NetworkImage(source)
      : source.startsWith('/') || source.startsWith('file://')
      ? FileImage(
          File(
            source.startsWith('file://')
                ? Uri.parse(source).toFilePath()
                : source,
          ),
        )
      : AssetImage(source) as ImageProvider;

  Map<String, Object?> toJson() => {'day': day, 'night': night};

  factory WindowView.fromJson(Map<String, Object?> json) =>
      WindowView(day: json['day']! as String, night: json['night'] as String?);

  @override
  bool operator ==(Object other) =>
      other is WindowView && other.day == day && other.night == night;

  @override
  int get hashCode => Object.hash(day, night);
}

/// The window pane on the 1194 × 834 Figma frame: 1010 × 289 pt, arched at
/// the top. Pictures are cropped to it (BoxFit.cover), so they are asked
/// for at its shape.
abstract final class WindowPane {
  static const size = Size(1010, 289);

  /// Width ÷ height, about 3.5 : 1.
  static double get aspect => size.width / size.height;

  /// What to ask an image model for: 2× the pane, rounded to the 64 px
  /// steps most models want.
  static const request = Size(2048, 576);
}

/// The request for one friend's window view, built only from what the
/// child chose (personality chip, favourite things, introduction), never
/// the child's own name or anything personal.
///
/// Not sent anywhere yet: it is the specification for the window-view
/// generation the character service will do. When the service takes it
/// over, the prompt moves there (as the character art prompt did) and this
/// class goes.
class WindowViewPrompt {
  const WindowViewPrompt({
    required this.prompt,
    required this.negativePrompt,
    required this.night,
  });

  final String prompt;
  final String negativePrompt;
  final bool night;

  Size get size => WindowPane.request;

  /// The day picture. The night one should be made from it (an image edit
  /// with the day picture as input) so the two show the same place.
  factory WindowViewPrompt.day(CharacterFriend friend) =>
      WindowViewPrompt._(friend, night: false);

  factory WindowViewPrompt.night(CharacterFriend friend) =>
      WindowViewPrompt._(friend, night: true);

  factory WindowViewPrompt._(CharacterFriend friend, {required bool night}) {
    final place = placeOf(friend);
    final mood = moodOf(friend.personality);
    final things = [
      for (final thing in friend.favoriteThings.take(3)) propOf(thing),
    ];
    final light = night
        ? 'The same place at night: deep teal and navy blues, a soft moon '
              'and a few twinkling stars, everything resting and quiet, no '
              'animals moving about.'
        : 'Daytime: a soft pastel gradient sky from pale cream-yellow at the '
              'top to bright aqua and sky blue, bright and cheerful.';
    final prompt = [
      'The view outside a child\'s bedroom window, seen straight on, for a '
          'children\'s picture-book app.',
      'Scene: $place.',
      if (things.isNotEmpty)
        'Small details placed naturally in the scene: ${things.join(', ')}.',
      'Mood: $mood.',
      light,
      'Style: flat 2D vector illustration like a kids\' picture book; '
          'simple rounded shapes, no outlines, smooth gradients, saturated '
          'pastel colours with a cream-yellow, aqua and soft blue palette '
          '(main accent #8BA2FF); gentle, friendly and calm.',
      'Composition: a very wide panorama, about 3.5 : 1. Keep the sky and '
          'the top corners plain (an arch covers them). Put the main shapes '
          'in the lower two-thirds and between 20% and 80% of the width; '
          'leave the very centre and a band 38% up from the bottom free of '
          'anything important (window bars cross there). The ground or sea '
          'floor runs along the bottom edge.',
      'Fill the whole image edge to edge, with no frame.',
    ].join(' ');
    return WindowViewPrompt(
      prompt: prompt,
      negativePrompt: _avoid,
      night: night,
    );
  }

  static const _avoid =
      'text, letters, numbers, logo, watermark, signature, people, faces, '
      'characters, mascots, animals in the foreground, window frame, window '
      'bars, curtains, border, vignette, photograph, photorealistic, 3D '
      'render, harsh shadows, dark or scary themes, clutter';

  /// Where the friend lives, from its introduction ("난 바다에 사는
  /// 해파리야") and favourite things.
  static String placeOf(CharacterFriend friend) {
    final about = '${friend.introduction} ${friend.favoriteThings.join(' ')}';
    for (final (words, place) in _places) {
      if (words.any(about.contains)) return place;
    }
    return 'a sunny meadow with soft rolling hills, round trees and flowers';
  }

  static const _places = [
    (
      ['바다', '심해', '물고기', '해파리', '수족관', '파도'],
      'under the sea: swaying green seaweed, rising bubbles, little fish, '
          'starfish on the sandy floor',
    ),
    (
      ['숲', '나무', '도토리', '버섯'],
      'a cosy forest: round trees, mushrooms, ferns and a winding path',
    ),
    (
      ['구름', '하늘', '날개', '새'],
      'high up in the sky above fluffy clouds, with a faraway rainbow',
    ),
    (
      ['우주', '별', '행성', '로켓'],
      'outer space: round pastel planets, a crescent moon and soft stars',
    ),
    (
      ['눈', '얼음', '겨울', '펭귄'],
      'a snowy land with soft snow hills, icicles and pine trees',
    ),
    (['사막', '선인장', '모래'], 'a warm desert with round dunes and cheerful cacti'),
    (
      ['네모', '기린', '높은'],
      'a savanna of tall trees under a wide sky, seen from up high',
    ),
    (
      ['꽃', '정원', '나비'],
      'a flower garden full of big round blossoms and butterflies',
    ),
  ];

  /// The personality chip as a feeling for the picture.
  static String moodOf(String personality) {
    for (final (words, mood) in _moods) {
      if (words.any(personality.contains)) return mood;
    }
    return 'warm, cosy and gentle';
  }

  static const _moods = [
    (['활발', '호기심'], 'bright, playful and full of little discoveries'),
    (['조용', '용감'], 'calm and peaceful, with a quiet sense of adventure'),
    (['다정', '웃'], 'warm, cosy and smiling'),
    (['엉뚱', '상상', '신비'], 'whimsical and dreamy, a little magical'),
    (['똑똑', '정의'], 'clear, tidy and bright'),
  ];

  /// A favourite thing as something to see; ones not listed go in as the
  /// child wrote them.
  static String propOf(String thing) {
    for (final (words, prop) in _props) {
      if (words.any(thing.contains)) return prop;
    }
    return 'something inspired by "$thing"';
  }

  static const _props = [
    (['사과'], 'a small apple tree with red apples'),
    (['딸기'], 'little strawberries'),
    (['구름'], 'fluffy white clouds'),
    (['도토리'], 'acorns'),
    (['산책'], 'a winding little path'),
    (['색연필', '그림', '크레파스'], 'rainbow colours like crayon strokes'),
    (['친구', '놀'], 'a bright ball and a swing'),
    (['높은'], 'a tall lookout hill'),
    (['별'], 'twinkling stars'),
    (['꽃'], 'round flowers'),
    (['물고기', '바다'], 'little fish'),
  ];
}
