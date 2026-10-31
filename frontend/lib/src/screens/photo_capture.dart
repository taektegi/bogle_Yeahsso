import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/studio_camera.dart';
import '../data/photo_preparation.dart';
import 'photo_capture/preparation_dialog.dart';
import '../theme/bogle_theme.dart';
import '../widgets/bogle_widgets.dart';
import '../widgets/photo_icon.dart';
import 'photo_edit.dart';
import '../app_lifecycle.dart';

part 'photo_capture/paper_frame.dart';
part 'photo_capture/viewfinder_art.dart';
part 'photo_capture/camera_controls.dart';
part 'photo_capture/review_controls.dart';

/// "Take a photo" (Figma wireframes 75 and 80, "캐릭터 촬영"): the back
/// camera looks at a drawing on paper through a torn-paper frame, with a
/// dark bar of controls on the right — the shutter, and the photo library
/// below it. A photo taken (or picked) is shown to check: "사용할래요." or
/// "다시 촬영할래요.".
///
/// Beyond the wireframe: a guide to fit the drawing in, tap to focus, pinch
/// to zoom, a light for dim rooms; turning, cropping and brightening the
/// photo while checking it; and a way on when the camera can't be used.
class PhotoCapture extends StatefulWidget {
  const PhotoCapture({
    super.key,
    required this.camera,
    required this.pickPhoto,
    required this.onUse,
    this.active = true,
    this.render = renderPhotoForGeneration,
  });

  /// Makes the camera to look through; a new one each time it opens.
  final StudioCamera Function() camera;
  final PhotoPicker pickPhoto;

  /// The photo the child chose, with its edits applied.
  final ValueChanged<Uint8List> onUse;

  /// Off while the studio shows the sketchbook: the camera is let go.
  final bool active;

  /// Applies the edits; replaceable in tests.
  final Future<Uint8List> Function(Uint8List photo, PhotoEdit edit) render;

  @override
  State<PhotoCapture> createState() => _PhotoCaptureState();
}

enum _Stage { opening, live, review, crop, problem }

