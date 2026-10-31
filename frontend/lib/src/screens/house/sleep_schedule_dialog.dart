import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../models/character_friend.dart';
import '../../theme/bogle_theme.dart';

/// Picks when [friend] goes to bed and gets up. Returns the new schedule,
/// or null if the child backs out.
Future<SleepSchedule?> showSleepSchedule(
  BuildContext context,
  CharacterFriend friend,
) => showDialog<SleepSchedule>(
  context: context,
  builder: (_) => _SleepScheduleDialog(friend: friend),
);

class _SleepScheduleDialog extends StatefulWidget {
  const _SleepScheduleDialog({required this.friend});
  final CharacterFriend friend;
  @override
  State<_SleepScheduleDialog> createState() => _SleepScheduleDialogState();
}

class _SleepScheduleDialogState extends State<_SleepScheduleDialog> {
  late int _bedtime = widget.friend.sleep.bedtime;
  late int _wakeTime = widget.friend.sleep.wakeTime;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.friend.name}의 잠자는 시간'),
    content: SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '잠드는 시간이 되면 스스로 잠들고, 일어나는 시간이 되면 깨어나요.',
            style: TextStyle(fontSize: 15, color: BogleColors.muted),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _TimeWheel(
                  key: const ValueKey('sleep-bedtime'),
                  icon: Icons.bedtime_rounded,
                  label: '잠드는 시간',
                  minutes: _bedtime,
                  onChanged: (m) => setState(() => _bedtime = m),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _TimeWheel(
                  key: const ValueKey('sleep-wake-time'),
                  icon: Icons.wb_sunny_rounded,
                  label: '일어나는 시간',
                  minutes: _wakeTime,
                  onChanged: (m) => setState(() => _wakeTime = m),
                ),
              ),
            ],
          ),
          if (_bedtime == _wakeTime)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                '잠드는 시간과 일어나는 시간이 같으면 잠들지 않아요.',
                style: TextStyle(fontSize: 14, color: BogleColors.muted),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: BogleColors.logo),
        onPressed: () => Navigator.pop(
          context,
          SleepSchedule(bedtime: _bedtime, wakeTime: _wakeTime),
        ),
        child: const Text('저장'),
      ),
    ],
  );
}

class _TimeWheel extends StatelessWidget {
  const _TimeWheel({
    super.key,
    required this.icon,
    required this.label,
    required this.minutes,
    required this.onChanged,
  });
  final IconData icon;
  final String label;
  final int minutes;
  final ValueChanged<int> onChanged;

  static const _step = 30;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F8FC),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: const Color(0xFF8C7BFF)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: BogleColors.text,
              ),
            ),
          ],
        ),
        // Half-hour steps named the way the card says them ("밤 9시"),
        // rather than a clock face with AM/PM.
        SizedBox(
          height: 150,
          child: CupertinoPicker(
            itemExtent: 36,
            scrollController: FixedExtentScrollController(
              initialItem: minutes ~/ _step,
            ),
            onSelectedItemChanged: (i) => onChanged(i * _step),
            children: [
              for (var m = 0; m < 24 * 60; m += _step)
                Center(
                  child: Text(
                    timeOfDayLabel(m),
                    style: const TextStyle(
                      fontFamily: bogleBodyFont,
                      fontSize: 18,
                      color: BogleColors.text,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
