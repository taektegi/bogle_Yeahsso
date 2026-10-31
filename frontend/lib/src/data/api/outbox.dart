import 'dart:async';
import 'package:flutter/foundation.dart';

import '../local_store.dart';
import 'api_client.dart';

/// Changes made on the iPad that the service still has to hear about. The
/// iPad keeps the friends and the profile; edits and deletions are saved
/// there at once and reach the service from here, in order, whenever it can
/// be reached. The list is kept in the [LocalStore], so a change made just
/// before the app closes (or offline) is sent on the next launch.
///
/// - Edits to one friend (or to the profile) are merged into one request.
/// - A deletion waits [Outbox.deleteCharacter]'s delay (the archive's undo)
///   and replaces that friend's pending edits; undoing removes it.
/// - A change the service refuses for good (a 4xx other than 408/429) is
///   dropped; a deletion of a friend it no longer has counts as done.
class Outbox {
  Outbox(
    this.api, {
    LocalStore? store,
    DateTime Function()? clock,
    this.retryAfter = const Duration(seconds: 30),
  }) : _store = store,
       _clock = clock ?? DateTime.now;

  final ApiClient api;
  final LocalStore? _store;
  final DateTime Function() _clock;

  /// How long to wait before trying again after the service couldn't be
  /// reached.
  final Duration retryAfter;

  static const _name = 'outbox';
  final List<_Change> _changes = [];
  Future<void>? _loading;
  Future<void> get _ready =>
      _loading ??= _load().catchError((Object error, StackTrace stack) {
        _loading = null;
        Error.throwWithStackTrace(error, stack);
      });
  Timer? _timer;

  /// Rejected edits remain visible as a user-facing sync notice.
  final notice = ValueNotifier<String?>(null);
  Future<void>? _sending;
  final _rejected = <Map<String, dynamic>>[];
  Future<List<Map<String, dynamic>>> get rejected async {
    await _ready;
    return [for (final item in _rejected) Map.of(item)];
  }

  Future<Set<String>> pendingFields(String? target) async {
    await _ready;
    return {
      for (final change in _changes)
        if (change.target == target) ...change.body.keys,
      for (final item in _rejected)
        if (item['target'] == target)
          ...(item['fields'] as Map).keys.cast<String>(),
    };
  }

  Future<void> _reject(_Change change, Iterable<String> fields) async {
    final values = {for (final field in fields) field: change.body[field]};
    if (values.isEmpty) return;
    _rejected.add({'target': change.target, 'fields': values});
    await _store?.write('sync_failures', _rejected);
  }

  Future<void> _load() async {
    final saved = await readDocument(
      _store,
      _name,
      (value) => [
        for (final row in value as List)
          _Change.fromJson((row as Map).cast()) ??
              (throw const FormatException('Invalid change')),
      ],
    );
    _changes
      ..clear()
      ..addAll(saved ?? const []);
    final rejected = await readDocument(
      _store,
      'sync_failures',
      (value) => [
        for (final row in value as List) Map<String, dynamic>.from(row as Map),
      ],
    );
    _rejected
      ..clear()
      ..addAll(rejected ?? const []);
    if (_rejected.isNotEmpty) {
      notice.value = '서버에 저장하지 못한 변경이 있어요. 내용을 확인해 주세요.';
    }
  }

  Future<void> _save() async {
    try {
      await _store?.write(_name, [for (final c in _changes) c.toJson()]);
    } catch (_) {
      notice.value = '변경을 기기에 저장하지 못했어요. 앱을 닫지 말고 다시 시도해 주세요.';
      rethrow;
    }
  }

  void _flushQuietly() => unawaited(
    flush().catchError((Object error) {
      notice.value = '변경을 저장하지 못했어요. 다시 시도해 주세요.';
    }),
  );

  /// Changes not yet sent, for tests and diagnostics.
  Future<int> get pending async {
    await _ready;
    return _changes.length;
  }

  /// Whether [friendId] is waiting to be deleted on the service.
  Future<bool> isLeaving(String friendId) async {
    await _ready;
    return _changes.any(
      (c) => c.kind == _Kind.deleteCharacter && c.target == friendId,
    );
  }

  Future<void> patchCharacter(String friendId, Map<String, Object?> fields) =>
      _merge(_Kind.patchCharacter, friendId, fields);

  Future<void> patchProfile(Map<String, Object?> fields) =>
      _merge(_Kind.patchProfile, null, fields);

  Future<void> _merge(
    _Kind kind,
    String? target,
    Map<String, Object?> fields,
  ) async {
    if (fields.isEmpty) return;
    await _ready;
    final index = _changes.indexWhere(
      (c) => c.kind == kind && c.target == target,
    );
    if (index < 0) {
      _changes.add(
        _Change(kind, target, Map.of(fields), _clock(), attempts: 0),
      );
    } else {
      _changes[index] = _changes[index].withBody({
        ..._changes[index].body,
        ...fields,
      });
    }
    await _save();
    for (final item in _rejected.where((r) => r['target'] == target)) {
      (item['fields'] as Map).removeWhere((key, _) => fields.containsKey(key));
    }
    _rejected.removeWhere((r) => (r['fields'] as Map).isEmpty);
    await _store?.write('sync_failures', _rejected);
    _flushQuietly();
  }

  Future<void> deleteCharacter(
    String friendId, {
    Duration delay = Duration.zero,
  }) async {
    await _ready;
    _changes.removeWhere((c) => c.target == friendId);
    _changes.add(
      _Change(
        _Kind.deleteCharacter,
        friendId,
        const {},
        _clock().add(delay),
        attempts: 0,
      ),
    );
    await _save();
    _schedule();
  }

