import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bogle_app/src/data/api/api_client.dart';
import 'package:bogle_app/src/data/api/api_window_views.dart';
import 'package:bogle_app/src/data/app_services.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/local_store.dart';
import 'package:bogle_app/src/data/order_catalog.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:bogle_app/src/screens/friend_screen.dart';
import 'package:bogle_app/src/screens/house/house_widgets.dart';
import 'package:bogle_app/src/screens/order/doll_options.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:bogle_app/src/widgets/character_preview_surface.dart';
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

  testWidgets('iPad: 민들레·생성 친구 대비와 낮밤 배경 캐시', (tester) async {
    final repository = InMemoryCharacterRepository();
    final friends = await repository.fetchFriends();
    final report = <String, Object?>{};
    for (final id in ['mindle', 'mungle', 'ppojik']) {
      final friend = friends.firstWhere((f) => f.id == id);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildBogleTheme(),
          home: Scaffold(
            body: SafeArea(
              child: Center(
                child: SizedBox(
                  width: 1108,
                  height: 640,
                  child: DollOptions(
                    friend: friend,
                    order: const DollOrder(),
                    onChanged: (_) {},
                    onOrder: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await frames(tester, 1000);
      expect(
        find.byKey(const ValueKey('character-preview-material')),
        findsOneWidget,
      );
      final look = await artLookOf(friend.assetPath);
      final color = CharacterPreviewSurface.backdrop(
        Color(friend.accentHex),
        look,
      );
      report['$id-whiteContrast'] = 1.05 / (color.computeLuminance() + .05);
      await binding.takeScreenshot('order-glass-$id');
    }
    final folder = await Directory.systemTemp.createTemp('bogle-window-test-');
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(const Color(0xFFC9DDF0), BlendMode.src);
    canvas.drawRect(
      const Rect.fromLTWH(0, 300, 2048, 276),
      Paint()..color = const Color(0xFF8CAD9D),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(2048, 576);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    const id = '01234567-0123-4567-89ab-012345678901';
    final original = friends.firstWhere((f) => f.id == 'mindle');
    final generated = CharacterFriend(
      id: id,
      name: '새 민들레',
      personality: original.personality,
      favoriteThings: [],
      speechStyle: original.speechStyle,
      assetPath: original.assetPath,
      accentHex: original.accentHex,
    );
    await repository.saveFriend(generated);
    var posts = 0, gets = 0;
    final api = ApiClient(
      baseUrl: 'https://api.test',
      session: Session(),
      client: MockClient((request) async {
        if (request.url.host == 'image.test') {
          return http.Response.bytes(png!.buffer.asUint8List(), 200);
        }
        if (request.method == 'POST') {
          posts++;
          return http.Response('{"status":"queued"}', 202);
        }
        gets++;
        final response = gets == 1
            ? {'status': 'missing'}
            : {
                'status': 'succeeded',
                for (final phase in ['day', 'night'])
                  phase: {
                    'assetId': '$phase-1',
                    'url': 'https://image.test/$phase',
                    'contentType': 'image/png',
                    'width': 2048,
                    'height': 576,
                  },
              };
        return http.Response(jsonEncode(response), 200);
      }),
    );
    final windows = ApiWindowViews(
      api,
      store: FileStore(folder),
      wait: (_) async {},
    );
    final services = AppServices.local(characters: repository);
    await tester.pumpWidget(
      AppServicesScope(
        services: AppServices(
          characters: repository,
          profile: services.profile,
          orders: services.orders,
          generator: services.generator,
          chat: services.chat,
          motion: services.motion,
          windowViews: windows,
        ),
        child: MaterialApp(
          theme: buildBogleTheme(),
          home: FriendScreen(repository: repository, friend: generated),
        ),
      ),
    );
    await frames(tester, 1800);
    expect(posts, 1);
    expect(find.byKey(const ValueKey('house-window-action')), findsOneWidget);
    final cached = await windows.load(generated);
    expect(cached, isNotNull);
    expect(await File(cached!.day).exists(), true);
    report['pairCached'] = true;
    report['generationRequests'] = posts;
    await binding.takeScreenshot('house-generated-window');
    await tester.pumpWidget(const SizedBox());
    await folder.delete(recursive: true);
    binding.reportData = {...?binding.reportData, ...report};
  });
}
