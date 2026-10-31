import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Where the service is and who the app signs in as, given at build time:
///
/// ```sh
/// flutter run --dart-define=BOGLE_API_URL=https://api.example.com \
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=... \
///   --dart-define=BOGLE_ACCOUNT_EMAIL=demo@example.com \
///   --dart-define=BOGLE_ACCOUNT_PASSWORD=...
/// ```
///
/// Without `BOGLE_API_URL` the app keeps everything on the device
/// ([ApiConfig.fromEnvironment] is null).
class ApiConfig {
  const ApiConfig({
    required this.apiUrl,
    required this.supabaseUrl,
    required this.anonKey,
    required this.email,
    required this.password,
  });

  final String apiUrl;
  final String supabaseUrl;
  final String anonKey;

  /// The demo account the app signs in with (there is no sign-in screen).
  final String email;
  final String password;

  static ApiConfig? fromEnvironment() {
    const api = String.fromEnvironment('BOGLE_API_URL');
    if (api.isEmpty) return null;
    return const ApiConfig(
      apiUrl: api,
      supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
      anonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
      email: String.fromEnvironment('BOGLE_ACCOUNT_EMAIL'),
      password: String.fromEnvironment('BOGLE_ACCOUNT_PASSWORD'),
    );
  }
}

/// A failed request, in the service's error shape (`error.code`,
/// `message`, `retryable`, `fieldErrors`). [message] is Korean and can be
/// shown as it is.
class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.retryable = false,
    this.fieldErrors = const {},
    this.retryAfter,
  });

  /// 0 when the service couldn't be reached at all.
  final int statusCode;
  final String code;
  final String message;
  final bool retryable;
  final Map<String, String> fieldErrors;
  final Duration? retryAfter;

  static const offline = ApiException(
    statusCode: 0,
    code: 'offline',
    message: '인터넷 연결을 확인하고 다시 시도해 주세요.',
    retryable: true,
  );

  @override
  String toString() => 'ApiException($statusCode $code)';
}

/// The signed-in session's access token.
abstract interface class AuthSession {
  Future<String> accessToken();

  /// After a 401: a fresh token, signing in again if it must.
  Future<String> refresh();
}

/// Signs in to Supabase Auth with the demo account's email and password
/// (REST, no SDK) and refreshes with the refresh token. Tokens live only in
/// memory: a relaunch signs in again.
class SupabasePasswordSession implements AuthSession {
  SupabasePasswordSession(this.config, {http.Client? client})
    : _client = client ?? http.Client();
  final ApiConfig config;
  final http.Client _client;
  String? _access;
  String? _refresh;
  DateTime _expires = DateTime.fromMillisecondsSinceEpoch(0);
  Future<String>? _pending;

  @override
  Future<String> accessToken() {
    final token = _access;
    if (token != null &&
        DateTime.now().isBefore(
          _expires.subtract(const Duration(minutes: 1)),
        )) {
      return Future.value(token);
    }
    return refresh();
  }

  @override
  Future<String> refresh() => _pending ??= _renew().whenComplete(() {
    _pending = null;
  });

  Future<String> _renew() async {
    if (_refresh case final refresh?) {
      try {
        return await _token('refresh_token', {'refresh_token': refresh});
      } on ApiException {
        _refresh = null; // fall back to signing in again
      }
    }
    return _token('password', {
      'email': config.email,
      'password': config.password,
    });
  }

