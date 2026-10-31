import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bogle_app/src/data/api/api_client.dart';
import 'package:bogle_app/src/data/api/api_window_views.dart';
import 'package:bogle_app/src/data/app_services.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/local_store.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:bogle_app/src/screens/friend_screen.dart';
import 'package:bogle_app/src/screens/house/house_widgets.dart';
import 'package:bogle_app/src/screens/house/room_scene.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class Session implements AuthSession {
  @override
  Future<String> accessToken() async => 'mock';
  @override
  Future<String> refresh() => accessToken();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> frames(WidgetTester tester, int ms) async {
    for (var i = 0; i < ms; i += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
  }

  testWidgets('iPad: 미리 만드는 배경 안내 후 완성 배경으로 교체', (tester) async {
    // 메모리 저장소와 임시 폴더만 쓴다. 기기의 저장 데이터는 건드리지 않는다.
    final repository = InMemoryCharacterRepository();
    final original = (await repository.fetchFriends()).firstWhere(
      (f) => f.id == 'mindle',
    );
    final friend = CharacterFriend(
      id: '01234567-0123-4567-89ab-012345678901',
      name: '새 민들레',
      personality: original.personality,
      favoriteThings: const [],
      speechStyle: original.speechStyle,
      assetPath: original.assetPath,
      accentHex: original.accentHex,
    );
    await repository.saveFriend(friend);
    final folder = await Directory.systemTemp.createTemp('bogle-pending-');
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(const Color(0xFFFFE0C2), BlendMode.src);
    canvas.drawRect(
      const Rect.fromLTWH(0, 300, 2048, 276),
      Paint()..color = const Color(0xFF9CC79A),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(2048, 576);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();

    // 캐릭터 생성 직후 서버가 이미 시작한 작업: 앱은 POST 없이 따라간다.
    var ready = false, posts = 0, polls = 0, downloads = 0;
    final api = ApiClient(
      baseUrl: 'https://api.test',
      session: Session(),
      client: MockClient((request) async {
        if (request.url.host == 'image.test') {
          downloads++;
          return http.Response.bytes(png!.buffer.asUint8List(), 200);
        }
        if (request.method == 'POST') posts++;
        polls++;
        return http.Response(
          jsonEncode(
            ready
                ? {
                    'status': 'succeeded',
                    for (final phase in ['day'])
                      phase: {
                        'assetId': '$phase-1',
                        'url': 'https://image.test/$phase',
                        'contentType': 'image/png',
                        'width': 2048,
                        'height': 576,
                      },
                  }
                : {'status': 'processing', 'pollAfterMs': 1000},
          ),
          200,
        );
      }),
    );
    final windows = ApiWindowViews(
      api,
      store: FileStore(folder),
      wait: (_) => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    final local = AppServices.local(characters: repository);
    var clock = DateTime(2026, 10, 31, 12);
    Widget house() => AppServicesScope(
      services: AppServices(
        characters: repository,
        profile: local.profile,
        orders: local.orders,
        generator: local.generator,
        chat: local.chat,
        motion: local.motion,
        windowViews: windows,
      ),
      child: MaterialApp(
        theme: buildBogleTheme(),
        home: FriendScreen(
          repository: repository,
          friend: friend,
          clock: () => clock,
        ),
      ),
    );
    final warm = windows.warm(friend);
    await tester.pumpWidget(house());
    await frames(tester, 2500);
    final pending = find.byKey(const ValueKey('house-window-pending'));
    expect(pending, findsOneWidget);
    expect(find.text(WindowPendingNotice.message), findsOneWidget);
    await binding.takeScreenshot('house-window-pending');

    ready = true;
    await frames(tester, 2500);
    expect(pending, findsNothing);
    final cached = await windows.load(friend);
    expect(cached, isNotNull);
    expect(cached!.night, isNull);
    await warm;
    expect(downloads, 1);
    await binding.takeScreenshot('house-window-ready');

    // 같은 PNG를 저녁·밤에도 쓰고 창밖에만 색상 보정을 적용한다.
    clock = DateTime(2026, 10, 31, 18);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(house());
    await frames(tester, 1500);
    await binding.takeScreenshot('house-window-evening');
    clock = DateTime(2026, 10, 31, 21);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(house());
    await frames(tester, 1500);
    final tint = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('house-window-tint')),
    );
    expect(
      (tint.decoration! as BoxDecoration).gradient!.colors,
      windowTint(DayTime.night),
    );
    expect((await windows.load(friend))!.day, cached.day);
    expect(downloads, 1);
    await binding.takeScreenshot('house-window-night');
    binding.reportData = {
      ...?binding.reportData,
      'noticeShown': true,
      'noticeGoneAfterReady': true,
      'generationRequests': posts,
      'polls': polls,
      'downloads': downloads,
      'dayOnly': true,
      'nightTintVerified': true,
    };
    expect(posts, 0);
    await tester.pumpWidget(const SizedBox());
    await folder.delete(recursive: true);
  });
}
