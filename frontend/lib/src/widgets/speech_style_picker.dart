import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/speech_style.dart';
import '../theme/bogle_theme.dart';

/// 생성은 네 가지 말투를 바로 선택하고, 편집은 기존 말끝 설정도 유지한다.
class SpeechStylePicker extends StatefulWidget {
  const SpeechStylePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.scale = 1,
    this.creationLayout = false,
    this.confirmation,
  });
  final String? value;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final double scale;

  /// 생성 화면은 Figma의 하단 가로 카드, 기존 편집은 격자 배치를 유지한다.
  final bool creationLayout;
  final Widget? confirmation;
  @override
  State<SpeechStylePicker> createState() => _SpeechStylePickerState();
}

class _SpeechStylePickerState extends State<SpeechStylePicker> {
  late bool _polite = _politeness(widget.value);
  late SpeechManner? _manner = SpeechProfile.tryParse(
    widget.value ?? '',
  )?.manner;
  bool _politeness(String? value) =>
      SpeechProfile.tryParse(value ?? '')?.polite ??
      (value == '해요체' ||
          value?.contains('지요') == true ||
          value?.contains('존댓말') == true);
  @override
  void didUpdateWidget(SpeechStylePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _polite = _politeness(widget.value);
      _manner = SpeechProfile.tryParse(widget.value ?? '')?.manner;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scale.clamp(.85, 1.2);
    if (widget.creationLayout) return _creation(s);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.value != null && _manner == null) ...[
          Text(
            '현재 말투 · ${widget.value}',
            style: const TextStyle(
              fontFamily: bogleUiFont,
              color: BogleColors.text,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
        ],
        LayoutBuilder(
          builder: (context, box) {
            final columns =
                box.maxWidth < 340 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.4
                ? 1
                : 2;
            final width = (box.maxWidth - 12 * (columns - 1)) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final manner in SpeechManner.values)
                  SizedBox(
                    width: width,
                    child: _MannerCard(
                      manner: manner,
                      selected: _manner == manner,
                      scale: s,
                      onTap: widget.enabled
                          ? () {
                              setState(() => _manner = manner);
                              widget.onChanged(
                                SpeechProfile(manner, polite: _polite).value,
                              );
                            }
                          : null,
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        Text(
          '말끝',
          style: TextStyle(
            fontFamily: bogleDisplayFont,
            color: BogleColors.text,
            fontSize: 17 * s,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        _endings(),
      ],
    );
  }

  Widget _endings() => Row(
    children: [
      for (final (polite, label) in [(false, '편한 말'), (true, '공손한 말')])
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontFamily: bogleUiFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                backgroundColor: _polite == polite
                    ? BogleColors.blueSoft
                    : Colors.white,
                foregroundColor: BogleColors.text,
                side: BorderSide(
                  color: _polite == polite
                      ? BogleColors.blueStrong
                      : BogleColors.line,
                ),
              ),
              onPressed: !widget.enabled
                  ? null
                  : () {
                      setState(() => _polite = polite);
                      if (_manner != null) {
                        widget.onChanged(
                          SpeechProfile(_manner!, polite: polite).value,
                        );
                      }
                    },
              child: Semantics(selected: _polite == polite, child: Text(label)),
            ),
          ),
        ),
    ],
  );

  String _creationLabel(SpeechManner manner) => switch (manner) {
    SpeechManner.plain => '담백하게',
    SpeechManner.bouncy => '발랄하게',
    SpeechManner.story => '이야기하듯',
    SpeechManner.robot => '로봇처럼',
  };

  String _creationSample(SpeechManner manner) => switch (manner) {
    SpeechManner.plain => '“안녕. 만나서 반가워.”',
    SpeechManner.bouncy => '“야호! 같이 놀자!”',
    SpeechManner.story => '“우리의 모험을 시작해 볼까?”',
    SpeechManner.robot => '“삐빅! 친구를 발견했어.”',
  };

  Widget _creation(double s) => LayoutBuilder(
    builder: (context, box) {
      final columns = box.maxWidth >= 760 ? 4 : 2;
      final gap = 14 * s;
      final width = (box.maxWidth - gap * (columns - 1)) / columns;
      final titleStyle = TextStyle(
        fontFamily: bogleDisplayFont,
        fontSize: 22 * s,
        height: 1.25,
        color: BogleColors.text,
      );
      final detailStyle = TextStyle(
        fontFamily: bogleUiFont,
        fontSize: 13 * s,
        height: 1.4,
        color: const Color(0xFF737B8D),
      );
      double measure(String text, TextStyle style) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: math.max(1, width - 28 * s));
        final height = painter.height;
        painter.dispose();
        return height;
      }

      var height = 96 * s;
      for (final manner in SpeechManner.values) {
        height = math.max(
          height,
          math.max(22 * s, measure(_creationLabel(manner), titleStyle)) +
              measure(_creationSample(manner), detailStyle) +
              40 * s,
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final manner in SpeechManner.values)
                SizedBox(
                  width: width,
                  height: height,
                  child: Semantics(
                    label:
                        '${_creationLabel(manner)}, ${_creationSample(manner)}',
                    button: true,
                    selected: _manner == manner,
                    enabled: widget.enabled,
                    excludeSemantics: true,
                    child: Material(
                      key: ValueKey('speech-manner-${manner.name}'),
                      color: _manner == manner
                          ? const Color(0xFFEDF0FF)
                          : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12 * s),
                        side: BorderSide(
                          color: _manner == manner
                              ? BogleColors.logo
                              : BogleColors.blueSoft,
                          width: _manner == manner ? 2 : 1.5,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: !widget.enabled
                            ? null
                            : () {
                                setState(() => _manner = manner);
                                widget.onChanged(
                                  SpeechProfile(manner, polite: _polite).value,
                                );
                              },
                        child: Padding(
                          padding: EdgeInsets.all(14 * s),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _creationLabel(manner),
                                textAlign: TextAlign.center,
                                style: titleStyle,
                              ),
                              SizedBox(height: 8 * s),
                              Text(
                                _creationSample(manner),
                                textAlign: TextAlign.center,
                                style: detailStyle,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 16 * s),
          ?widget.confirmation,
        ],
      );
    },
  );
}

class _MannerCard extends StatelessWidget {
  const _MannerCard({
    required this.manner,
    required this.selected,
    required this.scale,
    required this.onTap,
  });
  final SpeechManner manner;
  final bool selected;
  final double scale;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '${manner.label}, ${manner.description}',
    button: true,
    selected: selected,
    enabled: onTap != null,
    excludeSemantics: true,
    child: Material(
      key: ValueKey('speech-manner-${manner.name}'),
      color: selected ? BogleColors.blueSoft : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected ? BogleColors.logo : BogleColors.line,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.all(12 * scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                manner.label,
                style: TextStyle(
                  fontFamily: bogleDisplayFont,
                  fontSize: 20 * scale,
                  color: BogleColors.text,
                  height: 1.2,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                manner.description,
                style: TextStyle(
                  fontFamily: bogleUiFont,
                  fontSize: 13 * scale,
                  height: 1.3,
                  color: const Color(0xFF57617B),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
