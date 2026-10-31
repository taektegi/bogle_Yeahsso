import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/character_repository.dart';
import '../data/character_generation.dart';
import '../data/studio_camera.dart';
import '../drawing/drawing_controller.dart';
import '../drawing/color_picker.dart';
import '../drawing/pencil_input.dart';
import '../drawing/studio_draft.dart';
import '../drawing/paper_viewport.dart';
import '../theme/bogle_theme.dart';
import '../theme/bogle_viewport.dart';
import '../widgets/bogle_widgets.dart';
import '../widgets/top_bar.dart';
import 'loading_screen.dart';
import 'photo_capture.dart';
import '../app_lifecycle.dart';

export '../drawing/studio_draft.dart' show Paper;

part 'create_studio/studio_controls.dart';

enum CreateMode { drawing, photo }

/// Pan and zoom of the sketchbook: a canvas point p shows at p * scale + pan.
typedef _View = ({double scale, Offset pan});

class CreateStudioScreen extends StatefulWidget {
  const CreateStudioScreen({
    super.key,
    required this.repository,
    this.camera,
    this.pickPhoto,
    this.draft,
  });
  final CharacterRepository repository;

  /// The camera "Take a photo" uses, and where it picks existing photos
  /// from; the iPad's own by default, replaceable in tests.
  final StudioCamera Function()? camera;
  final PhotoPicker? pickPhoto;
  final StudioDraft? draft;
  @override
  State<CreateStudioScreen> createState() => _CreateStudioScreenState();
}

