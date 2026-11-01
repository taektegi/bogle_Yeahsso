import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'house_widgets.dart';

int _letters(String text) =>
    text.replaceAll(RegExp(r'\s+'), '').characters.length;

/// Let the welcome be glanced at before the visitor answers: a short beat
/// that grows a little with the line, the host's bubble still on screen.
/// Always shorter than [speechHold], so the visitor answers before the
/// host's bubble fades. These are product timings, not a measured Korean
/// reading-speed standard.
Duration greetingReplyDelay(String text) => Duration(
  milliseconds: (1000 + _letters(text) * 80).clamp(2200, 4500) + 300,
);

/// How long a line (one page of it) stays up in the room before it fades,
/// when nobody is chatting: long enough to glance at, growing with its
/// length (visible letters, joined emoji counted once).
Duration speechHold(String text) =>
    Duration(milliseconds: (2000 + _letters(text) * 120).clamp(3500, 8000));

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
    this.holds = true,
    this.onFaded,
  });
  final String text;
  final String? speaker;
  final double maxWidth;
  final bool tailRight;
  final bool sideTail;

  /// Stays up until something else is said (in conversation the child
  /// reads at their own pace). Otherwise each page shows for its
  /// [speechHold], the next following by itself, and after the last the
  /// balloon fades and [onFaded] is called.
  final bool holds;
  final VoidCallback? onFaded;
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
  Timer? _timer;
  bool _fading = false;

  bool get _lingers =>
      widget.holds || widget.onFaded == null || widget.text == '···';

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(SceneSpeech old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _page = 0;
    if (old.text != widget.text || old.holds != widget.holds) {
      _fading = false;
      _arm();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Starts the current page's clock, unless the balloon stays up.
  void _arm() {
    _timer?.cancel();
    _timer = null;
    if (_lingers) return;
    final pages = speechPages(widget.text);
    _timer = Timer(speechHold(pages[_page.clamp(0, pages.length - 1)]), _next);
  }

  void _next() {
    if (!mounted) return;
    final pages = speechPages(widget.text);
    if (_page < pages.length - 1) {
      setState(() => _page++);
      _arm();
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      widget.onFaded?.call();
      return;
    }
    setState(() => _fading = true);
  }

  void _turn(int pages) {
    setState(() {
      _page = (_page + 1) % pages;
      _fading = false;
    });
    _arm();
  }

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
      onTap: pages.length > 1 ? () => _turn(pages.length) : null,
      onLongPress: pages.length > 1 ? _fullText : null,
      hint: pages.length > 1 ? '눌러서 다음 문장, 길게 눌러 전체 읽기' : null,
      child: GestureDetector(
        onTap: pages.length > 1 ? () => _turn(pages.length) : null,
        onLongPress: pages.length > 1 ? _fullText : null,
        child: AnimatedOpacity(
          opacity: _fading ? 0 : 1,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOut,
          onEnd: () {
            if (_fading && mounted) widget.onFaded?.call();
          },
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
      ),
    );
  }
}