class _PhotoCaptureState extends State<PhotoCapture>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  StudioCamera? _camera;
  _Stage _stage = _Stage.opening;
  CameraProblem? _problem;
  int _opening = 0;

  Uint8List? _photo;
  Uint8List? _originalPhoto;
  Future<String?>? _assessment;
  Size? _size;
  bool _fromLibrary = false;
  bool _preparedPhoto = false;
  PhotoEdit _edit = uneditedPhoto;

  /// The crop before the crop screen opened, to put back on "취소".
  Rect _cropBefore = uneditedPhoto.crop;
  bool _rendering = false;

  /// The last photo, shown in the library button like the Camera app does.
  Uint8List? _thumbnail;

  bool _light = false;
  bool _capturing = false;
  double _zoom = 1;
  double _pinchFrom = 1;
  Offset? _focus;
  String? _note;
  Timer? _noteTimer;

  /// The framing hint shows as the camera opens, then gets out of the way.
  bool _hint = false;
  Timer? _hintTimer;

  late final AnimationController _flash;
  late final AnimationController _focusRing;

  @override
  void initState() {
    super.initState();
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _focusRing = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    WidgetsBinding.instance.addObserver(this);
    if (widget.active) _open();
  }

  @override
  void didUpdateWidget(PhotoCapture old) {
    super.didUpdateWidget(old);
    final checking = _stage == _Stage.review || _stage == _Stage.crop;
    if (widget.active && !old.active) {
      if (!checking) _open();
    } else if (!widget.active && old.active) {
      _release();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.active || _stage == _Stage.review || _stage == _Stage.crop) {
      return;
    }
    if (state == AppLifecycleState.resumed) {
      // Back from Settings, maybe with the camera now allowed.
      _open();
    } else if (!onScreen(state)) {
      // Out of sight; Control Center over the app keeps the camera on.
      _release();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _opening++;
    _camera?.close();
    _flash.dispose();
    _focusRing.dispose();
    _noteTimer?.cancel();
    _hintTimer?.cancel();
    super.dispose();
  }

  Future<void> _open() async {
    if (_camera != null) return;
    final attempt = ++_opening;
    setState(() {
      _stage = _Stage.opening;
      _problem = null;
    });
    final camera = widget.camera();
    try {
      await camera.open();
    } on CameraFailure catch (f) {
      if (!mounted || attempt != _opening) return;
      setState(() {
        _stage = _Stage.problem;
        _problem = f.problem;
      });
      return;
    }
    if (!mounted || attempt != _opening || !widget.active) {
      await camera.close();
      return;
    }
    setState(() {
      _camera = camera;
      _stage = _Stage.live;
      _zoom = camera.minZoom;
      _light = false;
      _hint = true;
    });
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _hint = false);
    });
  }

  void _release() {
    _opening++;
    final camera = _camera;
    _camera = null;
    camera?.close();
    if (mounted && _stage == _Stage.live) {
      setState(() {
        _stage = _Stage.opening;
        _light = false;
      });
    }
  }

  void _say(String note) {
    _noteTimer?.cancel();
    setState(() => _note = note);
    _noteTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _note = null);
    });
  }

  Future<void> _shoot() async {
    final camera = _camera;
    if (camera == null || _capturing) return;
    setState(() => _capturing = true);
    HapticFeedback.mediumImpact();
    if (!MediaQuery.disableAnimationsOf(context)) _flash.forward(from: 0);
    try {
      final photo = await camera.capture();
      if (!mounted) return;
      _check(photo, fromLibrary: false);
    } catch (_) {
      if (mounted) _say('사진을 찍지 못했어요. 다시 찍어 볼까요?');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _pick() async {
    final Uint8List? photo;
    try {
      photo = await widget.pickPhoto();
    } catch (_) {
      if (mounted) _say('사진 보관함을 열지 못했어요.');
      return;
    }
    if (photo != null && mounted) _check(photo, fromLibrary: true);
  }

  /// The photo to check; the camera rests meanwhile.
  void _check(Uint8List photo, {required bool fromLibrary}) {
    _release();
    _originalPhoto = photo;
    setState(() {
      _photo = photo;
      _preparedPhoto = false;
      _assessment = PhotoPreparation.assess(photo);
      _size = null;
      _thumbnail = photo;
      _fromLibrary = fromLibrary;
      _edit = uneditedPhoto;
      _stage = _Stage.review;
    });
    // Its shape, for cropping; the whole photo shows in the meantime.
    photoSize(photo).then((size) {
      if (mounted && identical(_photo, photo)) setState(() => _size = size);
    }, onError: (Object _) {});
  }

  /// Back to the camera (or, if it can't be used, to the way round it).
  void _again() {
    setState(() {
      _photo = null;
      _size = null;
    });
    _open();
  }

  Future<void> _use() async {
    final photo = _photo;
    if (photo == null || _rendering) return;
    setState(() => _rendering = true);
    try {
      final done = await widget.render(photo, _edit);
      if (mounted) widget.onUse(done);
    } on FormatException catch (error) {
      if (mounted) _say(error.message);
    } catch (_) {
      if (mounted) _say('사진을 고치지 못했어요. 다시 해 볼까요?');
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  Future<void> _preparePhoto() async {
    if (_rendering || _photo == null) return;
    setState(() => _rendering = true);
    try {
      final snapshot = await widget.render(_photo!, _edit);
      if (!mounted) return;
      // The modal owns its progress state; avoid a spinning submit button
      // behind it while the child is simply choosing a subject.
      setState(() => _rendering = false);
      final result = await showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PhotoPreparationDialog(photo: snapshot),
      );
      if (mounted && result != null) {
        setState(() {
          _rendering = true;
          _photo = result;
          _preparedPhoto = true;
          _assessment = PhotoPreparation.assess(result);
          _edit = uneditedPhoto;
          _size = null;
        });
        final size = await photoSize(result);
        if (mounted) setState(() => _size = size);
      }
    } on FormatException catch (error) {
      if (mounted) _say(error.message);
    } catch (_) {
      if (mounted) _say('사진을 정리하지 못했어요. 직접 잘라서 진행할 수 있어요.');
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  void _turn() => setState(
    () => _edit = (
      quarterTurns: (_edit.quarterTurns + 1) % 4,
      crop: turnCrop(_edit.crop),
      brighten: _edit.brighten,
    ),
  );

  void _setCrop(Rect crop) => setState(
    () => _edit = (
      quarterTurns: _edit.quarterTurns,
      crop: crop,
      brighten: _edit.brighten,
    ),
  );

  void _startCrop() {
    _cropBefore = _edit.crop;
    setState(() => _stage = _Stage.crop);
  }

  void _endCrop({required bool keep}) {
    if (!keep) _setCrop(_cropBefore);
    setState(() => _stage = _Stage.review);
  }

  Future<void> _toggleLight() async {
    final camera = _camera;
    if (camera == null) return;
    final on = !_light;
    setState(() => _light = on);
    await camera.setLight(on);
    if (mounted && !camera.hasLight) setState(() => _light = false);
  }

  void _focusAt(Offset local, Size size) {
    final camera = _camera;
    if (camera == null) return;
    setState(() => _focus = local);
    _focusRing.forward(from: 0);
    camera.focusAt(
      Offset(
        (local.dx / size.width).clamp(0.0, 1.0),
        (local.dy / size.height).clamp(0.0, 1.0),
      ),
    );
  }

  void _pinch(double scale) {
    final camera = _camera;
    if (camera == null || camera.maxZoom <= camera.minZoom) return;
    final zoom = (_pinchFrom * scale).clamp(camera.minZoom, camera.maxZoom);
    if ((zoom - _zoom).abs() < .01) return;
    setState(() => _zoom = zoom);
    camera.setZoom(zoom);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => switch (_stage) {
      _Stage.review || _Stage.crop => _checking(box.biggest),
      _Stage.problem => _problemCard(),
      _ => _viewfinder(box.biggest),
    },
  );

  // ---- Looking through the camera (wireframe 75) -------------------------

  /// The wireframe's bar is about a tenth of the panel.
  static const _bar = 118.0;
  static const _barColor = Color(0xFF2B2C31);

  Widget _viewfinder(Size space) {
    final camera = _camera;
    final live = _stage == _Stage.live && camera != null;
    // The panel keeps the camera's shape, so what is framed is what is
    // taken; before the camera is ready it assumes 4:3. The wireframe
    // leaves a margin all round.
    final aspect = live
        ? math.max(camera.aspectRatio, 1 / camera.aspectRatio)
        : 4 / 3;
    const margin = 24.0;
    final width = math.min(
      space.width - _bar - margin * 2,
      (space.height - margin * 2) * aspect,
    );
    final size = Size(width, width / aspect);
    return Center(
      child: TornPaper(
        key: const ValueKey('photo-viewfinder'),
        seed: 7,
        child: SizedBox(
          width: size.width + _bar,
          height: size.height,
          child: Row(
            children: [
              SizedBox.fromSize(
                size: size,
                child: ColoredBox(
                  color: _barColor,
                  child: live ? _live(camera, size) : _starting(),
                ),
              ),
              _controls(live),
            ],
          ),
        ),
      ),
    );
  }

  Widget _starting() => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: BogleColors.logo,
          ),
        ),
        SizedBox(height: 16),
        Text(
          '카메라를 켜고 있어요',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
      ],
    ),
  );

  Widget _live(StudioCamera camera, Size size) {
    final note = _note;
    final motion = Duration(
      milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 400,
    );
    return GestureDetector(
      key: const ValueKey('photo-live'),
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => _focusAt(d.localPosition, size),
      onScaleStart: (_) => _pinchFrom = _zoom,
      onScaleUpdate: (d) {
        if (d.pointerCount > 1) _pinch(d.scale);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(child: camera.preview()),
          IgnorePointer(child: CustomPaint(painter: _Guide())),
          // Says how to frame the drawing as the camera opens, then fades
          // so nothing covers the drawing; problems show here too.
          Positioned(
            top: 18,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _hint || note != null ? 1 : 0,
                duration: motion,
                child: Center(child: _Hint(note ?? '그림이 네모 안에 꽉 차게 찍어 주세요')),
              ),
            ),
          ),
          if (_focus case final at?)
            AnimatedBuilder(
              animation: _focusRing,
              builder: (context, _) {
                final t = _focusRing.value;
                if (t >= 1) return const SizedBox();
                final grow =
                    1 +
                    .4 * (1 - Curves.easeOutBack.transform(math.min(1, t * 3)));
                return Positioned(
                  left: at.dx - 36,
                  top: at.dy - 36,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: t < .7 ? 1 : (1 - t) / .3,
                      child: Transform.scale(
                        scale: grow,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: BogleColors.yellow,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          if (_zoom > camera.minZoom + .05)
            Positioned(
              bottom: 18,
              left: 0,
              right: 0,
              child: Center(
                child: _Hint(
                  '${_zoom.toStringAsFixed(1)}×',
                  key: const ValueKey('photo-zoom'),
                ),
              ),
            ),
          // The shutter's blink.
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _flash,
              builder: (context, _) => ColoredBox(
                color: Colors.white.withValues(
                  alpha: _flash.isAnimating ? (1 - _flash.value) * .85 : 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// As in the wireframe: the shutter in the middle, the library square at
  /// the bottom — no words, just the shapes — and the light at the top.
  Widget _controls(bool live) => Container(
    width: _bar,
    color: _barColor,
    padding: const EdgeInsets.symmetric(vertical: 26),
    child: Column(
      children: [
        _BarButton(
          key: const ValueKey('photo-light'),
          icon: _light
              ? Icons.flashlight_on_rounded
              : Icons.flashlight_off_rounded,
          label: _light ? '불 끄기' : '불 켜기',
          active: _light,
          onTap: live && (_camera?.hasLight ?? false) ? _toggleLight : null,
        ),
        const Spacer(),
        _Shutter(onTap: live && !_capturing ? _shoot : null),
        const Spacer(),
        _LibraryButton(thumbnail: _thumbnail, onTap: _pick),
      ],
    ),
  );

  // ---- Checking the photo (wireframe 80) ---------------------------------

  /// The wireframe's check screen: the title centred above, the photo on
  /// the left and the two big choices beside it, the whole group in the
  /// middle of the page. Tools to turn, crop and brighten sit under the
  /// photo. Cropping swaps the photo for the crop frame and the choices
  /// for "다 잘랐어요." / "취소".
  Widget _checking(Size space) {
    final photo = _photo!;
    final cropping = _stage == _Stage.crop && _size != null;
    final wide = space.width > 820;
    final limit = BoxConstraints(
      maxWidth: space.width * (wide ? .46 : .82),
      maxHeight: space.height * (wide ? .52 : .42),
    );
    final turnedSize = _size == null
        ? null
        : (_edit.quarterTurns.isOdd ? _size!.flipped : _size!);
    final aspect = turnedSize == null
        ? 1.0
        : turnedSize.aspectRatio * _edit.crop.width / _edit.crop.height;
    final editorWidth = math.min(
      limit.maxWidth,
      math.max(math.min(440.0, limit.maxWidth), limit.maxHeight * aspect),
    );
    final picture = cropping
        ? ConstrainedBox(
            constraints: limit.tighten(
              width: limit.maxWidth,
              height: limit.maxHeight,
            ),
            child: CropEditor(
              bytes: photo,
              size: _size!,
              edit: _edit,
              onCrop: _setCrop,
            ),
          )
        : ConstrainedBox(
            constraints: limit,
            // The cutout already carries transparency. A paper shadow would
            // show through its empty pixels as a dark rectangle.
            child: _preparedPhoto
                ? EditedPhoto(bytes: photo, size: _size, edit: _edit)
                : TornPaper(
                    seed: 11,
                    child: EditedPhoto(bytes: photo, size: _size, edit: _edit),
                  ),
          );
    final tools = Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: [
        _Tweak(
          key: const ValueKey('photo-turn'),
          icon: 'rotate-cw',
          label: '돌리기',
          onTap: _rendering ? null : _turn,
        ),
        if (cropping)
          _Tweak(
            key: const ValueKey('photo-crop-reset'),
            icon: 'scan',
            label: '처음대로',
            onTap: _rendering ? null : () => _setCrop(uneditedPhoto.crop),
          )
        else ...[
          _Tweak(
            key: const ValueKey('photo-crop'),
            icon: 'crop',
            label: '자르기',
            selected: _edit.crop != uneditedPhoto.crop,
            onTap: _rendering || _size == null ? null : _startCrop,
          ),
          _Tweak(
            key: const ValueKey('photo-brighten'),
            icon: 'sliders-horizontal',
            label: '선명하게',
            selected: _edit.brighten,
            onTap: _rendering
                ? null
                : () => setState(
                    () => _edit = (
                      quarterTurns: _edit.quarterTurns,
                      crop: _edit.crop,
                      brighten: !_edit.brighten,
                    ),
                  ),
          ),
        ],
      ],
    );
    final choices = Column(
      mainAxisSize: MainAxisSize.min,
      children: cropping
          ? [
              _ChoiceButton(
                key: const ValueKey('photo-crop-done'),
                label: '다 잘랐어요.',
                primary: true,
                onTap: () => _endCrop(keep: true),
              ),
              const SizedBox(height: 20),
              _ChoiceButton(
                key: const ValueKey('photo-crop-cancel'),
                label: '취소',
                onTap: () => _endCrop(keep: false),
              ),
            ]
          : [
              _ChoiceButton(
                key: const ValueKey('photo-use'),
                label: '사용할래요.',
                primary: true,
                busy: _rendering,
                onTap: _use,
              ),
              const SizedBox(height: 20),
              _ChoiceButton(
                key: const ValueKey('photo-again'),
                label: _fromLibrary ? '다시 고를래요.' : '다시 촬영할래요.',
                onTap: _rendering ? null : _again,
              ),
            ],
    );
    // A fixed slot, so turning or cropping the photo never moves the
    // title, the tools or the choices beside it.
    final photoBlock = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: editorWidth,
          height: limit.maxHeight,
          child: Center(child: picture),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: editorWidth,
          child: IgnorePointer(ignoring: _rendering, child: tools),
        ),
        if (!cropping) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: editorWidth,
            child: _SubjectEntry(
              key: const ValueKey('photo-prepare'),
              onTap: _rendering ? null : _preparePhoto,
            ),
          ),
          if (_originalPhoto != null && !identical(_photo, _originalPhoto))
            TextButton.icon(
              onPressed: _rendering
                  ? null
                  : () => _check(_originalPhoto!, fromLibrary: _fromLibrary),
              icon: const PhotoIcon(
                'undo-2',
                size: 18,
                color: BogleColors.muted,
              ),
              label: const Text(
                '촬영 원본 복원',
                style: TextStyle(
                  fontFamily: bogleUiFont,
                  fontSize: 14,
                  color: BogleColors.muted,
                ),
              ),
            ),
        ],
        FutureBuilder<String?>(
          future: _assessment,
          builder: (context, state) => state.data == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    state.data!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: bogleUiFont,
                      color: BogleColors.muted,
                      fontSize: 14,
                    ),
                  ),
                ),
        ),
      ],
    );
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              cropping ? '남길 곳을 골라 주세요.' : '사진을 확인해 주세요.',
              style: const TextStyle(
                fontFamily: bogleDisplayFont,
                fontSize: 34,
                color: BogleColors.text,
              ),
            ),
            if (_note case final note?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  note,
                  style: const TextStyle(color: BogleColors.muted),
                ),
              ),
            const SizedBox(height: 28),
            if (wide)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  photoBlock,
                  SizedBox(width: space.width * .07),
                  choices,
                ],
              )
            else ...[
              photoBlock,
              const SizedBox(height: 28),
              choices,
            ],
          ],
        ),
      ),
    );
  }

  // ---- When the camera can't be used -------------------------------------

  Widget _problemCard() {
    final (icon, title, body) = switch (_problem) {
      CameraProblem.denied => (
        Icons.no_photography_rounded,
        '카메라를 쓸 수 있게 해 주세요',
        '설정 → 보글 → 카메라를 켜면 종이에 그린 그림을 찍을 수 있어요.\n'
            '사진 보관함에 있는 그림 사진을 골라도 돼요.',
      ),
      CameraProblem.unavailable => (
        Icons.photo_library_rounded,
        '이 기기에서는 카메라를 쓸 수 없어요',
        '사진 보관함에서 그림 사진을 골라 주세요.',
      ),
      _ => (
        Icons.videocam_off_rounded,
        '카메라를 켜지 못했어요',
        '잠시 뒤에 다시 켜 보거나, 사진 보관함에서 골라 주세요.',
      ),
    };
    return Center(
      child: Container(
        key: const ValueKey('photo-problem'),
        width: 560,
        padding: const EdgeInsets.fromLTRB(40, 36, 40, 32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: const [
            BoxShadow(
              color: Color(0x143A4A8C),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: const BoxDecoration(
                color: BogleColors.blueSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 42, color: BogleColors.logo),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: bogleDisplayFont,
                fontSize: 26,
                color: BogleColors.text,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                height: 1.5,
                color: BogleColors.muted,
              ),
            ),
            const SizedBox(height: 28),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                if (_problem == CameraProblem.denied)
                  PrimaryButton(
                    label: '설정 열기',
                    icon: Icons.settings_rounded,
                    onPressed: () => launchUrl(Uri.parse('app-settings:')),
                  )
                else if (_problem == CameraProblem.failed)
                  PrimaryButton(
                    label: '다시 켜 보기',
                    icon: Icons.refresh_rounded,
                    onPressed: _open,
                  ),
                PrimaryButton(
                  label: '사진 보관함에서 고르기',
                  icon: Icons.photo_library_outlined,
                  secondary: _problem != CameraProblem.unavailable,
                  onPressed: _pick,
                ),
              ],
            ),
            if (_note case final note?)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  note,
                  style: const TextStyle(color: BogleColors.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