  /// Undoes a deletion that hasn't gone out yet. False if it already has.
  Future<bool> cancelDelete(String friendId) async {
    await _ready;
    final before = _changes.length;
    _changes.removeWhere(
      (c) =>
          c.kind == _Kind.deleteCharacter &&
          c.target == friendId &&
          c.notBefore.isAfter(_clock()),
    );
    if (_changes.length == before) return false;
    await _save();
    return true;
  }

  /// Sends what is due now. Safe to call any time (on launch, on resume).
  Future<void> flush() => _sending ??= _send().whenComplete(() {
    _sending = null;
    _schedule();
  });

  Future<void> _send() async {
    await _ready;
    while (true) {
      final now = _clock();
      // A change waiting out its delay (a deletion's undo) isn't due yet;
      // one that failed before is tried again whenever the outbox is
      // flushed (launch, foreground, a new change): only the timer waits.
      final next = _changes.where((c) => !c.notBefore.isAfter(now)).firstOrNull;
      if (next == null) return;
      try {
        await _deliver(next);
        // Sent. If a newer edit was merged into it meanwhile, that one
        // (a different object) stays and goes out next.
        _changes.remove(next);
      } on ApiException catch (e) {
        if (e.statusCode == 422 && next.kind != _Kind.deleteCharacter) {
          final bad = e.fieldErrors.keys
              .map((key) => key.split('.').first)
              .where(next.body.containsKey)
              .toSet();
          final index = _changes.indexWhere(
            (c) => c.kind == next.kind && c.target == next.target,
          );
          if (bad.isNotEmpty && index >= 0) {
            await _reject(next, bad);
            final current = _changes[index];
            final remaining = Map<String, Object?>.of(current.body);
            for (final field in bad) {
              // Never remove a newer edit because an older request failed.
              if (remaining[field] == next.body[field]) remaining.remove(field);
            }
            if (remaining.isEmpty) {
              _changes.removeAt(index);
            } else {
              _changes[index] = current.withBody(remaining);
            }
            notice.value =
                '일부 변경을 서버에 저장하지 못했어요. 입력 내용을 확인해 주세요. 다른 변경은 계속 저장해요.';
            await _save();
            continue;
          }
        }
        final done = next.kind == _Kind.deleteCharacter && e.statusCode == 404;
        final refused =
            e.statusCode >= 400 &&
            e.statusCode < 500 &&
            e.statusCode != 401 &&
            e.statusCode != 403 &&
            e.statusCode != 408 &&
            e.statusCode != 429 &&
            !e.retryable;
        if (done || refused) {
          _changes.remove(next);
          if (!done) await _reject(next, next.body.keys);
          if (!done) notice.value = '일부 변경을 서버에 저장하지 못했어요. 입력 내용을 다시 확인해 주세요.';
        } else {
          // The service can't be reached: try again later, keeping order.
          // The change may have been merged with a newer edit meanwhile:
          // mark the one in the list now, not the copy that was sent.
          final index = _changes.indexWhere(
            (c) => c.kind == next.kind && c.target == next.target,
          );
          if (index >= 0) {
            _changes[index] = _changes[index].retryAt(
              _clock().add(e.retryAfter ?? retryAfter),
            );
          }
          await _save();
          return;
        }
      }
      await _save();
    }
  }

  Future<void> _deliver(_Change change) => switch (change.kind) {
    _Kind.patchCharacter => api.patch(
      '/v1/characters/${change.target}',
      change.body,
    ),
    _Kind.patchProfile => api.patch('/v1/me', change.body),
    _Kind.deleteCharacter => api.delete('/v1/characters/${change.target}'),
  };

  void _schedule() {
    _timer?.cancel();
    if (_changes.isEmpty) return;
    final soonest = _changes
        .map((c) => c.due)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final wait = soonest.difference(_clock());
    _timer = Timer(wait.isNegative ? Duration.zero : wait, () {
      _flushQuietly();
    });
  }

  /// Stops the timer (tests, or the app going away).
  void dispose() => _timer?.cancel();
}

enum _Kind { patchCharacter, patchProfile, deleteCharacter }

class _Change {
  const _Change(
    this.kind,
    this.target,
    this.body,
    this.notBefore, {
    required this.attempts,
    this.retry,
  });

  final _Kind kind;
  final String? target;
  final Map<String, Object?> body;

  /// Not sent before this (a deletion's undo window).
  final DateTime notBefore;

  /// After a failure, when the timer tries again on its own.
  final DateTime? retry;
  final int attempts;

  DateTime get due =>
      retry != null && retry!.isAfter(notBefore) ? retry! : notBefore;

  _Change withBody(Map<String, Object?> body) =>
      _Change(kind, target, body, notBefore, attempts: attempts, retry: retry);

  _Change retryAt(DateTime at) =>
      _Change(kind, target, body, notBefore, attempts: attempts + 1, retry: at);

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'target': target,
    'body': body,
    'notBefore': notBefore.toIso8601String(),
    'retry': retry?.toIso8601String(),
    'attempts': attempts,
  };

  static _Change? fromJson(Map<String, Object?> json) {
    final kind = _Kind.values.asNameMap()[json['kind']];
    final at = DateTime.tryParse(json['notBefore'] as String? ?? '');
    if (kind == null || at == null) return null;
    return _Change(
      kind,
      json['target'] as String?,
      (json['body'] as Map? ?? const {}).cast(),
      at,
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      retry: DateTime.tryParse(json['retry'] as String? ?? ''),
    );
  }
}
