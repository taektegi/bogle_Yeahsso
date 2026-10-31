import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bogle_app/src/data/api/api_client.dart';
import 'package:bogle_app/src/data/api/api_window_views.dart';
import 'package:bogle_app/src/data/app_services.dart';
import 'package:bogle_app/src/data/local_store.dart';
import 'package:bogle_app/src/data/window_view.dart';
import 'package:bogle_app/src/data/window_view_service.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:bogle_app/src/screens/friend_screen.dart';
import 'package:bogle_app/src/screens/house/house_widgets.dart';
import 'package:bogle_app/src/theme/bogle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Session implements AuthSession {
  @override
  Future<String> accessToken() async => 'mock';
  @override
  Future<String> refresh() => accessToken();
}

/// Scenery the service is still making until [done] completes.
class _Pending implements WindowViewService {
  final done = Completer<WindowView?>();
  @override
  bool supports(CharacterFriend friend) => true;
  @override
  Future<WindowView?> load(
    CharacterFriend friend, {
    bool regenerate = false,
    bool Function()? active,
    void Function()? onWaiting,
  }) {
    onWaiting?.call();
    return done.future;
  }
}

void main() {
  const id = '01234567-0123-4567-89ab-012345678901';
  const friend = CharacterFriend(
    id: id,
    name: '민들레',
    personality: '밝아요',
    favoriteThings: [],
    speechStyle: '반말',
    assetPath: 'unused.png',
    accentHex: 0xFFCFDAEC,
  );

  Future<int> waitingCalls(List<String> statuses) async {
    final folder = await Directory.systemTemp.createTemp('window-waiting-');
    addTearDown(() => folder.delete(recursive: true));
    var poll = 0;
    final service = ApiWindowViews(
      ApiClient(
        baseUrl: 'https://api.test',
        session: _Session(),
        client: MockClient((request) async {
          final status = statuses[poll < statuses.length ? poll : 0];
          poll++;
          return http.Response(
            jsonEncode({
              'status': status,
              if (status == 'failed') 'error': {'message': 'retry'},
            }),
            200,
          );
        }),
      ),
      store: FileStore(folder),
      pollLimit: statuses.length,
      wait: (_) async {},
    );
    var calls = 0;
    try {
      await service.load(friend, onWaiting: () => calls++);
    } on ApiException {
      // The last status ends the wait either way.
    }
    return calls;
  }

  test('says once that the scenery is still being made', () async {
    expect(await waitingCalls(['queued', 'processing', 'failed']), 1);
  });

  test('a finished or failed job is never reported as waiting', () async {
    expect(await waitingCalls(['failed']), 0);
  });

  testWidgets('the house tells the child while the default view stands in', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1194, 834);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final local = AppServices.local();
    final windows = _Pending();
    final services = AppServices(
      characters: local.characters,
      profile: local.profile,
      orders: local.orders,
      generator: local.generator,
      chat: local.chat,
      motion: local.motion,
      windowViews: windows,
    );
    final first = (await local.characters.fetchFriends()).first;
    await tester.pumpWidget(
      AppServicesScope(
        services: services,
        child: MaterialApp(
          theme: buildBogleTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: FriendScreen(
            repository: local.characters,
            friend: first,
            clock: () => DateTime(2026, 10, 31, 14),
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('house-window-pending')), findsOneWidget);
    expect(find.text(WindowPendingNotice.message), findsOneWidget);

    windows.done.complete(null);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('house-window-pending')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
