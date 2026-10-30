import '../models/character_friend.dart';

/// The friends the app ships with. They are part of the app, not sample
/// data: every child meets them in the archive, alongside the friends they
/// make.
///
/// 고정 목업 데이터: these stay when the backend is wired in and its mock
/// data is removed, and friends the character service makes (by AI) are
/// added next to them, never in their place. Their ids are not service ids,
/// so they stay on the iPad: the app's own chat lines and motions.
///
/// A friend added here later also reaches iPads that already keep friends
/// ([starterIdsBefore]); new ones go at the end.
List<CharacterFriend> starterFriends() => [
  CharacterFriend(
    id: 'mungle',
    name: '뭉글이',
    introduction: '난 바다에 사는 해파리야.\n심해 모험을 좋아해.',
    personality: '활발하고 호기심이 많아요',
    favoriteThings: const ['사과', '구름', '친구랑 놀기'],
    speechStyle: '~지요!',
    assetPath: 'assets/figma/character_card.svg',
    accentHex: 0xFFBDCFFF,
    level: 4,
    memories: 12,
    createdAt: DateTime(2026, 9, 21),
  ),
  const CharacterFriend(
    id: 'dduchi',
    name: '뚜치',
    introduction: '뚜치 뚜치 고슴도치!\n작은 발로 숲속을 탐험해.',
    personality: '조용하지만 용감해요',
    favoriteThings: ['산책', '도토리'],
    speechStyle: '짧고 씩씩하게',
    assetPath: 'assets/figma/dduchi.png',
    accentHex: 0xFFFFB28B,
    level: 2,
    memories: 5,
  ),
  const CharacterFriend(
    id: 'nemorin',
    name: '네모린',
    introduction: '네모빔을 쏘는 기린이야.\n네모난 세상을 함께 구경하자!',
    personality: '엉뚱한 상상가예요',
    favoriteThings: ['높은 곳', '색연필'],
    speechStyle: '느긋하게',
    assetPath: 'assets/figma/nemorin.png',
    accentHex: 0xFFFCFCC9,
    level: 3,
    memories: 8,
  ),
  // Figma 819:2118, 819:2119, 820:2320 (Friends, 2026-10-26).
  const CharacterFriend(
    id: 'ppojik',
    name: '뽀직뽀직',
    introduction: '뽀직..\n난 보랏빛 별이야..',
    personality: '엉뚱한 상상가',
    favoriteThings: ['낮잠', '그림'],
    speechStyle: '반말',
    assetPath: 'assets/figma/ppojik.png',
    accentHex: 0xFFFED6FF,
    level: 2,
    memories: 4,
  ),
  const CharacterFriend(
    id: 'mindle',
    name: '민들레',
    introduction: '내가 민들레래!\n민들레여서 행복해.',
    personality: '다정한 응원가',
    favoriteThings: ['산책', '친구랑 놀기'],
    speechStyle: '반말',
    assetPath: 'assets/figma/mindle.png',
    accentHex: 0xFFB0D8A5,
    level: 3,
    memories: 6,
  ),
  const CharacterFriend(
    id: 'gyuri',
    name: '귤이',
    introduction: '난 차가운 귤이야.\n겨울에 태어났지.',
    personality: '차분하고 든든한 친구',
    favoriteThings: ['바다', '구름'],
    speechStyle: '반말',
    assetPath: 'assets/figma/gyuri.png',
    accentHex: 0xFFB8E7FF,
    level: 1,
    memories: 2,
  ),
];

/// The starters a save made before the save recorded them had already met:
/// a save without `starters` has these three, so one of them that is
/// missing was said goodbye to and stays gone.
const starterIdsBefore = ['mungle', 'dduchi', 'nemorin'];
