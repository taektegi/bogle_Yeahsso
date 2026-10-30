import 'package:flutter/material.dart';

import '../../data/profile_repository.dart';
import '../../theme/bogle_theme.dart';
import 'profile_widgets.dart';
import '../../widgets/bogle_dialog.dart';

/// "설정 및 고객센터": two columns of rows, as in the reference.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.profile,
    required this.onSave,
    required this.onEditProfile,
    required this.onAddresses,
    required this.onPaymentMethods,
  });
  final UserProfile profile;

  /// Persists; throws on failure.
  final Future<void> Function(UserProfile) onSave;
  final VoidCallback onEditProfile;
  final VoidCallback onAddresses, onPaymentMethods;

  @override
  Widget build(BuildContext context) {
    final left = [
      _Item(
        Icons.notifications_none_rounded,
        '알림 설정',
        () => showNotificationSettings(context, profile, onSave),
      ),
      _Item(Icons.person_outline_rounded, '계정 관리', onEditProfile),
      _Item(Icons.credit_card_rounded, '결제 수단 관리', onPaymentMethods),
    ];
    final right = [
      _Item(Icons.location_on_outlined, '배송지 관리', onAddresses),
      _Item(Icons.headset_mic_outlined, '고객센터', () => _help(context)),
      _Item(
        Icons.description_outlined,
        '이용약관 및 개인정보처리방침',
        () => _info(
          context,
          '이용약관 및 개인정보처리방침',
          '완성한 친구와 그림, 프로필, 돌봄 기록은 이 아이패드에 저장돼요. '
              '앱을 껐다 켜도 남아 있지만 앱을 삭제하면 기기에 저장한 데이터가 사라질 수 있어요.\n\n'
              '스케치북 초안과 도구 설정도 이 아이패드에 자동으로 저장돼요. '
              '서버가 연결된 버전은 친구 생성과 대화에 서버를 사용하고 친구와 프로필의 변경 내용을 동기화해요.\n\n'
              '배송지와 결제 수단의 표시 정보, 주문 내역은 이 아이패드에 저장돼요. '
              '이 안내는 현재 기능 설명이며 정식 약관과 개인정보처리방침은 준비 중이에요.',
        ),
      ),
    ];
    return ProfileSection(
      title: '설정 및 고객센터',
      child: ProfileCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: LayoutBuilder(
          builder: (context, box) => box.maxWidth >= 640
              ? IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: Column(children: left)),
                      const VerticalDivider(
                        width: 24,
                        color: ProfileStyle.border,
                        indent: 8,
                        endIndent: 8,
                      ),
                      Expanded(child: Column(children: right)),
                    ],
                  ),
                )
              : Column(children: [...left, ...right]),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: SizedBox(
      height: 56,
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(icon, size: 22, color: BogleColors.text),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: BogleColors.text,
              ),
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: ProfileStyle.subtle,
          ),
          const SizedBox(width: 8),
        ],
      ),
    ),
  );
}

void _info(BuildContext context, String title, String body) => showDialog<void>(
  context: context,
  builder: (context) => BogleDialog(
    title: title,
    icon: Icons.description_outlined,
    subtitle: '내 정보가 어디에 보관되는지 확인해 주세요.',
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('확인'),
      ),
    ],
    child: BogleDialogCard(child: Text(body)),
  ),
);

void _help(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => BogleDialog(
    title: '고객센터',
    icon: Icons.support_agent_rounded,
    subtitle: '궁금한 내용을 눌러 확인해 보세요.',
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('닫기'),
      ),
    ],
    child: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('자주 묻는 질문', style: ProfileStyle.itemTitle),
            for (final (q, a) in const [
              ('새 친구는 어떻게 만드나요?', '홈의 "그리기"에서 그림을 그리거나 사진을 찍으면 친구가 찾아와요.'),
              (
                '주문 내역은 어디에서 확인하나요?',
                '주문을 완료하면 마이페이지의 주문 내역에서 주문번호와 선택한 옵션, 배송 정보를 확인할 수 있어요.',
              ),
              (
                '그림과 프로필은 저장되나요?',
                '완성한 친구와 그림, 프로필은 이 아이패드에 저장돼 앱을 다시 켜도 남아 있어요. '
                    '스케치북 초안과 도구 설정도 자동으로 저장돼요.',
              ),
            ])
              ExpansionTile(
                title: Text(q),
                tilePadding: EdgeInsets.zero,
                shape: const Border(),
                collapsedShape: const Border(),
                childrenPadding: const EdgeInsets.only(bottom: 12),
                expandedAlignment: Alignment.centerLeft,
                children: [Text(a)],
              ),
            const SizedBox(height: 12),
            const Text(
              '1:1 문의는 고객센터가 연결되면 여기에서 바로 보낼 수 있어요.',
              style: ProfileStyle.label,
            ),
          ],
        ),
      ),
    ),
  ),
);

void showNotificationSettings(
  BuildContext context,
  UserProfile profile,
  Future<void> Function(UserProfile) onSave,
) => showDialog<void>(
  context: context,
  builder: (_) => _NotificationDialog(profile: profile, onSave: onSave),
);

class _NotificationDialog extends StatefulWidget {
  const _NotificationDialog({required this.profile, required this.onSave});
  final UserProfile profile;
  final Future<void> Function(UserProfile) onSave;
  @override
  State<_NotificationDialog> createState() => _NotificationDialogState();
}

class _NotificationDialogState extends State<_NotificationDialog> {
  late UserProfile _draft = widget.profile;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_draft);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '설정을 저장하지 못했어요. 다시 시도해 주세요.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: BogleDialog(
      title: '알림 설정',
      icon: Icons.notifications_none_rounded,
      subtitle: '받고 싶은 소식을 골라 주세요.',
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
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            SwitchListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              tileColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              activeTrackColor: BogleColors.logo,
              title: const Text('친구 소식'),
              subtitle: const Text('친구와의 새로운 이야기'),
              value: _draft.friendNotifications,
              onChanged: _saving
                  ? null
                  : (v) => setState(
                      () => _draft = _draft.copyWith(friendNotifications: v),
                    ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              tileColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              activeTrackColor: BogleColors.logo,
              title: const Text('주문·배송 소식'),
              subtitle: const Text('인형 제작과 배송 안내'),
              value: _draft.orderNotifications,
              onChanged: _saving
                  ? null
                  : (v) => setState(
                      () => _draft = _draft.copyWith(orderNotifications: v),
                    ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text(
                '알림을 받을 항목을 저장해요. 기기로 보내는 푸시 알림은 아직 지원하지 않아요.',
                style: TextStyle(fontSize: 13, color: BogleColors.muted),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
