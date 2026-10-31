import 'package:flutter/material.dart';
import '../data/app_services.dart';
import 'bogle_dialog.dart';

Future<void> showSyncStatus(BuildContext context) async {
  final outbox = AppServices.of(context).sync?.outbox;
  if (outbox == null) return;
  final pending = await outbox.pending;
  final rejected = await outbox.rejected;
  if (!context.mounted) return;
  const labels = {
    'name': '이름',
    'introduction': '소개',
    'nickname': '닉네임',
    'bio': '한 줄 소개',
    'personality': '성격',
    'speechStyle': '말투',
    'bedtime': '잠드는 시간',
    'wakeTime': '일어나는 시간',
  };
  await showDialog<void>(
    context: context,
    builder: (context) => BogleDialog(
      title: '동기화 상태',
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('확인'),
        ),
      ],
      child: Text(
        [
          pending == 0 ? '전송을 기다리는 변경이 없어요.' : '$pending개의 변경이 전송을 기다리고 있어요.',
          if (rejected.isNotEmpty) '아래 내용은 서버에 저장하지 못했어요. 해당 설정에서 다시 수정해 주세요.',
          for (final item in rejected) ...[
            '',
            item['target'] == null ? '마이페이지' : '보관함 · 친구 정보 수정',
            for (final entry in (item['fields'] as Map).entries)
              '${labels[entry.key] ?? '설정'}: ${entry.value}',
          ],
        ].join('\n'),
      ),
    ),
  );
}
