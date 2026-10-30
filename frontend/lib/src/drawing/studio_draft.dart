import 'package:flutter/material.dart';
import 'dart:async';
import '../data/local_store.dart';

import '../theme/bogle_theme.dart';
import 'drawing_controller.dart';

enum Paper { blank, dots, grid, lines }

/// Device-local sketch draft, independent of a page's lifetime. Vector ink,
/// undo and tool preferences survive relaunches when a store is attached.
class StudioDraft {
  StudioDraft({this.store}) {
    drawing.history.addListener(_inkChanged);
    ready = _restore();
  }
  final LocalStore? store;
  static int _serial = 0;
  static String _nextRevision() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_serial++}';
  String _revision = _nextRevision();
  String get revision => _revision;
  final resetCount = ValueNotifier(0);

  void _inkChanged() {
    if (_restoring || _disposed) return;
    _revision = _nextRevision();
    changed();
  }

  /// 생성에 쓴 바로 그 그림만 소비한다. 나중에 그린 그림은 보존한다.
  Future<void> consumeGeneratedDrawing(String submittedRevision) async {
    await ready;
    if (_disposed || _revision != submittedRevision) return;
    scale = 1;
    pan = Offset.zero;
    pageSize = Size.zero;
    final preferences = drawing.snapshot();
    drawing.restore({...preferences, 'strokes': [], 'undo': [], 'redo': []});
    resetCount.value++;
    try {
      await flush();
    } catch (_) {
      // 생성된 친구는 정상으로 보여 주고, 초안 저장 오류는 다음 스케치북에 알린다.
    }
  }

  final saveError = ValueNotifier<String?>(null);
  late final Future<void> ready;
  Timer? _saveTimer;
  bool _restoring = true;
  double scale = 1;
  Offset pan = Offset.zero;
  Size pageSize = Size.zero;
  bool? pencilOnly;
  bool pencilDoubleTap = true, leftHanded = false;
  Future<void> _restore() async {
    try {
      final data = await store?.read('sketchbook');
      if (data is! Map) return;
      if (data['drawing'] is Map) drawing.restore(data['drawing'] as Map);
      _revision = data['revision'] as String? ?? _revision;
      final width = (data['pageWidth'] as num?)?.toDouble() ?? 0;
      final height = (data['pageHeight'] as num?)?.toDouble() ?? 0;
      if (width.isFinite && height.isFinite && width > 0 && height > 0) {
        pageSize = Size(width, height);
      }
      paper = Paper.values.asNameMap()[data['paper']] ?? Paper.blank;
      tool = DrawingTool.values.asNameMap()[data['tool']] ?? DrawingTool.pen;
      color = Color((data['color'] as int?) ?? BogleColors.ink.toARGB32());
      opacity = ((data['opacity'] as num?)?.toDouble() ?? 1).clamp(0, 1);
      eraserMode =
          EraserMode.values.asNameMap()[data['eraserMode']] ??
          EraserMode.partial;
      scale = ((data['scale'] as num?)?.toDouble() ?? 1).clamp(1, 4);
      pan = Offset(
        (data['panX'] as num?)?.toDouble() ?? 0,
        (data['panY'] as num?)?.toDouble() ?? 0,
      );
      pencilOnly = data['pencilOnly'] as bool?;
      pencilDoubleTap = data['pencilDoubleTap'] != false;
      leftHanded = data['leftHanded'] == true;
      for (final t in DrawingTool.values) {
        final w = (data['widths'] as Map?)?[t.name];
        if (w is List && w.length == 3) {
          widths[t] = w
              .map((v) => (v as num).toDouble().clamp(1.0, 64.0))
              .toList();
        }
        slots[t] = (((data['slots'] as Map?)?[t.name] as int?) ?? 1).clamp(
          0,
          2,
        );
      }
      if (data['colors'] is List) {
        savedColors = (data['colors'] as List)
            .whereType<int>()
            .map(Color.new)
            .take(12)
            .toList();
      }
    } catch (_) {
      /* Keep the usable draft if a save is malformed. */
    } finally {
      _restoring = false;
    }
  }

  void changed() {
    if (_restoring || _disposed || store == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), () {
      flush().catchError((Object _) {});
    });
  }

  Future<void> flush() async {
    if (_restoring || _disposed || store == null) return;
    _saveTimer?.cancel();
    try {
      await store!.write('sketchbook', {
        'drawing': drawing.snapshot(),
        'revision': _revision,
        'paper': paper.name,
        'pageWidth': pageSize.width,
        'pageHeight': pageSize.height,
        'tool': tool.name,
        'color': color.toARGB32(),
        'opacity': opacity,
        'eraserMode': eraserMode.name,
        'scale': scale,
        'panX': pan.dx,
        'panY': pan.dy,
        'pencilOnly': pencilOnly,
        'pencilDoubleTap': pencilDoubleTap,
        'leftHanded': leftHanded,
        'widths': {for (final t in DrawingTool.values) t.name: widths[t]},
        'slots': {for (final t in DrawingTool.values) t.name: slots[t]},
        'colors': savedColors.map((c) => c.toARGB32()).toList(),
      });
      if (!_disposed) saveError.value = null;
    } catch (_) {
      if (!_disposed) saveError.value = '초안을 저장하지 못했어요. 앱을 닫기 전에 다시 저장해 주세요.';
      rethrow;
    }
  }

  final drawing = DrawingController();
  int _readers = 0;
  bool _closing = false;
  bool _disposed = false;

  void attach() => _readers++;
  void detach() {
    _readers--;
    _disposeIfUnused();
  }

  Paper paper = Paper.blank;
  DrawingTool tool = DrawingTool.pen;
  Color color = BogleColors.ink;
  double opacity = 1;
  EraserMode eraserMode = EraserMode.partial;
  final widths = {
    DrawingTool.pen: [3.0, 6.0, 12.0],
    DrawingTool.marker: [12.0, 20.0, 32.0],
    DrawingTool.eraser: [12.0, 28.0, 56.0],
  };
  final slots = {
    DrawingTool.pen: 1,
    DrawingTool.marker: 1,
    DrawingTool.eraser: 1,
  };
  List<Color> savedColors = [
    BogleColors.ink,
    BogleColors.blueStrong,
    const Color(0xFFFF728C),
    const Color(0xFFFFC45E),
    const Color(0xFF53BE94),
    Colors.white,
  ];

  void dispose() {
    flush().catchError((Object _) {});
    _closing = true;
    _disposeIfUnused();
  }

  void _disposeIfUnused() {
    // The app owner's dispose can run before its page descendants dispose.
    if (_closing && _readers == 0 && !_disposed) {
      flush().catchError((Object _) {});
      _disposed = true;
      _saveTimer?.cancel();
      drawing.dispose();
      saveError.dispose();
      resetCount.dispose();
    }
  }
}

class StudioDraftScope extends InheritedWidget {
  const StudioDraftScope({
    super.key,
    required this.draft,
    required super.child,
  });
  final StudioDraft draft;
  static StudioDraft? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StudioDraftScope>()?.draft;
  @override
  bool updateShouldNotify(StudioDraftScope oldWidget) =>
      draft != oldWidget.draft;
}
