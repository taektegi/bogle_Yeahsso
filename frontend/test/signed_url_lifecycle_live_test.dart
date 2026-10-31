import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bogle_app/src/data/api/api_client.dart';
import 'package:bogle_app/src/data/api/api_services.dart';
import 'package:bogle_app/src/data/api/device_art.dart';
import 'package:bogle_app/src/data/api/outbox.dart';
import 'package:bogle_app/src/data/api/synced_character_repository.dart';
import 'package:bogle_app/src/data/character_repository.dart';
import 'package:bogle_app/src/data/local_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

// 전용 Python 진단 프로그램이 만든 임시 계정만 사용한다. 토큰·서명 URL은 출력하지 않는다.
class _Session implements AuthSession {
  @override
  Future<String> accessToken() async =>
      Platform.environment['BOGLE_DIAG_ACCESS_TOKEN']!;
  @override
  Future<String> refresh() => accessToken();
}

class _Network extends http.BaseClient {
  final http.Client inner = http.Client();
  bool offline = false;
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests++;
    if (offline) throw const SocketException('진단용 오프라인');
    return inner.send(request);
  }

  @override
  void close() => inner.close();
}

Future<bool> _validPng(String path) async {
  final codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
  try {
    final frame = await codec.getNextFrame();
    final valid = frame.image.width == 256 && frame.image.height == 256;
    frame.image.dispose();
    return valid;
  } finally {
    codec.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final base = Platform.environment['BOGLE_DIAG_API_URL'];
  test(
    '실제 Storage 주소 만료 후 로컬 그림과 새 다운로드 확인',
    () async {
      // Flutter 테스트의 가짜 HTTP 응답 대신 실제 로컬 서버·Storage로 요청한다.
      HttpOverrides.global = null;
      final result = <String, Object?>{};
      var phase = 'configuration';
      final network = _Network();
      final root = await Directory.systemTemp.createTemp(
        'bogle-signed-url-device-',
      );
      final api = ApiClient(
        baseUrl: base!,
        session: _Session(),
        client: network,
      );
      final id = Platform.environment['BOGLE_DIAG_FRIEND_ID']!;
      final jobId = Platform.environment['BOGLE_DIAG_JOB_ID']!;
      final expected = await File(
        Platform.environment['BOGLE_DIAG_IMAGE_PATH']!,
      ).readAsBytes();

      SyncedCharacterRepository repository(FileStore store) =>
          SyncedCharacterRepository(
            api,
            local: InMemoryCharacterRepository(
              store: store,
              relocate: store.relocate,
            ),
            outbox: Outbox(api, store: store),
            art: DeviceArt(store.art),
          );

      void check(bool condition) {
        if (!condition) throw StateError(phase);
      }

      try {
        phase = 'first_download';
        final before = await api.get('/v1/characters/$id');
        final old = ImageRef.fromJson(before['art'] as Map<String, dynamic>);
        check(listEquals(await api.download(old.url), expected));
        final store = FileStore(Directory('${root.path}/original'));
        final repo = repository(store);
        check(await repo.pull() == 1);
        final friend = (await repo.fetchFriends()).singleWhere(
          (f) => f.id == id,
        );
        check(await _validPng(friend.assetPath));
        check(await _validPng(friend.thumbnail));
        result['initialDownloadAndPngDecode'] = true;

        phase = 'actual_expiration';
        // 운영 TTL은 바꾸지 않는다. 진단 서버의 이 실행만 짧은 TTL을 쓴다.
        await Future<void>.delayed(const Duration(seconds: 9));
        var expired = false;
        try {
          await api.download(old.url);
        } on ApiException catch (error) {
          expired = error.statusCode >= 400 && error.statusCode < 500;
          result['expiredUrlHttpStatus'] = error.statusCode;
        }
        check(expired && DateTime.now().toUtc().isAfter(old.expiresAt));
        result['oldUrlActuallyRejected'] = true;

        phase = 'offline_reload';
        network.offline = true;
        final count = network.requests;
        final reloaded = repository(
          FileStore(Directory('${root.path}/original')),
        );
        final kept = (await reloaded.fetchFriends()).singleWhere(
          (f) => f.id == id,
        );
        check(await _validPng(kept.assetPath));
        check(await _validPng(kept.thumbnail));
        check(listEquals(await File(kept.assetPath).readAsBytes(), expected));
        check(network.requests == count);
        final document = jsonEncode(await store.read('characters'));
        check(
          !document.contains('token=') && !document.contains('/object/sign/'),
        );
        result['expiredUrlOfflineReloadUsesLocalFiles'] = true;
        result['offlineReloadHttpRequests'] = network.requests - count;
        result['persistentFriendDoesNotStoreSignedUrl'] = true;
        network.offline = false;

        phase = 'fresh_url';
        final after = await api.get('/v1/characters/$id');
        final fresh = ImageRef.fromJson(after['art'] as Map<String, dynamic>);
        check(fresh.assetId == old.assetId && fresh.url != old.url);
        check(fresh.expiresAt.isAfter(old.expiresAt));
        check(listEquals(await api.download(fresh.url), expected));
        result['sameAssetGetsNewWorkingUrl'] = true;

        phase = 'empty_local_restore';
        final empty = repository(
          FileStore(Directory('${root.path}/second-device')),
        );
        check(await empty.pull() == 1);
        final restored = (await empty.fetchFriends()).singleWhere(
          (f) => f.id == id,
        );
        check(await _validPng(restored.assetPath));
        check(await _validPng(restored.thumbnail));
        result['emptyLocalRestoreAfterOldUrlExpiry'] = true;

        phase = 'resume_generation';
        final pendingStore = FileStore(Directory('${root.path}/pending'));
        await pendingStore.write('pending_generation', jobId);
        final generator = ApiCharacterGenerator(
          api,
          art: DeviceArt(pendingStore.art),
          store: pendingStore,
        );
        final pending = await generator.unfinished();
        check(pending != null);
        final generated = await pending!.result;
        check(generated.jobId == jobId && await _validPng(generated.assetPath));
        result['generationResumeGetsFreshUrl'] = true;
      } catch (error) {
        result['failedStage'] = phase;
        result['errorType'] = error.runtimeType.toString();
        if (error is ApiException) {
          result['httpStatus'] = error.statusCode;
          result['errorCode'] = error.code;
        }
      } finally {
        network.close();
        // 직접 만든 시스템 TEMP 하위 작업 폴더만 경로를 확인하고 정리한다.
        final parent = Directory.systemTemp.absolute.path;
        final absolute = root.absolute.path;
        if (!absolute.startsWith('$parent${Platform.pathSeparator}') ||
            !root.uri.pathSegments
                .where((s) => s.isNotEmpty)
                .last
                .startsWith('bogle-signed-url-device-')) {
          throw StateError('temporary_path_check');
        }
        await root.delete(recursive: true);
        await File(
          Platform.environment['BOGLE_DIAG_RESULT_PATH']!,
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(result));
      }
      expect(result.containsKey('failedStage'), isFalse, reason: '결과 JSON 확인');
    },
    skip: base == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
