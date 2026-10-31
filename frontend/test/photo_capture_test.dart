import 'dart:ui' as ui;
import 'dart:async';
import 'package:bogle_app/src/data/app_services.dart';

import 'package:bogle_app/src/app_lifecycle.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/character_generation.dart';
import 'package:bogle_app/src/data/studio_camera.dart';
import 'package:bogle_app/src/screens/create_studio_screen.dart';
import 'package:bogle_app/src/screens/loading_screen.dart';
import 'package:bogle_app/src/screens/photo_capture.dart';
import 'package:bogle_app/src/screens/photo_edit.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 1×1 PNG.
final _png = Uint8List.fromList(const [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, //
  0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, //
  120, 156, 99, 248, 255, 255, 63, 0, 5, 254, 2, 254, 167, 53, 129, 132, 0, //
  0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

class FakeCamera implements StudioCamera {
  FakeCamera({this.problem, this.photo});
  final Uint8List? photo;
  final CameraProblem? problem;
  bool opened = false, closed = false, light = false;
  double zoom = 1;
  Offset? focused;
  int shots = 0;

  @override
  Future<void> open() async {
    if (problem case final p?) throw CameraFailure(p);
    opened = true;
  }

  @override
  Widget preview() =>
      const ColoredBox(key: ValueKey('fake-preview'), color: Color(0xFF445566));
  @override
  double get aspectRatio => 4 / 3;
  @override
  bool get hasLight => true;
  @override
  Future<void> setLight(bool on) async => light = on;
  @override
  double get minZoom => 1;
  @override
  double get maxZoom => 4;
  @override
  Future<void> setZoom(double z) async => zoom = z;
  @override
  Future<void> focusAt(Offset point) async => focused = point;
  @override
  Future<Uint8List> capture() async {
    shots++;
    return photo ?? _png;
  }

  @override
  Future<void> close() async => closed = true;
}

class _PhotoJob implements CharacterGenerationJob {
  final done = Completer<GeneratedArt>();
  @override
  Future<GeneratedArt> get result => done.future;
  @override
  void cancel() {}
}

class _PhotoGenerator implements CharacterGenerator {
  GenerationInput? input;
  @override
  CharacterGenerationJob start(GenerationInput value) {
    input = value;
    return _PhotoJob();
  }

  @override
  Future<CharacterGenerationJob?> unfinished() async => null;
  @override
  Future<void> finished(String id) async {}
  @override
  Future<void>? faceStillComing(String jobId) => null;
}

Future<void> _show(
  WidgetTester tester,
  Widget child, {
  AppServices? services,
}) async {
  tester.view.physicalSize = const Size(1366, 1024);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppServicesScope(
      services: services ?? AppServices.local(),
      child: MaterialApp(
        theme: buildBogleTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('look, focus, zoom, light, shoot, check, retake and use', (
    tester,
  ) async {
    final cameras = <FakeCamera>[];
    Uint8List? used;
    PhotoEdit? rendered;
    await _show(
      tester,
      Scaffold(
        body: PhotoCapture(
          camera: () => (cameras..add(FakeCamera())).last,
          pickPhoto: () async => null,
          onUse: (p) => used = p,
          render: (photo, edit) async {
            rendered = edit;
            return photo;
          },
        ),
      ),
    );
    final camera = cameras.single;
    expect(camera.opened, isTrue);
    expect(find.byKey(const ValueKey('fake-preview')), findsOneWidget);
    expect(find.text('그림이 네모 안에 꽉 차게 찍어 주세요'), findsOneWidget);

    // The viewfinder keeps the camera's 4:3 and the bar sits on its right.
    final live = tester.getRect(find.byKey(const ValueKey('photo-live')));
    expect(live.width / live.height, closeTo(4 / 3, .01));
    final shutter = tester.getRect(find.byKey(const ValueKey('photo-shutter')));
    expect(shutter.left, greaterThan(live.right));

    await tester.tapAt(live.topLeft + const Offset(100, 150));
    await tester.pump();
    expect(camera.focused!.dx, closeTo(100 / live.width, .01));

    final a = await tester.startGesture(live.center - const Offset(60, 0));
    final b = await tester.startGesture(live.center + const Offset(60, 0));
    for (var i = 0; i < 6; i++) {
      await a.moveBy(const Offset(-12, 0));
      await b.moveBy(const Offset(12, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pump();
    expect(camera.zoom, greaterThan(1.5));
    expect(find.byKey(const ValueKey('photo-zoom')), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('불 켜기'));
    await tester.pump();
    expect(camera.light, isTrue);

    await tester.tap(find.bySemanticsLabel('사진 찍기'));
    await tester.pumpAndSettle();
    expect(camera.shots, 1);
    // Checking: the camera rests.
    expect(camera.closed, isTrue);
    expect(find.text('사진을 확인해 주세요.'), findsOneWidget);
    expect(find.text('사용할래요.'), findsOneWidget);

    await tester.tap(find.text('다시 촬영할래요.'));
    await tester.pumpAndSettle();
    expect(cameras, hasLength(2));
    expect(find.byKey(const ValueKey('fake-preview')), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('사진 찍기'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('돌리기'));
    await tester.tap(find.bySemanticsLabel('선명하게'));
    await tester.pump();
    await tester.tap(find.text('사용할래요.'));
    await tester.pumpAndSettle();
    expect(rendered!.quarterTurns, 1);
    expect(rendered!.brighten, isTrue);
    expect(rendered!.crop, const Rect.fromLTRB(0, 0, 1, 1));
    expect(used, _png);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a photo from the library is checked the same way', (
    tester,
  ) async {
    await _show(
      tester,
      Scaffold(
        body: PhotoCapture(
          camera: FakeCamera.new,
          pickPhoto: () async => _png,
          onUse: (_) {},
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('사진 보관함에서 고르기'));
    await tester.pumpAndSettle();
    expect(find.text('사진을 확인해 주세요.'), findsOneWidget);
    expect(find.text('다시 고를래요.'), findsOneWidget);
    await tester.tap(find.text('다시 고를래요.'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fake-preview')), findsOneWidget);
  });

  testWidgets('camera not allowed: how to allow it, or use the library', (
    tester,
  ) async {
    var picked = 0;
    await _show(
      tester,
      Scaffold(
        body: PhotoCapture(
          camera: () => FakeCamera(problem: CameraProblem.denied),
          pickPhoto: () async {
            picked++;
            return null;
          },
          onUse: (_) {},
        ),
      ),
    );
    expect(find.text('카메라를 쓸 수 있게 해 주세요'), findsOneWidget);
    expect(find.text('설정 열기'), findsOneWidget);
    await tester.tap(find.text('사진 보관함에서 고르기'));
    await tester.pumpAndSettle();
    expect(picked, 1);
  });

  testWidgets('no camera at all (the simulator): the photo library', (
    tester,
  ) async {
    await _show(
      tester,
      Scaffold(
        body: PhotoCapture(
          camera: () => FakeCamera(problem: CameraProblem.unavailable),
          pickPhoto: () async => (await rootBundle.load(
            'assets/figma/archive_nemorin.png',
          )).buffer.asUint8List(),
          onUse: (_) {},
        ),
      ),
    );
    expect(find.text('이 기기에서는 카메라를 쓸 수 없어요'), findsOneWidget);
    expect(find.text('샘플 사진으로 해 보기'), findsNothing);
    await tester.tap(find.text('사진 보관함에서 고르기'));
    await tester.pumpAndSettle();
    expect(find.text('사진을 확인해 주세요.'), findsOneWidget);
  });

  testWidgets('the studio lets the camera go in the sketchbook and makes a '
      'friend from the photo', (tester) async {
    final validPhoto = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(128, 128);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List();
      image.dispose();
      picture.dispose();
      return bytes;
    }))!;
    final cameras = <FakeCamera>[];
    final generator = _PhotoGenerator();
    final repo = InMemoryCharacterRepository();
    await _show(
      tester,
      CreateStudioScreen(
        repository: repo,
        camera: () => (cameras..add(FakeCamera(photo: validPhoto))).last,
        pickPhoto: () async => null,
      ),
      services: AppServices.local(characters: repo, generator: generator),
    );
    expect(cameras, isEmpty);
    await tester.tap(find.text('Take a photo'));
    await tester.pumpAndSettle();
    expect(cameras.single.opened, isTrue);
    await tester.tap(find.text('Drawing'));
    await tester.pumpAndSettle();
    expect(cameras.single.closed, isTrue);

    await tester.tap(find.text('Take a photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('사진 찍기'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('사용할래요.'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(LoadingScreen), findsOneWidget);
    expect(generator.input!.source, GenerationSource.photo);
    expect(
      await tester.runAsync(() => photoSize(generator.input!.image)),
      const Size(128, 128),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cropping: drag a corner in, keep it, or cancel', (tester) async {
    PhotoEdit? rendered;
    await _show(
      tester,
      Scaffold(
        body: PhotoCapture(
          camera: FakeCamera.new,
          pickPhoto: () async => null,
          onUse: (_) {},
          render: (photo, edit) async {
            rendered = edit;
            return photo;
          },
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('사진 찍기'));
    await tester.pump();
    // The photo's shape is read on the real clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('자르기'));
    await tester.pumpAndSettle();
    expect(find.text('남길 곳을 골라 주세요.'), findsOneWidget);
    final area = tester.getRect(find.byKey(const ValueKey('photo-crop-area')));
    // Drag the top-left corner a quarter of the way in.
    await tester.dragFrom(
      area.topLeft + const Offset(4, 4),
      Offset(area.width / 4, area.height / 4),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.text('사진을 확인해 주세요.'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('자르기'));
    await tester.pumpAndSettle();
    await tester.dragFrom(
      area.topLeft + const Offset(4, 4),
      Offset(area.width / 4, area.height / 4),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('다 잘랐어요.'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('사용할래요.'));
    await tester.pumpAndSettle();
    final crop = rendered!.crop;
    expect(crop.left, closeTo(.25, .03));
    expect(crop.top, closeTo(.25, .03));
    expect(crop.right, 1);
    expect(crop.bottom, 1);
  });

  test('turning moves the crop with the photo', () {
    const crop = Rect.fromLTRB(.1, .2, .5, .6);
    // A quarter clockwise: the top edge becomes the right edge.
    expect(turnCrop(crop), const Rect.fromLTRB(.4, .1, .8, .5));
    var c = crop;
    for (var i = 0; i < 4; i++) {
      c = turnCrop(c);
    }
    expect(c.left, closeTo(crop.left, 1e-9));
    expect(c.bottom, closeTo(crop.bottom, 1e-9));
  });

  test('edits are baked into the picture', () async {
    // 2×1: a red pixel left of a blue one.
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..drawRect(
        const Rect.fromLTWH(0, 0, 1, 1),
        Paint()..color = const Color(0xFFFF0000),
      )
      ..drawRect(
        const Rect.fromLTWH(1, 0, 1, 1),
        Paint()..color = const Color(0xFF0000FF),
      );
    final image = await recorder.endRecording().toImage(2, 1);
    final png = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    expect(await renderPhotoEdit(png, uneditedPhoto), same(png));

    Future<(Size, List<int>)> pixels(Uint8List bytes) async {
      final codec = await ui.instantiateImageCodec(bytes);
      final img = (await codec.getNextFrame()).image;
      final data = (await img.toByteData())!;
      return (
        Size(img.width.toDouble(), img.height.toDouble()),
        [for (var i = 0; i < data.lengthInBytes; i += 4) data.getUint8(i)],
      );
    }

    // Turned a quarter: 1×2, red on top.
    final turned = await pixels(
      await renderPhotoEdit(png, (
        quarterTurns: 1,
        crop: const Rect.fromLTRB(0, 0, 1, 1),
        brighten: false,
      )),
    );
    expect(turned.$1, const Size(1, 2));
    // Smoothing blurs a 2-pixel picture a little: mostly red, then not.
    expect(turned.$2[0], greaterThan(200));
    expect(turned.$2[1], lessThan(60));
    // Cropped to its right half: just the blue pixel.
    final cropped = await pixels(
      await renderPhotoEdit(png, (
        quarterTurns: 0,
        crop: const Rect.fromLTRB(.5, 0, 1, 1),
        brighten: false,
      )),
    );
    expect(cropped.$1, const Size(1, 1));
    expect(cropped.$2.single, lessThan(60));
  });

  test('Control Center over the app still counts as on screen', () {
    expect(onScreen(AppLifecycleState.resumed), isTrue);
    expect(onScreen(AppLifecycleState.inactive), isTrue);
    expect(onScreen(null), isTrue);
    expect(onScreen(AppLifecycleState.hidden), isFalse);
    expect(onScreen(AppLifecycleState.paused), isFalse);
  });

  testWidgets('the camera stays on under Control Center, rests when away', (
    tester,
  ) async {
    final cameras = <FakeCamera>[];
    await _show(
      tester,
      Scaffold(
        body: PhotoCapture(
          camera: () => (cameras..add(FakeCamera())).last,
          pickPhoto: () async => null,
          onUse: (_) {},
        ),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(cameras.single.closed, isFalse);
    expect(find.byKey(const ValueKey('fake-preview')), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(cameras.single.closed, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(cameras, hasLength(2));
    expect(find.byKey(const ValueKey('fake-preview')), findsOneWidget);
  });
}
