import '../data/window_view.dart';

class CharacterFriend {
  const CharacterFriend({
    required this.id,
    required this.name,
    required this.personality,
    required this.favoriteThings,
    required this.speechStyle,
    required this.assetPath,
    required this.accentHex,
    this.level = 1,
    this.memories = 0,
    this.createdAt,
    this.introduction = '',
    this.sleep = const SleepSchedule(),
    this.view,
    this.thumbnailPath,
  });

  final String id;
  final String name;
  final String personality;

  /// Identity/story shown on the archive card, separate from temperament.
  final String introduction;
  String get displayIntroduction => introduction.trim().isNotEmpty
      ? introduction
      : '네가 그린 그림에서 태어났어.\n우리만의 이야기를 만들어 가자!';
  final List<String> favoriteThings;
  final String speechStyle;
  final String assetPath;

  /// A small copy of the picture for tiles and lists (256 px), when there
  /// is one; [thumbnail] falls back to the picture itself.
  final String? thumbnailPath;
  String get thumbnail => thumbnailPath ?? assetPath;

  final int accentHex;
  final int level;
  final int memories;
  final DateTime? createdAt;

  /// When it goes to bed and gets up; it sleeps by itself in between.
  final SleepSchedule sleep;

  /// The view out of its house's window, once one has been painted for
  /// it; until then the house shows [WindowView.aquarium].
  final WindowView? view;

  CharacterFriend copyWith({
    String? name,
    String? personality,
    String? introduction,
    List<String>? favoriteThings,
    String? speechStyle,
    int? level,
    int? memories,
    SleepSchedule? sleep,
    WindowView? view,
  }) {
    return CharacterFriend(
      id: id,
      name: name ?? this.name,
      personality: personality ?? this.personality,
      introduction: introduction ?? this.introduction,
      favoriteThings: favoriteThings ?? this.favoriteThings,
      speechStyle: speechStyle ?? this.speechStyle,
      assetPath: assetPath,
      thumbnailPath: thumbnailPath,
      accentHex: accentHex,
      level: level ?? this.level,
      memories: memories ?? this.memories,
      createdAt: createdAt,
      sleep: sleep ?? this.sleep,
      view: view ?? this.view,
    );
  }

  /// The same friend with its picture at [path] (the picture moved, not
  /// changed: [copyWith] keeps a friend's artwork as it is).
  CharacterFriend withArt(String path, {String? thumbnail}) =>
      path == assetPath && thumbnail == thumbnailPath
      ? this
      : CharacterFriend(
          id: id,
          name: name,
          personality: personality,
          introduction: introduction,
          favoriteThings: favoriteThings,
          speechStyle: speechStyle,
          assetPath: path,
          thumbnailPath: thumbnail,
          accentHex: accentHex,
          level: level,
          memories: memories,
          createdAt: createdAt,
          sleep: sleep,
          view: view,
        );

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'name': name,
    'personality': personality,
    'introduction': introduction,
    'favoriteThings': favoriteThings,
    'speechStyle': speechStyle,
    'assetPath': assetPath,
    'thumbnailPath': thumbnailPath,
    'accentHex': accentHex,
    'level': level,
    'memories': memories,
    'createdAt': createdAt?.toIso8601String(),
    'bedtime': sleep.bedtime,
    'wakeTime': sleep.wakeTime,
    'windowView': view?.toJson(),
  };

  /// Reads what [toJson] writes. Missing optional fields take their
  /// defaults, so a store can leave out what it doesn't keep.
  factory CharacterFriend.fromJson(Map<String, Object?> json) {
    const fallback = SleepSchedule();
    final created = json['createdAt'] as String?;
    final view = json['windowView'];
    return CharacterFriend(
      id: json['id']! as String,
      name: json['name']! as String,
      personality: json['personality'] as String? ?? '',
      introduction: json['introduction'] as String? ?? '',
      favoriteThings: [
        for (final thing in json['favoriteThings'] as List? ?? const [])
          thing as String,
      ],
      speechStyle: json['speechStyle'] as String? ?? '',
      assetPath: json['assetPath']! as String,
      thumbnailPath: json['thumbnailPath'] as String?,
      accentHex: (json['accentHex']! as num).toInt(),
      level: (json['level'] as num?)?.toInt() ?? 1,
      memories: (json['memories'] as num?)?.toInt() ?? 0,
      createdAt: created == null ? null : DateTime.parse(created),
      sleep: SleepSchedule(
        bedtime: (json['bedtime'] as num?)?.toInt() ?? fallback.bedtime,
        wakeTime: (json['wakeTime'] as num?)?.toInt() ?? fallback.wakeTime,
      ),
      view: view is Map ? WindowView.fromJson(view.cast()) : null,
    );
  }
}

/// Whether a friend's artwork is a drawing photographed on paper (shown as
/// a card) rather than cut-out art on a clear ground, vector or PNG, which
/// stands as it is. Photographs keep the Figma archive's `archive_` names.
bool isPhotographedArt(String assetPath) => assetPath.contains('/archive_');

/// A friend's night: it falls asleep at [bedtime] and wakes at [wakeTime],
/// both minutes after midnight. The night may run past midnight.
class SleepSchedule {
  const SleepSchedule({this.bedtime = 21 * 60, this.wakeTime = 7 * 60});

  final int bedtime;
  final int wakeTime;

  static int _minute(DateTime t) => t.hour * 60 + t.minute;

  bool asleepAt(DateTime time) {
    final m = _minute(time);
    if (bedtime == wakeTime) return false;
    return bedtime < wakeTime
        ? m >= bedtime && m < wakeTime
        : m >= bedtime || m < wakeTime;
  }

  /// The next moment after [time] when it falls asleep or wakes up.
  DateTime nextChange(DateTime time) {
    final midnight = DateTime(time.year, time.month, time.day);
    final candidates = [
      for (final day in [0, 1])
        for (final m in [bedtime, wakeTime])
          midnight.add(Duration(days: day, minutes: m)),
    ]..sort();
    return candidates.firstWhere((t) => t.isAfter(time));
  }

  @override
  bool operator ==(Object other) =>
      other is SleepSchedule &&
      other.bedtime == bedtime &&
      other.wakeTime == wakeTime;

  @override
  int get hashCode => Object.hash(bedtime, wakeTime);
}

/// "밤 9시", "아침 7시 30분": a time of day the way a child hears it.
String timeOfDayLabel(int minutes) {
  final h = minutes ~/ 60 % 24, m = minutes % 60;
  final part = switch (h) {
    < 5 => '새벽',
    < 9 => '아침',
    < 12 => '오전',
    < 18 => '오후',
    < 21 => '저녁',
    _ => '밤',
  };
  final hour = h % 12 == 0 ? 12 : h % 12;
  return m == 0 ? '$part $hour시' : '$part $hour시 $m분';
}
