import 'local_store.dart';

/// The child's profile (`GET`/`PATCH /v1/me` on the service).
class UserProfile {
  const UserProfile({
    this.nickname = defaultNickname,
    this.avatar = defaultAvatar,
    this.bio = '',
    this.interests = const [],
    this.profileColor = 'blue',
    this.friendNotifications = true,
    this.orderNotifications = true,
  });

  /// What a new account is called until the child picks a name (the
  /// service gives new profiles the same one).
  static const defaultNickname = '그린고블린';
  static const defaultAvatar = 'assets/figma/character_card.svg';

  final String nickname;

  /// A friend's artwork (svg/png). Real photos of children are avoided.
  final String avatar;
  static const interestChoices = [
    '그림 그리기',
    '사진 찍기',
    '이야기 나누기',
    '친구 돌보기',
    '상상 놀이',
    '인형 꾸미기',
  ];
  static const colorChoices = ['blue', 'mint', 'pink', 'yellow'];
  final String bio;
  final List<String> interests;
  final String profileColor;
  final bool friendNotifications;
  final bool orderNotifications;

  UserProfile copyWith({
    String? nickname,
    String? avatar,
    String? bio,
    List<String>? interests,
    String? profileColor,
    bool? friendNotifications,
    bool? orderNotifications,
  }) => UserProfile(
    nickname: nickname ?? this.nickname,
    avatar: avatar ?? this.avatar,
    bio: bio ?? this.bio,
    interests: List.unmodifiable(interests ?? this.interests),
    profileColor: profileColor ?? this.profileColor,
    friendNotifications: friendNotifications ?? this.friendNotifications,
    orderNotifications: orderNotifications ?? this.orderNotifications,
  );

  Map<String, Object?> toJson() => {
    'nickname': nickname,
    'avatar': avatar,
    'bio': bio,
    'interests': interests,
    'profileColor': profileColor,
    'friendNotifications': friendNotifications,
    'orderNotifications': orderNotifications,
  };

  factory UserProfile.fromJson(Map<String, Object?> json) => UserProfile(
    nickname: json['nickname'] as String? ?? defaultNickname,
    avatar: json['avatar'] as String? ?? defaultAvatar,
    bio: json['bio'] as String? ?? '',
    interests: List.unmodifiable(
      (json['interests'] as List? ?? const [])
          .whereType<String>()
          .where(interestChoices.contains)
          .take(3),
    ),
    profileColor: colorChoices.contains(json['profileColor'])
        ? json['profileColor'] as String
        : 'blue',
    friendNotifications: json['friendNotifications'] as bool? ?? true,
    orderNotifications: json['orderNotifications'] as bool? ?? true,
  );
}

abstract interface class ProfileRepository {
  Future<UserProfile> fetchProfile();

  /// Saves and returns the profile as stored.
  Future<UserProfile> saveProfile(UserProfile profile);
}

/// The profile kept on the device: for this session, or with a [store]
/// across launches.
class InMemoryProfileRepository implements ProfileRepository {
  InMemoryProfileRepository({
    UserProfile profile = const UserProfile(),
    LocalStore? store,
  }) : _profile = profile,
       _store = store;
  UserProfile _profile;
  final LocalStore? _store;
  static const _name = 'profile';

  Future<void>? _restoring;
  Future<void> get _ready =>
      _restoring ??= _restore().catchError((Object error, StackTrace stack) {
        _restoring = null;
        Error.throwWithStackTrace(error, stack);
      });

  Future<void> _restore() async {
    final profile = await readDocument(
      _store,
      _name,
      (value) => UserProfile.fromJson((value as Map).cast()),
    );
    if (profile != null) _profile = profile;
  }

  @override
  Future<UserProfile> fetchProfile() async {
    await _ready;
    return _profile;
  }

  @override
  Future<UserProfile> saveProfile(UserProfile profile) async {
    await _ready;
    await _store?.write(_name, profile.toJson());
    _profile = profile;
    return profile;
  }
}
