import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/photo_preparation.dart';
import '../../theme/bogle_theme.dart';
import '../../widgets/photo_icon.dart';
import '../photo_edit.dart';

/// Retain the original until the child explicitly accepts a proposed cutout.
class PhotoPreparationDialog extends StatefulWidget {
  const PhotoPreparationDialog({super.key, required this.photo});
  final Uint8List photo;
  @override
  State<PhotoPreparationDialog> createState() => _PhotoPreparationDialogState();
}

class _PhotoPreparationDialogState extends State<PhotoPreparationDialog> {
  bool _paper = false, _busy = false, _original = true;
  Offset _subject = const Offset(.5, .5);
  Uint8List? _proposal;
  bool _hasSelection = false;
  late final Future<Size> _sourceSize = photoSize(widget.photo);
  Future<Size>? _resultSize;
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String? _message;
  Future<void> _prepare() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await PhotoPreparation.prepare(
        widget.photo,
        paper: _paper,
        subject: _subject,
      );
      final size = photoSize(result);
      if (mounted) {
        setState(() {
          _resultSize = size;
          _proposal = result;
          _original = false;
        });
      }
    } on MissingPluginException {
      if (mounted) {
        setState(
          () => _message = '이 환경에서는 자동 정리를 사용할 수 없어요. 원본이나 수동 자르기로 진행해 주세요.',
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () =>
              _message = error.message ?? '대상을 찾지 못했어요. 다른 곳을 누르거나 직접 잘라 주세요.',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _message = '사진을 정리하지 못했어요. 원본은 그대로 보관돼 있어요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final ready = _proposal != null;
    final primary = FilledButton(
      key: const ValueKey('photo-subject-primary'),
      onPressed: _busy || (ready && _original)
          ? null
          : ready
          ? () => Navigator.pop(
              context,
              PreparedPhoto(_proposal!, subjectSelected: !_paper),
            )
          : _prepare,
      style: FilledButton.styleFrom(
        backgroundColor: BogleColors.logo,
        foregroundColor: Colors.white,
        disabledBackgroundColor: BogleColors.blueSoft,
        disabledForegroundColor: BogleColors.muted,
        minimumSize: const Size(180, 56),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(
          fontFamily: bogleDisplayFont,
          fontSize: 20,
          height: 1.4,
        ),
      ),
      child: _busy
          ? const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('사진을 정리하고 있어요…'),
              ],
            )
          : Text(ready ? '정리한 사진 사용' : '정리해 보기'),
    );
    return PopScope(
      canPop: !_busy,
      child: DefaultTextStyle(
        style: const TextStyle(
          fontFamily: bogleUiFont,
          fontSize: 16,
          height: 1.5,
          color: BogleColors.text,
        ),
        child: Dialog(
          backgroundColor: BogleColors.cream,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 940,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight:
                    media.size.height -
                    media.viewInsets.vertical -
                    media.padding.vertical -
                    48,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 24, 16, 12),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '어떤 친구로 만들까요?',
                            style: TextStyle(
                              fontFamily: bogleQuestionFont,
                              fontSize: 30,
                              height: 1.3,
                              letterSpacing: -.9,
                              color: BogleColors.text,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '닫기',
                          onPressed: _busy
                              ? null
                              : () => Navigator.pop(context),
                          icon: const PhotoIcon('x', size: 22),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: Scrollbar(
                      controller: _scroll,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(28, 12, 28, 16),
                        child: LayoutBuilder(
                          builder: (context, box) {
                            final preview = _preview(
                              media.size.height < 700 ? 280 : 400,
                            );
                            final options = _options();
                            if (box.maxWidth >= 760 &&
                                media.textScaler.scale(1) < 1.5) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 6, child: preview),
                                  const SizedBox(width: 28),
                                  Expanded(flex: 4, child: options),
                                ],
                              );
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                preview,
                                const SizedBox(height: 20),
                                options,
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
                    child: OverflowBar(
                      alignment: MainAxisAlignment.end,
                      spacing: 16,
                      overflowSpacing: 12,
                      children: [
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            foregroundColor: BogleColors.muted,
                            minimumSize: const Size(100, 56),
                            textStyle: const TextStyle(
                              fontFamily: bogleDisplayFont,
                              fontSize: 20,
                            ),
                          ),
                          child: const Text('원본 유지'),
                        ),
                        primary,
                      ],
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

  Widget _options() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        '사진 종류',
        style: TextStyle(
          fontFamily: bogleUiFont,
          fontSize: 14,
          color: BogleColors.muted,
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final paper in [false, true])
            ChoiceChip(
              label: Text(paper ? '종이에 그린 그림' : '사물·인형·동식물'),
              selected: _paper == paper,
              showCheckmark: false,
              selectedColor: BogleColors.blueSoft,
              backgroundColor: Colors.white,
              side: BorderSide(
                color: _paper == paper ? BogleColors.logo : BogleColors.line,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              labelStyle: const TextStyle(
                fontFamily: bogleUiFont,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: BogleColors.text,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              onSelected: _busy
                  ? null
                  : (_) => setState(() {
                      _paper = paper;
                      _proposal = null;
                      _original = true;
                      _message = null;
                      _hasSelection = false;
                    }),
            ),
        ],
      ),
      const SizedBox(height: 24),
      Text(
        _proposal != null
            ? '이 모습으로 만들까요?'
            : _paper
            ? '종이를 반듯하게 펴요'
            : '친구가 될 대상을 눌러요',
        style: const TextStyle(
          fontFamily: bogleQuestionFont,
          fontSize: 24,
          height: 1.4,
          letterSpacing: -.72,
          color: BogleColors.text,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        _proposal != null
            ? '원본과 비교해 보세요. 빠진 부분이 있으면 다시 골라도 괜찮아요.'
            : _paper
            ? '종이의 기울기를 맞춰요. 연한 선과 색은 그대로 남겨요.'
            : '사진에서 원하는 대상을 누른 뒤, 정리해 보기를 눌러 주세요.',
        style: const TextStyle(
          fontFamily: bogleUiFont,
          fontSize: 15,
          height: 1.65,
          color: BogleColors.muted,
        ),
      ),
      if (_proposal != null) ...[
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final original in [true, false])
              ChoiceChip(
                label: Text(original ? '원본 보기' : '정리한 사진 보기'),
                selected: _original == original,
                showCheckmark: false,
                selectedColor: BogleColors.blueSoft,
                backgroundColor: Colors.white,
                labelStyle: const TextStyle(
                  fontFamily: bogleUiFont,
                  fontSize: 14,
                  color: BogleColors.text,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                side: BorderSide(
                  color: _original == original
                      ? BogleColors.logo
                      : BogleColors.line,
                ),
                onSelected: _busy
                    ? null
                    : (_) => setState(() => _original = original),
              ),
          ],
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                  _proposal = null;
                  _original = true;
                  _message = null;
                }),
          style: TextButton.styleFrom(
            foregroundColor: BogleColors.muted,
            alignment: Alignment.centerLeft,
            textStyle: const TextStyle(fontFamily: bogleUiFont, fontSize: 14),
          ),
          child: const Text('대상 다시 고르기'),
        ),
      ],
      if (_message != null)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Semantics(
            liveRegion: true,
            child: Text(
              _message!,
              style: const TextStyle(
                fontFamily: bogleUiFont,
                fontSize: 14,
                height: 1.6,
                color: BogleColors.muted,
              ),
            ),
          ),
        ),
    ],
  );

  Widget _preview(double height) => SizedBox(
    height: height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F0EA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BogleColors.line),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FutureBuilder<Size>(
          future: _original ? _sourceSize : _resultSize,
          builder: (context, state) => LayoutBuilder(
            builder: (context, box) {
              final size = state.data;
              final fitted = size == null
                  ? Size.zero
                  : applyBoxFit(BoxFit.contain, size, box.biggest).destination;
              final rect = Alignment.center.inscribe(
                fitted,
                Offset.zero & box.biggest,
              );
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: _busy || !_original || _paper || size == null
                    ? null
                    : (details) {
                        if (!rect.contains(details.localPosition)) return;
                        setState(() {
                          _subject = Offset(
                            (details.localPosition.dx - rect.left) / rect.width,
                            (details.localPosition.dy - rect.top) / rect.height,
                          );
                          _hasSelection = true;
                          _proposal = null;
                          _message = '대상을 골랐어요. 정리해 보기를 눌러 주세요.';
                        });
                      },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(
                      _original ? widget.photo : _proposal!,
                      fit: BoxFit.contain,
                    ),
                    if (_original && _hasSelection && !_paper && size != null)
                      Positioned(
                        left: rect.left + _subject.dx * rect.width - 17,
                        top: rect.top + _subject.dy * rect.height - 17,
                        child: IgnorePointer(
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: BogleColors.blueStrong,
                                width: 2,
                              ),
                              color: Colors.white.withValues(alpha: .4),
                            ),
                            child: const Center(
                              child: SizedBox.square(
                                dimension: 6,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: BogleColors.blueStrong,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}
