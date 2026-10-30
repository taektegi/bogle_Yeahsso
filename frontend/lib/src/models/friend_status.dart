/// How a friend is doing inside its house. Care is gentle: values drift
/// down slowly while you are away but never below [floor], and nothing is
/// ever lost for neglect (Tamagotchi-style attachment without punishment).
class FriendStatus {
  const FriendStatus({
    this.mood = 80,
    this.fullness = 70,
    this.energy = 75,
    this.closeness = 40,
    this.asleep = false,
    required this.updatedAt,
  });

  static const floor = 25;

  /// 기분, 배부름, 기운, 친밀도 — all 0..100.
  final int mood;
  final int fullness;
  final int energy;
  final int closeness;
  final bool asleep;
  final DateTime updatedAt;

  FriendStatus copyWith({
    int? mood,
    int? fullness,
    int? energy,
    int? closeness,
    bool? asleep,
    DateTime? updatedAt,
  }) => FriendStatus(
    mood: _clamp(mood ?? this.mood),
    fullness: _clamp(fullness ?? this.fullness),
    energy: _clamp(energy ?? this.energy),
    closeness: _clamp(closeness ?? this.closeness),
    asleep: asleep ?? this.asleep,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// Time passing while the child is away: a little hungrier and sleepier,
  /// or rested if the friend was put to bed.
  FriendStatus aged(DateTime now) {
    final hours = now.difference(updatedAt).inMinutes / 60;
    if (hours < 0.25) return this;
    int down(int v, double perHour) =>
        (v - perHour * hours).round().clamp(floor, 100);
    return copyWith(
      fullness: down(fullness, 4),
      mood: down(mood, 2),
      energy: asleep
          ? (energy + 15 * hours).round().clamp(0, 100)
          : down(energy, 3),
      updatedAt: now,
    );
  }

  static int _clamp(int v) => v.clamp(0, 100);

  Map<String, Object?> toJson() => {
    'mood': mood,
    'fullness': fullness,
    'energy': energy,
    'closeness': closeness,
    'asleep': asleep,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory FriendStatus.fromJson(Map<String, Object?> json) => FriendStatus(
    mood: (json['mood'] as num?)?.toInt() ?? 80,
    fullness: (json['fullness'] as num?)?.toInt() ?? 70,
    energy: (json['energy'] as num?)?.toInt() ?? 75,
    closeness: (json['closeness'] as num?)?.toInt() ?? 40,
    asleep: json['asleep'] as bool? ?? false,
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
  );
}
