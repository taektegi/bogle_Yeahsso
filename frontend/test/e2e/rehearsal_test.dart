// A rehearsal against a real service: the app's own API code, talking to a
// running server and Supabase. Skipped unless BOGLE_E2E_API_URL is set:
//
//   BOGLE_E2E_API_URL=http://127.0.0.1:8000 \
//   BOGLE_E2E_SUPABASE_URL=http://127.0.0.1:54321 \
//   BOGLE_E2E_ANON_KEY=<anon key> \
//   BOGLE_E2E_EMAIL=demo@bogle.test BOGLE_E2E_PASSWORD=<password> \
//   flutter test test/e2e/rehearsal_test.dart
//
// It makes a friend from a drawing, edits it, chats, sets the profile,
// installs "afresh" to bring it back, and deletes it.
@Tags(['e2e'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:bogle_app/src/data/api/api_client.dart';
import 'package:bogle_app/src/data/app_services.dart';
import 'package:bogle_app/src/data/character_generation.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/local_store.dart';
import 'package:bogle_app/src/models/character_friend.dart';
import 'package:bogle_app/src/screens/house/face_map.dart';
import 'package:flutter_test/flutter_test.dart';

final _env = Platform.environment;
final _apiUrl = _env['BOGLE_E2E_API_URL'];

ApiConfig get _config => ApiConfig(
  apiUrl: _apiUrl!,
  supabaseUrl: _env['BOGLE_E2E_SUPABASE_URL']!,
  anonKey: _env['BOGLE_E2E_ANON_KEY']!,
  email: _env['BOGLE_E2E_EMAIL']!,
  password: _env['BOGLE_E2E_PASSWORD']!,
);

Future<FileStore> _freshInstall() async {
  final folder = await Directory.systemTemp.createTemp('bogle_e2e_');
  addTearDown(() => folder.delete(recursive: true));
  return FileStore(folder);
}

Future<GenerationInput> _drawing() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawCircle(
    const ui.Offset(300, 220),
    140,
    ui.Paint()..color = const ui.Color(0xFF8BA2FF),
  );
  for (final x in [250.0, 350.0]) {
    canvas.drawCircle(
      ui.Offset(x, 190),
      18,
      ui.Paint()..color = const ui.Color(0xFF202030),
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(600, 440);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  return GenerationInput(
    png!.buffer.asUint8List(),
    source: GenerationSource.drawing,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a friend goes from a drawing to the service and back to a fresh iPad',
    () async {
      // The test binding answers every HTTP request with 400; this one talks
      // to a real server.
      HttpOverrides.global = null;
      final first = AppServices.remote(_config, store: await _freshInstall());
      await first.sync!.start();
      final api = ApiClient(
        baseUrl: _config.apiUrl,
        session: SupabasePasswordSession(_config),
      );

      // Draw → upload → generate: the friend's pictures land on the iPad.
      final art = await first.generator.start(await _drawing()).result;
      expect(art.jobId, isNotNull);
      expect(File(art.assetPath).existsSync(), isTrue);
      expect(File(art.thumbnailPath!).existsSync(), isTrue);
      final face = await faceMapFor(art.assetPath);
      expect(face?.eyes, hasLength(2), reason: 'face map from the server');
      expect(face?.mouth, isNotNull);

      // Setup → the friend, on the service and on the iPad.
      final friend = await first.characters.createFriend(
        NewFriend(
          name: '리허설',
          personality: '엉뚱해요',
          favoriteThings: const ['구름', '사과'],
          speechStyle: '해요체',
          assetPath: art.assetPath,
          thumbnailPath: art.thumbnailPath,
          accentHex: art.accentHex,
          generationJobId: art.jobId,
        ),
      );
      await first.generator.finished(art.jobId!);
      expect(
        (await first.characters.fetchFriends()).map((f) => f.id),
        contains(friend.id),
      );

      // An edit on the iPad reaches the service through the outbox.
      await first.characters.saveFriend(
        friend.copyWith(
          name: '리허설2',
          sleep: const SleepSchedule(bedtime: 0, wakeTime: 0),
        ),
      );
      await first.sync!.resumed();
      final onService = await api.get('/v1/characters/${friend.id}');
      expect(onService['name'], '리허설2');
      expect(onService['bedtime'], 0);

      // Chat: the service answers (scripted without an AI key) and keeps it.
      final reply = await first.chat.replyTo(friend, '오늘 뭐 했어?');
      expect(reply, isNotNull);
      final past = await first.chat.history(friend);
      expect(past.first, (mine: true, text: '오늘 뭐 했어?'));

      // Motion without a motion server: the app's own motions.
      expect(await first.motion.clipsFor(friend), isNull);

      // The profile, with the new friend as avatar.
      final profile = await first.profile.fetchProfile();
      await first.profile.saveProfile(
        profile.copyWith(nickname: '리허설맘', avatar: art.assetPath),
      );
      await first.sync!.resumed();
      final me = await api.get('/v1/me');
      expect(me['nickname'], '리허설맘');
      expect(me['avatarCharacterId'], friend.id);

      // A fresh install brings the friend back, pictures and face included.
      final second = AppServices.remote(_config, store: await _freshInstall());
      await second.sync!.start();
      final back = (await second.characters.fetchFriends()).firstWhere(
        (f) => f.id == friend.id,
      );
      expect(back.name, '리허설2');
      expect(File(back.assetPath).existsSync(), isTrue);
      expect((await faceMapFor(back.assetPath))?.mouth, isNotNull);
      expect((await second.profile.fetchProfile()).nickname, '리허설맘');

      // Deleting it reaches the service once the undo has run out.
      await second.characters.deleteFriend(friend.id);
      await Future<void>.delayed(const Duration(seconds: 11));
      await expectLater(
        api.get('/v1/characters/${friend.id}'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
      );
      // …and was accepted the first time, not left to retry after an error.
      expect(await second.sync!.outbox.pending, 0);
      expect(await first.sync!.outbox.pending, 0);
    },
    skip: _apiUrl == null ? 'set BOGLE_E2E_API_URL to rehearse' : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