  Future<String> _token(String grant, Map<String, String> body) async {
    final uri = Uri.parse(
      '${config.supabaseUrl}/auth/v1/token',
    ).replace(queryParameters: {'grant_type': grant});
    final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {
              'apikey': config.anonKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
    } on Exception {
      throw ApiException.offline;
    }
    if (response.statusCode != 200) {
      throw ApiException(
        statusCode: response.statusCode,
        code: 'unauthenticated',
        message: '로그인하지 못했어요.',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    _access = json['access_token'] as String;
    _refresh = json['refresh_token'] as String?;
    _expires = DateTime.now().add(
      Duration(seconds: (json['expires_in'] as num?)?.toInt() ?? 3600),
    );
    return _access!;
  }
}

/// A file sent as multipart form data.
class UploadFile {
  const UploadFile(this.field, this.bytes, this.filename, this.contentType);
  final String field;
  final Uint8List bytes;
  final String filename;
  final String contentType;
}

/// Talks JSON to the service: signs every request, retries once with a
/// fresh token after a 401, and turns the service's errors into
/// [ApiException]s.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.session,
    http.Client? client,
    math.Random? random,
    Future<void> Function(Duration)? wait,
    Duration Function()? utcOffset,
  }) : _client = client ?? http.Client(),
       _random = random ?? math.Random.secure(),
       _wait = wait ?? Future<void>.delayed,
       _utcOffset = utcOffset ?? (() => DateTime.now().timeZoneOffset);

  final String baseUrl;
  final AuthSession session;
  final http.Client _client;
  final math.Random _random;
  final Future<void> Function(Duration) _wait;
  final Duration Function() _utcOffset;

  /// The longest a request waits before its one retry.
  static const _longestRetryWait = Duration(seconds: 5);

  /// For `Idempotency-Key` and `clientMessageId`: a UUID v4.
  String newKey() {
    final b = List<int>.generate(16, (_) => _random.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String hex(int from, int to) => [
      for (final x in b.sublist(from, to)) x.toRadixString(16).padLeft(2, '0'),
    ].join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
  }) async => _json(await send('GET', path, query: query));

  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    String? idempotencyKey,
    Duration timeout = const Duration(seconds: 20),
  }) async => _json(
    await send(
      'POST',
      path,
      body: body,
      idempotencyKey: idempotencyKey,
      timeout: timeout,
    ),
  );

  Future<Map<String, dynamic>> patch(String path, Object body) async =>
      _json(await send('PATCH', path, body: body));

  Future<void> delete(String path) async => send('DELETE', path);

  Future<Map<String, dynamic>> upload(String path, UploadFile file) async =>
      _json(
        await send(
          'POST',
          path,
          file: file,
          timeout: const Duration(seconds: 60),
        ),
      );

  /// Sends a request. A request that is safe to repeat (a read, or one
  /// with an idempotency key) is tried once more after a passing problem
  /// (the service busy or briefly down, the connection dropped), after the
  /// wait the service asks for.
  Future<http.Response> send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    UploadFile? file,
    String? idempotencyKey,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final repeatable = method == 'GET' || idempotencyKey != null;
    try {
      return await _signed(
        method,
        path,
        query: query,
        body: body,
        file: file,
        idempotencyKey: idempotencyKey,
        timeout: timeout,
      );
    } on ApiException catch (e) {
      if (!repeatable || !e.retryable) rethrow;
      final asked = e.retryAfter ?? const Duration(seconds: 1);
      if (asked > _longestRetryWait) rethrow; // too long to wait here
      await _wait(asked);
      return _signed(
        method,
        path,
        query: query,
        body: body,
        file: file,
        idempotencyKey: idempotencyKey,
        timeout: timeout,
      );
    }
  }

  /// A picture or clip by its (signed) URL, without the app's token.
  Future<Uint8List> download(String url) async {
    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        throw ApiException(
          statusCode: response.statusCode,
          code: 'download_failed',
          message: '그림을 받아 오지 못했어요.',
          retryable: response.statusCode >= 500,
        );
      }
      return response.bodyBytes;
    } on ApiException {
      rethrow;
    } on Exception {
      throw ApiException.offline;
    }
  }

  Future<http.Response> _signed(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    UploadFile? file,
    String? idempotencyKey,
    required Duration timeout,
  }) async {
    var token = await session.accessToken();
    for (var attempt = 0; ; attempt++) {
      final response = await _once(
        method,
        path,
        token: token,
        query: query,
        body: body,
        file: file,
        idempotencyKey: idempotencyKey,
        timeout: timeout,
      );
      if (response.statusCode == 401 && attempt == 0) {
        token = await session.refresh();
        continue;
      }
      if (response.statusCode >= 400) throw _error(response);
      return response;
    }
  }

  Future<http.Response> _once(
    String method,
    String path, {
    required String token,
    Map<String, String>? query,
    Object? body,
    UploadFile? file,
    String? idempotencyKey,
    required Duration timeout,
  }) async {
    final uri = Uri.parse(
      '$baseUrl$path',
    ).replace(queryParameters: query?.isEmpty ?? true ? null : query);
    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      // 요청마다 갱신해 기기 시간대 변경도 반영한다. 시각 자체는 서버가 판단한다.
      'X-Bogle-Utc-Offset-Minutes': '${_utcOffset().inMinutes}',
      'Idempotency-Key': ?idempotencyKey,
    };
    final http.BaseRequest request;
    if (file != null) {
      request = http.MultipartRequest(method, uri)
        ..files.add(
          http.MultipartFile.fromBytes(
            file.field,
            file.bytes,
            filename: file.filename,
          ),
        );
    } else {
      final plain = http.Request(method, uri);
      if (body != null) {
        headers['Content-Type'] = 'application/json';
        plain.body = jsonEncode(body);
      }
      request = plain;
    }
    request.headers.addAll(headers);
    try {
      final streamed = await _client.send(request).timeout(timeout);
      return await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw const ApiException(
        statusCode: 0,
        code: 'timeout',
        message: '응답이 늦어요. 잠시 후 다시 시도해 주세요.',
        retryable: true,
      );
    } on http.ClientException {
      throw ApiException.offline;
    } on Exception {
      throw ApiException.offline;
    }
  }

  static Map<String, dynamic> _json(http.Response response) {
    if (response.body.isEmpty) return const {};
    return (jsonDecode(utf8.decode(response.bodyBytes)) as Map)
        .cast<String, dynamic>();
  }

  static ApiException _error(http.Response response) {
    Map<String, dynamic> error = const {};
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body case {'error': final Map<String, dynamic> e}) error = e;
    } on FormatException {
      // Not the service's error shape (a proxy, say).
    }
    final retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
    return ApiException(
      statusCode: response.statusCode,
      code: error['code'] as String? ?? 'http_${response.statusCode}',
      message: error['message'] as String? ?? '잠시 후 다시 시도해 주세요.',
      retryable:
          error['retryable'] as bool? ??
          (response.statusCode >= 500 || response.statusCode == 429),
      fieldErrors: {
        for (final MapEntry(:key, :value)
            in (error['fieldErrors'] as Map? ?? const {}).entries)
          '$key': '$value',
      },
      retryAfter: retryAfter == null ? null : Duration(seconds: retryAfter),
    );
  }
}

/// A signed image URL and when it stops working.
class ImageRef {
  const ImageRef({
    required this.assetId,
    required this.url,
    required this.expiresAt,
    required this.width,
    required this.height,
  });

  factory ImageRef.fromJson(Map<String, dynamic> json) => ImageRef(
    assetId: json['assetId'] as String,
    url: json['url'] as String,
    expiresAt: DateTime.parse(json['expiresAt'] as String),
    width: (json['width'] as num).toInt(),
    height: (json['height'] as num).toInt(),
  );

  final String assetId;
  final String url;
  final DateTime expiresAt;
  final int width;
  final int height;
}
