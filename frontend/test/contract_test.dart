import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/api_fixtures.dart';

/// 개인 서버와 팀 서버 계약을 분리한다. 서로 다른 서버의 필드를 합쳐
/// 실제로 존재하지 않는 계약을 만들지 않는다.
final _spec =
    jsonDecode(File('test/contract/openapi.json').readAsStringSync())
        as Map<String, dynamic>;

final _teamSpec =
    jsonDecode(File('test/contract/team_openapi.json').readAsStringSync())
        as Map<String, dynamic>;

Map<String, dynamic> _schema(String name, {Map<String, dynamic>? spec}) =>
    (((spec ?? _spec)['components'] as Map)['schemas'] as Map)[name]
        as Map<String, dynamic>;

/// [value] has every field [schema] requires and none it doesn't know;
/// nested objects named by `$ref` are checked too.
void expectMatches(
  Object? value,
  String schema, {
  String at = r'$',
  Map<String, dynamic>? spec,
}) {
  final s = _schema(schema, spec: spec);
  expect(value, isA<Map>(), reason: '$at should be a $schema');
  final map = (value! as Map).cast<String, Object?>();
  final properties = (s['properties'] as Map).cast<String, Object?>();
  for (final field in (s['required'] as List? ?? const []).cast<String>()) {
    expect(map.containsKey(field), isTrue, reason: '$at.$field ($schema)');
  }
  for (final MapEntry(:key, :value) in map.entries) {
    expect(
      properties.containsKey(key),
      isTrue,
      reason: '$at.$key is not in $schema',
    );
    final ref = _refOf(properties[key]);
    if (ref != null && value != null) {
      expectMatches(value, ref, at: '$at.$key', spec: spec);
    }
  }
}

/// The schema a property points to, directly or as `X | null`.
String? _refOf(Object? property) {
  if (property is! Map) return null;
  if (property[r'$ref'] case final String ref) return ref.split('/').last;
  for (final option in property['anyOf'] as List? ?? const []) {
    if (option case {r'$ref': final String ref}) return ref.split('/').last;
  }
  return null;
}

void main() {
  test('a friend is a CharacterOut', () {
    expectMatches(serverFriend(), 'CharacterOut');
  });

  test('every state of a generation is a GenerationOut', () {
    expectMatches(generationWaiting('queued'), 'GenerationOut');
    final personal = Map<String, dynamic>.of(generationSucceeded())
      ..remove('faceStatus');
    expectMatches(personal, 'GenerationOut');
    expectMatches(generationSucceeded(), 'GenerationOut', spec: _teamSpec);
    expectMatches(
      generationSucceededFace('pending'),
      'GenerationOut',
      spec: _teamSpec,
    );
    expectMatches(
      generationSucceededFace('unavailable'),
      'GenerationOut',
      spec: _teamSpec,
    );
    expectMatches(
      generationFailed('generation_rejected', retryable: false),
      'GenerationOut',
    );
  });

  test('개인 백엔드는 앱 자체 모션 사용을 안내한다', () {
    expectMatches({
      'status': 'unsupported',
      'reason': 'client_animation',
      'clips': {},
    }, 'MotionOut');
  });

  test('chat answers are a MessagePairOut', () {
    expectMatches({
      'userMessage': message('user', '안녕'),
      'assistantMessage': message('assistant', '반가워요!'),
    }, 'MessagePairOut');
  });

  test('the profile is a ProfileOut', () {
    expectMatches(me(), 'ProfileOut');
  });

  test('프로필 확장 필드와 창문 배경 상태가 현재 서버 계약에 있다', () {
    final fields = _schema('ProfileOut')['properties'] as Map;
    expect(
      fields.keys,
      containsAll(['bio', 'interests', 'profileColor', 'avatarCharacterId']),
    );
    for (final status in [
      'missing',
      'queued',
      'processing',
      'succeeded',
      'failed',
      'cancelled',
    ]) {
      expectMatches({
        'status': status,
        'jobId': null,
        'readyJobId': null,
        'day': null,
        'night': null,
        'error': null,
        'pollAfterMs': 2000,
      }, 'WindowOut');
    }
  });

  test('every path the app calls is one the service has', () {
    final paths = (_spec['paths'] as Map).keys.toSet();
    for (final path in const [
      '/v1/assets',
      '/v1/generations',
      '/v1/generations/{job_id}',
      '/v1/generations/{job_id}/cancel',
      '/v1/characters',
      '/v1/characters/{character_id}',
      '/v1/characters/{character_id}/messages',
      '/v1/characters/{character_id}/motion',
      '/v1/me',
      '/v1/characters/{character_id}/window-view',
    ]) {
      expect(paths, contains(path));
    }
  });
}
