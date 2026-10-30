import 'package:flutter/material.dart';

import '../../data/profile_repository.dart';
import '../../models/character_friend.dart';
import '../../theme/bogle_theme.dart';
import 'profile_widgets.dart';
import '../../widgets/bogle_dialog.dart';

/// Returns the saved profile, or null when cancelled.
Future<UserProfile?> showProfileEditor(
  BuildContext context, {
  required UserProfile profile,
  required List<CharacterFriend> friends,
  required ProfileRepository repository,
}) => showDialog<UserProfile>(
  context: context,
  builder: (_) => _ProfileEditor(
    profile: profile,
    friends: friends,
    repository: repository,
  ),
);

class _ProfileEditor extends StatefulWidget {
  const _ProfileEditor({
    required this.profile,
    required this.friends,
    required this.repository,
  });
  final UserProfile profile;
  final List<CharacterFriend> friends;
  final ProfileRepository repository;
  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  late final _name = TextEditingController(text: widget.profile.nickname);
  final _form = GlobalKey<FormState>();
  late final _bio = TextEditingController(text: widget.profile.bio);
  late final _interests = {...widget.profile.interests};
  late String _color = widget.profile.profileColor;

  /// Options are friends, so two friends sharing artwork stay distinct.
  late final List<({String label, String asset})> _options = [
    for (final f in widget.friends) (label: f.name, asset: f.assetPath),
    if (!widget.friends.any((f) => f.assetPath == widget.profile.avatar))
      (label: '지금 프로필', asset: widget.profile.avatar),
  ];
  late int _selected = _options.indexWhere(
    (o) => o.asset == widget.profile.avatar,
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.repository.saveProfile(
        widget.profile.copyWith(
          nickname: _name.text.trim(),
          bio: _bio.text.trim(),
          interests: _interests.toList(),
          profileColor: _color,
          avatar: _options[_selected].asset,
        ),
      );
      if (mounted) Navigator.pop(context, saved);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '저장하지 못했어요. 다시 시도해 주세요.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: BogleDialog(
      title: '프로필 수정',
      icon: Icons.face_retouching_natural_rounded,
      subtitle: '나를 소개하는 작은 공간을 꾸며 보세요.',
      width: 640,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '저장 중…' : '저장'),
        ),
      ],
      child: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('프로필에 함께할 친구를 골라 주세요.'),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (i, o) in _options.indexed)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: SizedBox(
                            width: 100,
                            child: Semantics(
                              button: true,
                              selected: i == _selected,
                              label: '${o.label} 프로필 선택',
                              excludeSemantics: true,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: _saving
                                    ? null
                                    : () => setState(() => _selected = i),
                                child: Column(
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 160,
                                      ),
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          width: 3,
                                          color: i == _selected
                                              ? BogleColors.blueStrong
                                              : Colors.transparent,
                                        ),
                                      ),
                                      child: ProfileAvatar(
                                        asset: o.asset,
                                        size: 72,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      o.label,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: i == _selected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  key: const ValueKey('profile-nickname'),
                  controller: _name,
                  enabled: !_saving,
                  maxLength: 12,
                  textInputAction: TextInputAction.done,

                  decoration: const InputDecoration(
                    labelText: '불러 줄 이름',
                    hintText: '1~12글자',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? '이름을 입력해 주세요.'
                      : value.trim().characters.length > 12
                      ? '12글자 이내로 입력해 주세요.'
                      : null,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: const ValueKey('profile-bio'),
                  controller: _bio,
                  enabled: !_saving,
                  maxLength: 60,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '한 줄 소개',
                    hintText: '예: 그림 그리기와 구름 구경을 좋아해요.',
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '좋아하는 활동',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                ),
                const Text(
                  '최대 3개 · 마이페이지에 함께 보여요.',
                  style: TextStyle(fontSize: 13, color: BogleColors.muted),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final interest in UserProfile.interestChoices)
                      FilterChip(
                        label: Text(interest),
                        selected: _interests.contains(interest),
                        onSelected: _saving
                            ? null
                            : (selected) {
                                if (selected && _interests.length >= 3) {
                                  setState(
                                    () => _error = '좋아하는 활동은 최대 3개까지 고를 수 있어요.',
                                  );
                                  return;
                                }
                                setState(() {
                                  selected
                                      ? _interests.add(interest)
                                      : _interests.remove(interest);
                                  _error = null;
                                });
                              },
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                const Text(
                  '프로필 포인트 색상',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (value, label, color) in profileColors)
                      ChoiceChip(
                        key: ValueKey('profile-color-$value'),
                        avatar: CircleAvatar(backgroundColor: color, radius: 9),
                        label: Text(label),
                        selected: _color == value,
                        onSelected: _saving
                            ? null
                            : (_) => setState(() => _color = value),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
