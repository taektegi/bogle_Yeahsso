import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/api_fixtures.dart';

/// The character service's API, as it describes itself. A copy of
/// `docs/openapi.json` from the backend repository
/// (quasiaward/bogle_backend_try), which checks that file against its own
/// code. When the service's API changes, copy the new file here: these
/// tests then say which of the app's pretend answers no longer match.
final _spec =
    jsonDecode(File('test/contract/openapi.json').readAsStringSync())
        as Map<String, dynamic>;

Map<String, dynamic> _schema(String name) =>
    ((_spec['components'] as Map)['schemas'] as Map)[name]
        as Map<String, dynamic>;

/// [value] has every field [schema] requires and none it doesn't know;
/// nested objects named by `$ref` are checked too.
void expectMatches(Object? value, String schema, {String at = r'$'}) {
  final s = _schema(schema);
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
      expectMatches(value, ref, at: '$at.$key');
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
    expectMatches(generationSucceeded(), 'GenerationOut');
    expectMatches(generationSucceededFace('pending'), 'GenerationOut');
    expectMatches(generationSucceededFace('unavailable'), 'GenerationOut');
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
    ]) {
      expect(paths, contains(path));
    }
  });
}
