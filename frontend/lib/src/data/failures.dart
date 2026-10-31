import 'api/api_client.dart';
import 'character_generation.dart';
import 'local_store.dart';

/// What to tell the child when a request failed: the service's own words
/// when it gave some (they are written to be shown), else [fallback].
String failureMessage(Object error, String fallback) => switch (error) {
  ApiException(:final message) when message.isNotEmpty => message,
  GenerationError(:final message) when message.isNotEmpty => message,
  StoreRecoveryException(:final message) => message,
  _ => fallback,
};