class _CreateStudioScreenState extends State<CreateStudioScreen>
    with WidgetsBindingObserver {
  late final StudioDraft _draft;
  late final DrawingController _drawing;
  bool _draftReady = false;
  bool _ownsDraft = false;
  bool _restoringDraft = true, _handTool = false, _leftHanded = false;
  int? _panPointer;
  Offset? _panAt;
  bool _exporting = false;
  final _messages = GlobalKey<ScaffoldMessengerState>();
  final _visibleInk = ValueNotifier(false);
  int _inkCheck = 0;
  Timer? _inkCheckTimer;
  CreateMode _mode = CreateMode.drawing;
  DrawingTool _tool = DrawingTool.pen;
  DrawingTool _lastInkTool = DrawingTool.pen;
  DrawingTool _previousTool = DrawingTool.eraser;
  StreamSubscription<MethodCall>? _pencilEvents;
  bool _systemPencilOnly = false;
  bool? _pencilOnlyOverride;
  bool get _pencilOnly => _pencilOnlyOverride ?? _systemPencilOnly;
  bool _pencilDoubleTap = true;
  int? _stylusPointer;
  final _canvasKey = GlobalKey();
  final _hoverAt = ValueNotifier<Offset?>(null);
  Color _color = BogleColors.ink;
  double _opacity = 1;
  EraserMode _eraserMode = EraserMode.partial;
  Paper _paper = Paper.blank;
  bool _toolsVisible = true;
  bool _pickingColor = false;
  bool _sampling = false;
  final _savedColors = <Color>[
    BogleColors.ink,
    BogleColors.blueStrong,
    const Color(0xFFFF728C),
    const Color(0xFFFFC45E),
    const Color(0xFF53BE94),
    Colors.white,
  ];

  /// Three thickness slots per tool, like Goodnotes' contextual toolbar.
  /// Tapping the chosen slot again fine-tunes it.
  final _widths = {
    DrawingTool.pen: [3.0, 6.0, 12.0],
    DrawingTool.marker: [12.0, 20.0, 32.0],
    DrawingTool.eraser: [12.0, 28.0, 56.0],
  };
  final _slot = {
    DrawingTool.pen: 1,
    DrawingTool.marker: 1,
    DrawingTool.eraser: 1,
  };
  double get _width => _widths[_tool]![_slot[_tool]!];

  // Pencil draws; touch draws or pans according to the explicit input mode.
  static const _identity = (scale: 1.0, pan: Offset.zero);
  final _view = ValueNotifier<_View>(_identity);
  final _touches = <int, Offset>{};
  int? _drawPointer;
  bool _liftingStrokes = false;
  bool _pinching = false;
  ({Offset focal, double distance, _View view})? _pinchStart;
  Offset? _lastErase;
  Size _viewport = Size.zero;
  Size get _paperSize => _draft.pageSize.isEmpty ? _viewport : _draft.pageSize;
  PaperViewport get _paperFit =>
      PaperViewport(paper: _paperSize, viewport: _viewport);

  /// Where the eraser is, drawn as a ring so its size is visible.
  final _eraserAt = ValueNotifier<Offset?>(null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pencilEvents = PencilInput.events.listen(_onPencilEvent);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncPencilPreferences(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_draftReady) return;
    final shared = widget.draft ?? StudioDraftScope.maybeOf(context);
    _ownsDraft = shared == null;
    _draft = shared ?? StudioDraft();
    _restoringDraft = _draft.store != null;
    _draft.attach();
    _draft.resetCount.addListener(_generatedDrawingConsumed);
    _drawing = _draft.drawing;
    _drawing.history.addListener(_checkVisibleInk);
    _draftReady = true;
    _applyDraft();
    _draft.ready.then((_) {
      if (!mounted) return;
      setState(() {
        _applyDraft();
        _restoringDraft = false;
      });
    });
  }

  void _generatedDrawingConsumed() {
    if (mounted) setState(_applyDraft);
  }

  void _applyDraft() {
    _paper = _draft.paper;
    _tool = _draft.tool;
    if (_tool != DrawingTool.eraser) _lastInkTool = _tool;
    _color = _draft.color;
    _opacity = _draft.opacity;
    _eraserMode = _draft.eraserMode;
    for (final tool in DrawingTool.values) {
      _widths[tool] = List.of(_draft.widths[tool]!);
      _slot[tool] = _draft.slots[tool]!;
    }
    _savedColors
      ..clear()
      ..addAll(_draft.savedColors);
    _pencilOnlyOverride = _draft.pencilOnly;
    _pencilDoubleTap = _draft.pencilDoubleTap;
    _leftHanded = _draft.leftHanded;
    _view.value = (scale: _draft.scale, pan: _draft.pan);
  }

  void _checkVisibleInk() {
    final check = ++_inkCheck;
    _inkCheckTimer?.cancel();
    if (!_drawing.hasInk) {
      _visibleInk.value = false;
      return;
    }
    if (_viewport.isEmpty) return;
    // Probe only committed history, not every Pencil event. A small debounced
    // raster catches fully erased pages without making the toolbar repaint ink.
    _inkCheckTimer = Timer(const Duration(milliseconds: 60), () async {
      try {
        final visible = await _drawing.hasVisibleInk(_paperSize);
        if (mounted && check == _inkCheck) _visibleInk.value = visible;
      } catch (_) {
        // The full-size export remains the authoritative guard on completion.
        if (mounted && check == _inkCheck) _visibleInk.value = _drawing.hasInk;
      }
    });
  }

  void _keepDraft() {
    _draft
      ..paper = _paper
      ..tool = _tool
      ..color = _color
      ..opacity = _opacity
      ..eraserMode = _eraserMode
      ..savedColors = List.of(_savedColors);
    _draft
      ..scale = _view.value.scale
      ..pan = _view.value.pan
      ..pencilOnly = _pencilOnlyOverride
      ..pencilDoubleTap = _pencilDoubleTap
      ..leftHanded = _leftHanded;
    for (final tool in DrawingTool.values) {
      _draft.widths[tool] = List.of(_widths[tool]!);
      _draft.slots[tool] = _slot[tool]!;
    }
    if (!_restoringDraft) _draft.changed();
  }

  Future<void> _syncPencilPreferences() async {
    final pencilOnly = await PencilInput.attach();
    if (mounted && pencilOnly != null) {
      setState(() => _systemPencilOnly = pencilOnly);
    }
  }

  void _selectTool(DrawingTool tool) {
    _stopDrawing(cancel: false);
    if (_handTool) setState(() => _handTool = false);
    _hoverAt.value = null;
    if (tool == _tool) return;
    setState(() {
      _previousTool = _tool;
      _tool = tool;
      if (tool != DrawingTool.eraser) _lastInkTool = tool;
    });
  }

  void _onPencilEvent(MethodCall event) {
    if (!mounted ||
        _mode != CreateMode.drawing ||
        !(ModalRoute.of(context)?.isCurrent ?? false) ||
        !onScreen(WidgetsBinding.instance.lifecycleState)) {
      _hoverAt.value = null;
      return;
    }
    final args = event.arguments is Map ? event.arguments as Map : const {};
    switch (event.method) {
      case 'doubleTap':
        if (_pencilDoubleTap) {
          _selectTool(
            _tool == DrawingTool.eraser ? _lastInkTool : DrawingTool.eraser,
          );
        }
      case 'squeeze':
        _stopDrawing(cancel: false);
        _hoverAt.value = null;
        switch (args['action']) {
          case 'eraser':
            _selectTool(
              _tool == DrawingTool.eraser ? _lastInkTool : DrawingTool.eraser,
            );
          case 'previous':
            _selectTool(_previousTool);
          case 'colors':
            _showColors();
          case 'width':
            _adjustSlot();
          case 'tools':
            _showPencilTools();
        }
      case 'hover':
        final box = _canvasKey.currentContext?.findRenderObject();
        if (args['visible'] != true ||
            _drawPointer != null ||
            box is! RenderBox ||
            args['x'] is! num ||
            args['y'] is! num) {
          _hoverAt.value = null;
          return;
        }
        final local = box.globalToLocal(
          Offset((args['x'] as num).toDouble(), (args['y'] as num).toDouble()),
        );
        _hoverAt.value = (Offset.zero & box.size).contains(local)
            ? _toCanvas(local)
            : null;
    }
  }

  Future<void> _showPencilTools() async {
    final tool = await showDialog<DrawingTool>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Pencil 도구'),
        children: [
          for (final (tool, label) in const [
            (DrawingTool.pen, '펜'),
            (DrawingTool.marker, '형광펜'),
            (DrawingTool.eraser, '지우개'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, tool),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    _toolIcon(tool, BogleColors.blueStrong),
                    const SizedBox(width: 16),
                    Text(label),
                    const Spacer(),
                    if (_tool == tool)
                      const Icon(Icons.check_rounded, size: 20),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (mounted && tool != null) _selectTool(tool);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncPencilPreferences();
    } else if (!onScreen(state)) {
      _stopDrawing(cancel: false);
      _keepDraft();
      _draft.flush().catchError((Object _) {});
      _hoverAt.value = null;
      _touches.clear();
      _pinching = false;
      _pinchStart = null;
    }
  }

  @override
  void dispose() {
    _stopDrawing(cancel: false);
    _keepDraft();
    _draft.resetCount.removeListener(_generatedDrawingConsumed);
    _drawing.history.removeListener(_checkVisibleInk);
    ++_inkCheck;
    _inkCheckTimer?.cancel();
    _visibleInk.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _pencilEvents?.cancel();
    _hoverAt.dispose();
    if (_ownsDraft) _draft.dispose();
    _draft.detach();
    _view.dispose();
    _eraserAt.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_exporting || !_drawing.hasInk) return;
    _stopDrawing(cancel: false);
    _keepDraft();
    setState(() => _exporting = true);
    final submittedRevision = _draft.revision;
    try {
      final png = await _drawing.exportInk(_paperSize);
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      if (png == null) {
        _messages.currentState?.showSnackBar(
          const SnackBar(content: Text('친구가 될 그림을 먼저 그려 주세요.')),
        );
        return;
      }
      await _draft.flush();
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      _openGeneration(
        GenerationInput(
          png,
          source: GenerationSource.drawing,
          sketchRevision: submittedRevision,
        ),
      );
    } catch (_) {
      if (mounted) {
        _messages.currentState?.showSnackBar(
          const SnackBar(content: Text('그림을 준비하지 못했어요. 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _openGeneration(GenerationInput input) {
    Navigator.of(context).push(
      bogleRoute(
        LoadingScreen(
          repository: widget.repository,
          input: input,
          draft: _draft,
        ),
      ),
    );
  }

  /// The drawing photographed on paper, chosen on the check screen. It goes
  /// to the character generator like a sketch does.
  void _createFromPhoto(Uint8List photo) {
    if (photo.isEmpty) return;
    _keepDraft();
    _openGeneration(GenerationInput(photo, source: GenerationSource.photo));
  }

  @override
  Widget build(BuildContext context) {
    if (_draftReady && !_restoringDraft) _keepDraft();
    final drawing = _mode == CreateMode.drawing;
    return ScaffoldMessenger(
      key: _messages,
      child: Scaffold(
        backgroundColor: BogleColors.cream,
        body: AmbientBackground(
          child: Column(
            children: [
              // Figma 250:2339 / 250:2379: the shared top bar with the two
              // modes as its pills.
              AppTopBar(
                repository: widget.repository,
                center: Row(
                  key: const ValueKey('studio-mode-switch'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: TopBarPill(
                        MediaQuery.sizeOf(context).width < 900
                            ? '그리기'
                            : 'Drawing',
                        compact: MediaQuery.sizeOf(context).width < 900,
                        key: const ValueKey('studio-mode-drawing'),
                        selected: drawing,
                        onTap: () => setState(() => _mode = CreateMode.drawing),
                      ),
                    ),
                    SizedBox(
                      width: BogleViewport.of(context).usable.width < 900
                          ? 12
                          : 24,
                    ),
                    Flexible(
                      child: TopBarPill(
                        MediaQuery.sizeOf(context).width < 900
                            ? '사진'
                            : 'Take a photo',
                        compact: MediaQuery.sizeOf(context).width < 900,
                        key: const ValueKey('studio-mode-photo'),
                        selected: !drawing,
                        onTap: () {
                          _stopDrawing(cancel: false);
                          setState(() => _mode = CreateMode.photo);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
                    child: _restoringDraft
                        ? const Center(child: CircularProgressIndicator())
                        : drawing
                        ? _buildDrawing()
                        : PhotoCapture(
                            key: const ValueKey('photo-workspace'),
                            camera: widget.camera ?? DeviceCamera.new,
                            pickPhoto: widget.pickPhoto ?? pickFromLibrary,
                            onUse: _createFromPhoto,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Pointer handling ------------------------------------------------

  Offset _toCanvas(Offset viewport) {
    final v = _view.value;
    return _paperFit.toPaper(viewport, zoom: v.scale, pan: v.pan);
  }

  void _pointerDown(PointerDownEvent e) {
    final stylus =
        e.kind == ui.PointerDeviceKind.stylus ||
        e.kind == ui.PointerDeviceKind.invertedStylus;
    // A resting palm must not turn a Pencil stroke into a pinch gesture.
    if (_stylusPointer != null) return;
    if (stylus) {
      _stopDrawing(cancel: true);
      _touches.clear();
      _pinching = false;
      _pinchStart = null;
      _stylusPointer = e.pointer;
    }
    _hoverAt.value = null;
    if (_pickingColor) {
      _sampleColor(_toCanvas(e.localPosition));
      return;
    }
    if (!stylus) _touches[e.pointer] = e.localPosition;
    if (!stylus && _touches.length == 2) {
      // A second finger means zoom, not ink: drop the line just started.
      _stopDrawing(cancel: true);
      _pinching = true;
      _panPointer = null;
      _startPinch();
      return;
    }
    if (!stylus && _touches.length == 1 && (_handTool || _pencilOnly)) {
      _panPointer = e.pointer;
      _panAt = e.localPosition;
      return;
    }
    if (!stylus &&
        (_touches.length > 1 ||
            _pinching ||
            (_pencilOnly && e.kind == ui.PointerDeviceKind.touch))) {
      return;
    }
    final p = _toCanvas(e.localPosition);
    if (!(Offset.zero & _paperSize).contains(p)) return;
    _drawPointer = e.pointer;
    if (_tool == DrawingTool.eraser) _eraserAt.value = p;
    _liftingStrokes =
        _tool == DrawingTool.eraser && _eraserMode == EraserMode.stroke;
    if (_liftingStrokes) {
      _lastErase = p;
      _drawing.eraseStrokesAt(p, _width / 2);
      return;
    }
    _drawing.begin(
      p,
      _color.withValues(
        alpha: _opacity * (_tool == DrawingTool.marker ? 0.35 : 1),
      ),
      _width,
      _tool,
      inputScale: _view.value.scale * _paperFit.scale,
    );
  }

  void _pointerMove(PointerMoveEvent e) {
    if (e.pointer != _stylusPointer) {
      if (_stylusPointer != null || !_touches.containsKey(e.pointer)) return;
      _touches[e.pointer] = e.localPosition;
    }
    if (_pinching) {
      if (_touches.length == 2) _updatePinch();
      return;
    }
    if (e.pointer == _panPointer) {
      final v = _view.value;
      _view.value = (
        scale: v.scale,
        pan: _clampPan(
          v.pan + e.localPosition - (_panAt ?? e.localPosition),
          v.scale,
        ),
      );
      _panAt = e.localPosition;
      _keepDraft();
      return;
    }
    if (e.pointer != _drawPointer) return;
    final p = _toCanvas(e.localPosition);
    if (_tool == DrawingTool.eraser) _eraserAt.value = p;
    if (_liftingStrokes) {
      // Step along fast swipes so thin lines between samples are caught.
      final from = _lastErase ?? p;
      final r = _width / 2;
      final steps = math.max(1, ((p - from).distance / r).ceil());
      for (var i = 1; i <= steps; i++) {
        _drawing.eraseStrokesAt(Offset.lerp(from, p, i / steps)!, r);
      }
      _lastErase = p;
    } else {
      _drawing.extend(p);
    }
  }

  void _pointerUp(PointerEvent e, {bool cancel = false}) {
    if (e.pointer == _stylusPointer) _stylusPointer = null;
    _touches.remove(e.pointer);
    if (e.pointer == _panPointer) {
      _panPointer = null;
      _panAt = null;
    }
    if (e.pointer == _drawPointer) _stopDrawing(cancel: cancel);
    if (_touches.length < 2) _pinchStart = null;
    if (_touches.length == 2) _startPinch();
    if (_pinching && _touches.length == 1) {
      _panPointer = _touches.keys.single;
      _panAt = _touches.values.single;
      _pinching = false;
    }
    // Once navigation ends, a fresh touch follows the selected input mode.
    if (_touches.isEmpty) _pinching = false;
  }

  void _stopDrawing({required bool cancel}) {
    if (_drawPointer == null) return;
    _drawPointer = null;
    _stylusPointer = null;
    _eraserAt.value = null;
    _lastErase = null;
    if (_liftingStrokes) {
      if (cancel) {
        _drawing.cancelStrokeErase();
      } else {
        _drawing.endStrokeErase();
      }
    } else if (cancel) {
      _drawing.cancel();
    } else {
      _drawing.end();
    }
  }

  void _startPinch() {
    final p = _touches.values.toList();
    _pinchStart = (
      focal: (p[0] + p[1]) / 2,
      distance: math.max((p[0] - p[1]).distance, 1),
      view: _view.value,
    );
  }

  void _updatePinch() {
    final start = _pinchStart;
    if (start == null) return;
    final p = _touches.values.toList();
    final focal = (p[0] + p[1]) / 2;
    final scale = (start.view.scale * (p[0] - p[1]).distance / start.distance)
        .clamp(1.0, 4.0);
    // Keep the page point that was under the fingers under them.
    final anchor = (start.focal - start.view.pan) / start.view.scale;
    _view.value = (scale: scale, pan: _clampPan(focal - anchor * scale, scale));
    _keepDraft();
  }

  /// Bound navigation to the fitted page area, with no unreachable paper.
  Offset _clampPan(Offset pan, double scale) => Offset(
    pan.dx.clamp(_viewport.width * (1 - scale), 0.0),
    pan.dy.clamp(_viewport.height * (1 - scale), 0.0),
  );

  // ---- Sketchbook ------------------------------------------------------

  Widget _buildDrawing() {
    return LayoutBuilder(
      builder: (context, workspace) => ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: LayoutBuilder(
                key: _canvasKey,
                builder: (context, box) {
                  if (_draft.pageSize.isEmpty && !_restoringDraft) {
                    _draft.pageSize = _drawing.paperExtent(box.biggest);
                    _draft.changed();
                  }
                  if (_viewport != box.biggest) {
                    final previous = _viewport;
                    _viewport = box.biggest;
                    final v = _view.value;
                    // Preserve the relative viewport position while resizing.
                    if (!previous.isEmpty) {
                      _view.value = (
                        scale: v.scale,
                        pan: _clampPan(
                          Offset(
                            v.pan.dx * _viewport.width / previous.width,
                            v.pan.dy * _viewport.height / previous.height,
                          ),
                          v.scale,
                        ),
                      );
                    }
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        _checkVisibleInk();
                        _keepDraft();
                      }
                    });
                  }
                  return Listener(
                    key: const ValueKey('drawing-canvas'),
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _pointerDown,
                    onPointerMove: _pointerMove,
                    onPointerUp: _pointerUp,
                    onPointerCancel: (e) => _pointerUp(e, cancel: true),
                    child: ColoredBox(
                      color: BogleColors.cream,
                      child: ValueListenableBuilder<_View>(
                        valueListenable: _view,
                        builder: (context, view, page) => Transform(
                          transform: _paperFit.transform(
                            zoom: view.scale,
                            pan: view.pan,
                          ),
                          child: OverflowBox(
                            alignment: Alignment.topLeft,
                            minWidth: _paperSize.width,
                            maxWidth: _paperSize.width,
                            minHeight: _paperSize.height,
                            maxHeight: _paperSize.height,
                            child: ClipRect(
                              child: SizedBox(
                                width: _paperSize.width,
                                height: _paperSize.height,
                                child: page,
                              ),
                            ),
                          ),
                        ),
                        child: ColoredBox(
                          color: Colors.white,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (_paper != Paper.blank)
                                RepaintBoundary(
                                  child: CustomPaint(
                                    key: ValueKey('paper-${_paper.name}'),
                                    painter: PaperPainter(_paper),
                                  ),
                                ),
                              RepaintBoundary(
                                child: CustomPaint(
                                  painter: InkPainter(_drawing),
                                  isComplex: true,
                                  willChange: true,
                                ),
                              ),
                              IgnorePointer(
                                child: CustomPaint(
                                  painter: _EraserRing(
                                    _eraserAt,
                                    _width / 2,
                                    _view,
                                    fitScale: _paperFit.scale,
                                  ),
                                ),
                              ),
                              IgnorePointer(
                                child: RepaintBoundary(
                                  child: CustomPaint(
                                    key: const ValueKey('pencil-hover-preview'),
                                    painter: _PencilHoverPreview(
                                      _hoverAt,
                                      _width / 2,
                                      _view,
                                      _tool == DrawingTool.eraser
                                          ? Colors.white
                                          : _color,
                                      _tool == DrawingTool.eraser,
                                      fitScale: _paperFit.scale,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              top: 20,
              left: 24,
              child: IgnorePointer(
                child: Text(
                  '나의 상상 스케치북',
                  style: TextStyle(
                    color: BogleColors.muted.withValues(alpha: 0.6),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            // Goodnotes shows the zoom level while zoomed; tapping it brings
            // the whole page back.
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: ValueListenableBuilder<_View>(
                  valueListenable: _view,
                  builder: (context, view, _) => AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: view.scale < 1.01
                        ? const SizedBox.shrink()
                        : _ZoomChip(
                            percent: (view.scale * 100).round(),
                            onReset: () {
                              _view.value = _identity;
                              _keepDraft();
                            },
                          ),
                  ),
                ),
              ),
            ),
            if (_pickingColor)
              Positioned(
                left: 0,
                right: 0,
                top: 48,
                child: Center(
                  child: Material(
                    color: BogleColors.blueSoft,
                    borderRadius: BorderRadius.circular(24),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 20, right: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.colorize_rounded, size: 20),
                          const SizedBox(width: 8),
                          const Text('그림에서 가져올 색상을 눌러 주세요'),
                          TextButton(
                            onPressed: () =>
                                setState(() => _pickingColor = false),
                            child: const Text('취소'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 16,
              bottom: 16,
              child: Material(
                color: BogleColors.cream,
                borderRadius: BorderRadius.circular(20),
                child: ValueListenableBuilder<int>(
                  valueListenable: _drawing.history,
                  builder: (_, _, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '되돌리기',
                        onPressed: _drawing.canUndo
                            ? () {
                                _stopDrawing(cancel: false);
                                _drawing.undo();
                              }
                            : null,
                        icon: const Icon(Icons.undo_rounded),
                      ),
                      IconButton(
                        tooltip: '다시 실행',
                        onPressed: _drawing.canRedo ? _drawing.redo : null,
                        icon: const Icon(Icons.redo_rounded),
                      ),
                      IconButton(
                        tooltip: '화면 이동',
                        isSelected: _handTool,
                        onPressed: () {
                          _stopDrawing(cancel: false);
                          setState(() => _handTool = !_handTool);
                        },
                        icon: const Icon(Icons.pan_tool_outlined),
                      ),
                      IconButton(
                        tooltip: '그리기 설정',
                        onPressed: _shapeSettings,
                        icon: const Icon(Icons.tune_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 24,
              top: 40,
              child: IgnorePointer(
                child: Text(
                  _handTool || _pencilOnly
                      ? '한 손가락으로 이동 · 두 손가락으로 확대'
                      : '손가락으로 그리기 · 두 손가락으로 확대·이동',
                  style: const TextStyle(
                    fontSize: 12,
                    color: BogleColors.muted,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 225,
              right: 100,
              bottom: 16,
              child: Center(
                child: Material(
                  color: BogleColors.cream,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: _quickColors(workspace.maxWidth < 700),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 225,
              right: 100,
              bottom: 72,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _drawing,
                  builder: (_, _) => _drawing.activeShape == null
                      ? const SizedBox()
                      : const Center(
                          child: Text(
                            '도형을 다듬었어요 · 더 움직이면 원래 선으로 돌아가요',
                            style: TextStyle(
                              fontSize: 13,
                              color: BogleColors.blueStrong,
                            ),
                          ),
                        ),
                ),
              ),
            ),
            // Down the right side: the ✓ that makes the friend on its own,
            Positioned(
              left: 225,
              right: 100,
              bottom: 105,
              child: ValueListenableBuilder<String?>(
                valueListenable: _draft.saveError,
                builder: (_, error, _) => error == null
                    ? const SizedBox()
                    : Center(
                        child: TextButton(
                          onPressed: () =>
                              _draft.flush().catchError((Object _) {}),
                          child: Text('$error  다시 저장'),
                        ),
                      ),
              ),
            ),
            // well apart from the tools below it so it is never mistaken for
            // one. Both shrink to fit a short canvas rather than spill past.
            Positioned(
              right: _leftHanded ? null : 16,
              left: _leftHanded ? 16 : null,
              top: 16,
              bottom: 16,
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ValueListenableBuilder<bool>(
                        valueListenable: _visibleInk,
                        builder: (context, _, _) => _DoneButton(
                          enabled: _visibleInk.value && !_exporting,
                          onTap: _create,
                          caption: true,
                        ),
                      ),
                      const SizedBox(height: 30),
                      _toolbarTransition(workspace.maxHeight),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickColors(bool scroll) {
    final colors = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final color in _savedColors.take(6))
          IconButton(
            tooltip: '빠른 색상 ${color.toARGB32().toRadixString(16)}',
            onPressed: () {
              _selectTool(_lastInkTool);
              setState(() => _color = color);
            },
            icon: _colorChip(color, 24),
          ),
      ],
    );
    return scroll
        ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: colors)
        : colors;
  }

  // Reserve the expanded dock's geometry throughout the transition. Changing
  // the child's height inside FittedBox used to rescale/recenter the whole
  // column (including the completion button) when an outgoing dock disappeared.
  // Slide/opacity only composite a small isolated layer; no per-frame layout.
  Widget _toolbarTransition(double workspaceHeight) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    Widget transition(
      Widget child, {
      required bool visible,
      bool slide = false,
    }) {
      return IgnorePointer(
        ignoring: !visible,
        child: ExcludeSemantics(
          excluding: !visible,
          child: AnimatedSlide(
            duration: duration,
            curve: Curves.easeOutCubic,
            offset: slide && !visible ? const Offset(.18, 0) : Offset.zero,
            child: AnimatedOpacity(
              duration: duration,
              curve: Curves.easeOutCubic,
              opacity: visible ? 1 : 0,
              child: child,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: 72,
      height: (workspaceHeight - 160).clamp(240.0, 690.0),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          transition(
            SingleChildScrollView(child: _toolbar()),
            visible: _toolsVisible,
            slide: true,
          ),
          Positioned(
            top: 0,
            right: 0,
            child: transition(_collapsedToolbar(), visible: !_toolsVisible),
          ),
        ],
      ),
    );
  }

  Widget _dock({required Widget child, Key? key}) => RepaintBoundary(
    key: key,
    child: Material(
      elevation: 8,
      shadowColor: BogleColors.ink.withValues(alpha: 0.16),
      color: const Color(0xFFFDFCF6),
      borderRadius: BorderRadius.circular(24),
      child: child,
    ),
  );

  /// With the tools tucked away, the dock shrinks to a tab showing the
  /// current tool; tapping it brings everything back.
  Widget _collapsedToolbar() => _dock(
    key: const ValueKey('dock-collapsed'),
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: '도구 보이기',
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => setState(() => _toolsVisible = true),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: SizedBox(
                  width: 56,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _toolIcon(_tool, BogleColors.ink),
                      if (_tool != DrawingTool.eraser) ...[
                        const SizedBox(height: 8),
                        _colorChip(_color, 18),
                      ],
                      const SizedBox(height: 6),
                      const Icon(
                        Icons.keyboard_arrow_left_rounded,
                        color: BogleColors.muted,
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
  );

  Widget _toolbar() => _dock(
    key: const ValueKey('dock-open'),
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DockButton(
              label: '도구 숨기기',
              icon: const Icon(Icons.keyboard_arrow_right_rounded, size: 26),
              onTap: () => setState(() => _toolsVisible = false),
            ),
            _toolButton(DrawingTool.pen, '펜'),
            _toolButton(DrawingTool.marker, '형광펜'),
            _toolButton(DrawingTool.eraser, '지우개'),
            _divider(),
            // Contextual section: what the chosen tool can change.
            const Text(
              '굵기',
              style: TextStyle(fontSize: 12, color: BogleColors.muted),
            ),
            for (var i = 0; i < 3; i++) _sizeSlot(i),
            _divider(),
            // A fixed contextual slot avoids resizing all tools whenever the
            // selected tool changes between colour and eraser controls.
            SizedBox(
              height: 88,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_tool == DrawingTool.eraser)
                    for (final (mode, label, short) in const [
                      (EraserMode.partial, '부분 지우기', '부분'),
                      (EraserMode.stroke, '선 지우기', '선'),
                    ])
                      _EraserModeChip(
                        label: label,
                        short: short,
                        selected: _eraserMode == mode,
                        onTap: () => setState(() => _eraserMode = mode),
                      )
                  else ...[
                    const Text(
                      '색상',
                      style: TextStyle(fontSize: 12, color: BogleColors.muted),
                    ),
                    _colorMenu(),
                  ],
                ],
              ),
            ),
            _paperMenu(),
            _divider(),
            ValueListenableBuilder<int>(
              valueListenable: _drawing.history,
              builder: (_, _, _) => Column(
                children: [
                  _DockButton(
                    label: '전체 지우기',
                    icon: const Icon(Icons.delete_outline_rounded, size: 23),
                    onTap: _drawing.isEmpty ? null : _confirmClear,
                  ),
                ],
              ),
            ),
            _divider(),
          ],
        ),
      ),
    ),
  );

  Widget _divider() => Container(
    width: 36,
    height: 1,
    margin: const EdgeInsets.symmetric(vertical: 8),
    color: BogleColors.line,
  );

  Widget _colorChip(Color color, double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: BogleColors.line),
    ),
  );

  Widget _colorMenu() => Tooltip(
    message: '색상',
    child: InkResponse(
      onTap: _showColors,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(child: _colorChip(_color, 30)),
      ),
    ),
  );

  static final _sideMenuStyle = MenuStyle(
    alignment: AlignmentDirectional.topStart,
    backgroundColor: const WidgetStatePropertyAll(Color(0xFFFDFCF6)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
  );

  Widget _toolIcon(DrawingTool tool, Color color) => switch (tool) {
    DrawingTool.pen => Icon(Icons.edit_rounded, size: 23, color: color),
    DrawingTool.marker => Icon(
      Icons.border_color_rounded,
      size: 22,
      color: color,
    ),
    DrawingTool.eraser => _EraserGlyph(color: color),
  };

  Widget _toolButton(DrawingTool tool, String label) {
    final selected = _tool == tool;
    return _DockButton(
      label: label,
      selected: selected,
      icon: _toolIcon(tool, selected ? Colors.white : BogleColors.ink),
      onTap: () {
        if (selected && tool == DrawingTool.pen && !_handTool) {
          _shapeSettings();
        } else {
          _selectTool(tool);
        }
      },
    );
  }

  Future<void> _shapeSettings() async {
    _stopDrawing(cancel: false);
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          void change({bool? enabled, bool? snap, bool? fill}) {
            update(
              () => _drawing.configureShapes(
                enabled: enabled ?? _drawing.drawAndHold,
                snap: snap ?? _drawing.snapToShapes,
                fill: fill ?? _drawing.fillShapes,
              ),
            );
            setState(() {});
          }

          return AlertDialog(
            title: const Text('그리기 후 유지'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '펜이나 형광펜으로 한 번에 그리고, 끝에서 잠깐 멈춰 보세요. 직선·원·타원·삼각형·사각형을 반듯하게 다듬어 드려요.',
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.6,
                        color: BogleColors.muted,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('그리기 후 유지'),
                      value: _drawing.drawAndHold,
                      onChanged: (v) => change(enabled: v),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('선 떨림 부드럽게'),
                      value: _drawing.stabilize,
                      onChanged: (v) {
                        update(() => _drawing.stabilize = v);
                        setState(() {});
                      },
                    ),
                    const Divider(),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('다른 모양에 스냅'),
                      subtitle: const Text('직선의 끝을 가까운 도형 끝점에 연결해요.'),
                      value: _drawing.snapToShapes,
                      onChanged: _drawing.drawAndHold
                          ? (v) => change(snap: v)
                          : null,
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('색상 채우기'),
                      subtitle: const Text('닫힌 도형 안을 선택한 색으로 채워요.'),
                      value: _drawing.fillShapes,
                      onChanged: _drawing.drawAndHold
                          ? (v) => change(fill: v)
                          : null,
                    ),
                    const SizedBox(height: 12),
                    const Divider(),
                    const Text('Apple Pencil', style: TextStyle(fontSize: 17)),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('도구를 왼쪽에 배치'),
                      value: _leftHanded,
                      onChanged: (v) {
                        update(() => _leftHanded = v);
                        setState(() {});
                      },
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('두 번 탭으로 지우개 전환'),
                      subtitle: const Text(
                        '지원되는 Pencil에서 펜과 지우개를 바꿔요. iPad 설정에서 꺼두면 동작하지 않아요.',
                      ),
                      value: _pencilDoubleTap,
                      onChanged: (v) {
                        update(() => _pencilDoubleTap = v);
                      },
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Pencil로만 그리기'),
                      subtitle: const Text('Pencil로 그리고, 한 손가락으로 종이를 이동해요.'),
                      value: _pencilOnly,
                      onChanged: (v) {
                        update(() => _pencilOnlyOverride = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Pencil과 손가락 모두 사용할 수 있어요. 되돌리기를 한 번 누르면 원래 그린 선으로 돌아가요.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: BogleColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('완료'),
              ),
            ],
          );
        },
      ),
    );
    if (mounted) setState(_keepDraft);
  }

  static const _slotNames = {
    DrawingTool.pen: ['가는 펜', '보통 펜', '굵은 펜'],
    DrawingTool.marker: ['가는 형광펜', '보통 형광펜', '굵은 형광펜'],
    DrawingTool.eraser: ['작은 지우개', '보통 지우개', '큰 지우개'],
  };

  Widget _sizeSlot(int i) {
    final selected = _slot[_tool] == i;
    final eraser = _tool == DrawingTool.eraser;
    final thickness = (_widths[_tool]![i] * .7).clamp(2.0, 16.0);
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final borderRadius = BorderRadius.circular(10);
    return Tooltip(
      message: _slotNames[_tool]![i],
      child: Semantics(
        button: true,
        selected: selected,
        // Keep the ripple on a small, local ink surface rather than the
        // whole dock. InkRipple has continuous eased expansion/fade, without
        // the theme's sparkle shader or a second pressed-highlight flash.
        child: RepaintBoundary(
          child: Material(
            color: selected ? BogleColors.blueSoft : Colors.transparent,
            borderRadius: borderRadius,
            animateColor: true,
            animationDuration: reducedMotion
                ? Duration.zero
                : const Duration(milliseconds: 160),
            child: InkWell(
              borderRadius: borderRadius,
              splashFactory: reducedMotion
                  ? NoSplash.splashFactory
                  : InkRipple.splashFactory,
              splashColor: BogleColors.ink.withValues(alpha: .09),
              highlightColor: Colors.transparent,
              onTap: () {
                if (selected) {
                  _adjustSlot();
                } else {
                  setState(() => _slot[_tool] = i);
                }
              },
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Container(
                    key: ValueKey('stroke-width-$i'),
                    width: 28,
                    height: thickness,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: eraser ? Colors.white : BogleColors.ink,
                      border: eraser
                          ? Border.all(color: BogleColors.ink, width: 1.6)
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const _paperMenuWidth = 180.0;

  Widget _paperMenu() => MenuAnchor(
    // To the left of the column, level with the button.
    alignmentOffset: const Offset(-(_paperMenuWidth + 16 + 10), 0),
    style: _sideMenuStyle,
    menuChildren: [
      for (final (paper, label) in const [
        (Paper.blank, '빈 종이'),
        (Paper.dots, '점 종이'),
        (Paper.grid, '모눈 종이'),
        (Paper.lines, '줄 종이'),
      ])
        SizedBox(
          width: _paperMenuWidth,
          child: MenuItemButton(
            onPressed: () => setState(() => _paper = paper),
            leadingIcon: _PaperSwatch(paper, selected: paper == _paper),
            trailingIcon: paper == _paper
                ? const Icon(
                    Icons.check_rounded,
                    size: 20,
                    color: BogleColors.blueStrong,
                  )
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
    ],
    builder: (context, menu, _) => _DockButton(
      label: '종이 고르기',
      icon: _PaperSwatch(_paper, selected: false, size: 24),
      onTap: () => menu.isOpen ? menu.close() : menu.open(),
    ),
  );

  Future<void> _confirmClear() async {
    final clear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('그림을 모두 지울까요?'),
        content: const Text('지운 뒤에도 되돌리기로 다시 가져올 수 있어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('모두 지우기'),
          ),
        ],
      ),
    );
    if (clear == true) _drawing.clear();
  }

  /// Fine-tunes thickness. Colour and opacity live in the colour panel.
  void _adjustSlot() {
    final tool = _tool;
    final slot = _slot[tool]!;
    final eraser = tool == DrawingTool.eraser;
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final width = _widths[tool]![slot];
          return AlertDialog(
            title: Text(_slotNames[tool]![slot]),
            content: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 72,
                    child: Center(
                      child: Container(
                        width: 200,
                        height: width,
                        decoration: BoxDecoration(
                          color: eraser ? Colors.white : BogleColors.ink,
                          border: eraser
                              ? Border.all(color: BogleColors.ink, width: 1.5)
                              : null,
                          borderRadius: BorderRadius.circular(32),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [const Text('굵기'), Text('${width.round()} pt')],
                  ),
                  Slider(
                    semanticFormatterCallback: (v) => '${v.round()} 포인트',
                    value: width,
                    min: 1,
                    max: 64,
                    onChanged: (v) {
                      setState(() => _widths[tool]![slot] = v);
                      update(() {});
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('완료'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showColors() async {
    final pick = await showDialog<bool>(
      context: context,
      builder: (_) => StudioColorPicker(
        color: _color,
        opacity: _opacity,
        saved: _savedColors,
        onChanged: (color, opacity) => setState(() {
          _color = color;
          _opacity = opacity;
        }),
      ),
    );
    if (mounted) {
      setState(() {
        _savedColors.remove(_color);
        _savedColors.insert(0, _color);
        if (_savedColors.length > 12) {
          _savedColors.removeRange(12, _savedColors.length);
        }
      });
    }
    if (mounted && pick == true) setState(() => _pickingColor = true);
  }

  /// Samples the painted paper + ink, not the toolbar or screen chrome.
  Future<void> _sampleColor(Offset point) async {
    if (_sampling) return;
    _sampling = true;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..translate(-point.dx, -point.dy);
    canvas.drawRect(Offset.zero & _paperSize, Paint()..color = Colors.white);
    if (_paper != Paper.blank) PaperPainter(_paper).paint(canvas, _paperSize);
    _drawing.paint(canvas, _paperSize);
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(1, 1);
      try {
        final bytes = await image.toByteData();
        if (mounted && bytes != null) {
          setState(() {
            _color = bytes.getUint8(3) == 0
                ? Colors.white
                : Color.fromARGB(
                    255,
                    bytes.getUint8(0),
                    bytes.getUint8(1),
                    bytes.getUint8(2),
                  );
            _pickingColor = false;
          });
          await _showColors();
        }
      } finally {
        image.dispose();
      }
    } catch (_) {
      if (mounted) {
        _messages.currentState?.showSnackBar(
          const SnackBar(content: Text('색상을 가져오지 못했어요. 그림을 다시 눌러 주세요.')),
        );
      }
    } finally {
      picture.dispose();
      _sampling = false;
    }
  }
}
