import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'house_widgets.dart';

/// Let the welcome be read before the visitor answers. Count visible
/// characters (including joined emoji), then leave a short conversational
/// beat with the host's bubble still on screen. These are product timings,
/// not a measured Korean reading-speed standard.
Duration greetingReplyDelay(String text) {
  final letters = text.replaceAll(RegExp(r'\s+'), '').characters.length;
  final reading = (1800 + letters * 140).clamp(4000, 8500);
  return Duration(milliseconds: reading + 650);
}

/// 문장·단어를 우선해 나누고 긴 한 단어만 표시 글자 경계에서 나눈다.
List<String> speechPages(String text, {int limit = 46}) {
  final pages = <String>[];
  var current = '';
  for (final word in text.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    if (current.isNotEmpty &&
        (current.characters.length + word.characters.length + 1 > limit)) {
      pages.add(current);
      current = '';
    }
    final letters = word.characters.toList();
    while (letters.length > limit) {
      pages.add(letters.take(limit).join());
      letters.removeRange(0, limit);
    }
    if (letters.isNotEmpty) {
      current = [if (current.isNotEmpty) current, letters.join()].join(' ');
    }
    if (RegExp(r'[.!?。]$').hasMatch(current) &&
        current.characters.length > limit ~/ 2) {
      pages.add(current);
      current = '';
    }
  }
  if (current.isNotEmpty) pages.add(current);
  return pages.isEmpty ? [text] : pages;
}

class SceneSpeech extends StatefulWidget {
  const SceneSpeech({
    super.key,
    required this.text,
    required this.maxWidth,
    required this.tailRight,
    this.speaker,
    this.sideTail = false,
  });
  final String text;
  final String? speaker;
  final double maxWidth;
  final bool tailRight;
  final bool sideTail;
  static Size estimate(
    BuildContext context,
    String text, {
    required double width,
    bool sideTail = false,
  }) {
    final pages = speechPages(text);
    var size = Size.zero;
    for (final page in pages) {
      final next = SpeechBubble.estimate(
        context,
        page,
        maxWidth: width,
        boxy: true,
        sideTail: sideTail,
        footer: pages.length > 1 ? '1 / ${pages.length} · 눌러서 이어보기' : null,
      );
      size = Size(
        math.max(size.width, next.width),
        math.max(size.height, next.height),
      );
    }
    return size;
  }

  @override
  State<SceneSpeech> createState() => _SceneSpeechState();
}

class _SceneSpeechState extends State<SceneSpeech> {
  int _page = 0;
  void _fullText() => showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(widget.speaker ?? '친구의 이야기'),
      content: SingleChildScrollView(child: Text(widget.text)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('닫기'),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final pages = speechPages(widget.text);
    return Semantics(
      label: widget.text == '···'
          ? '생각하는 중'
          : widget.speaker == null
          ? null
          : '${widget.speaker}의 말. ${pages[_page.clamp(0, pages.length - 1)]}',
      excludeSemantics: widget.speaker != null || widget.text == '···',
      liveRegion: true,
      button: pages.length > 1,
      onTap: pages.length > 1
          ? () => setState(() => _page = (_page + 1) % pages.length)
          : null,
      onLongPress: pages.length > 1 ? _fullText : null,
      hint: pages.length > 1 ? '눌러서 다음 문장, 길게 눌러 전체 읽기' : null,
      child: GestureDetector(
        onTap: pages.length > 1
            ? () => setState(() => _page = (_page + 1) % pages.length)
            : null,
        onLongPress: pages.length > 1 ? _fullText : null,
        child: SpeechBubble(
          text: pages[_page.clamp(0, pages.length - 1)],
          boxy: true,
          maxWidth: widget.maxWidth,
          tailRight: widget.tailRight,
          sideTail: widget.sideTail,
          footer: pages.length > 1
              ? '${_page + 1} / ${pages.length} · 눌러서 이어보기'
              : null,
        ),
      ),
    );
  }
}
