import 'package:dio/dio.dart';
import '../contracts.dart';

class ServiceFailure implements Exception {
  const ServiceFailure(
    this.code,
    this.message, {
    this.status,
    this.retryable = false,
    this.receipt,
  });
  final String code, message;
  final int? status;
  final bool retryable;
  final Json? receipt;
  @override
  String toString() => message;
}

String normalizeServerAddress(
  String value, {
  bool allowLocalHttp = const bool.fromEnvironment('ALLOW_INSECURE_LOCAL'),
}) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const FormatException(
      'Enter the Field Assist server address without credentials or query parameters.',
    );
  }
  final host = uri.host.toLowerCase(),
      parts = host.split('.').map(int.tryParse).toList();
  final privateIp =
      parts.length == 4 &&
      parts.every((p) => p != null && p >= 0 && p <= 255) &&
      (parts[0] == 10 ||
          parts[0] == 192 && parts[1] == 168 ||
          parts[0] == 172 && parts[1]! >= 16 && parts[1]! <= 31);
  final local =
      host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '::1' ||
      host.endsWith('.local') ||
      privateIp;
  if (uri.scheme != 'https' &&
      !(allowLocalHttp && uri.scheme == 'http' && local)) {
    throw const FormatException(
      'Use HTTPS. This demo build also allows a private local Wi-Fi address.',
    );
  }
  var path = uri.path;
  if (path.isEmpty || path == '/') {
    path = '/api/v1/';
  } else if (path == '/api/v1') {
    path = '/api/v1/';
  } else if (!path.endsWith('/api/v1/')) {
    throw const FormatException(
      'Use the Field Assist server address, or its /api/v1/ address.',
    );
  }
  return uri.replace(path: path).toString();
}

class ApiClient {
  ApiClient({String? baseUrl})
    : dio = Dio(
        BaseOptions(
          baseUrl:
              baseUrl ??
              const String.fromEnvironment(
                'API_BASE_URL',
                defaultValue: 'https://localhost:3000/api/v1/',
              ),
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 30),
          headers: {'Accept': 'application/json'},
        ),
      ) {
    final uri = Uri.parse(dio.options.baseUrl);
    if (uri.scheme != 'https' &&
        !const bool.fromEnvironment('ALLOW_INSECURE_LOCAL')) {
      throw const ServiceFailure(
        'HTTPS_REQUIRED',
        'Use an HTTPS API address. HTTP is allowed only in explicit local development builds.',
      );
    }
  }
  final Dio dio;
  String? token;
  Future<Json> send(
    String route, {
    String method = 'GET',
    Object? body,
    Map<String, String>? headers,
  }) async {
    try {
      final r = await dio.request<Json>(
        route,
        data: body,
        options: Options(
          method: method,
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
            ...?(headers),
            if (body is String) 'Content-Type': 'application/json',
          },
        ),
      );
      return r.data ?? {};
    } on DioException catch (e) {
      final data = e.response?.data;
      final err = data is Map ? data['error'] : null;
      throw ServiceFailure(
        err is Map
            ? err['code'] as String? ?? 'TRANSPORT_ERROR'
            : 'TRANSPORT_ERROR',
        err is Map
            ? err['message'] as String? ??
                  'Could not connect. Your saved work is safe.'
            : 'Could not connect. Your saved work is safe.',
        status: e.response?.statusCode,
        retryable:
            e.response == null ||
            [429, 500, 502, 503, 504].contains(e.response?.statusCode),
        receipt: err is Map ? err['receipt'] as Json? : null,
      );
    }
  }
}
