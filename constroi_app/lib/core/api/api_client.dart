import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/session_manager.dart';
import 'api_config.dart';

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  ApiClient({
    required ApiConfig config,
    required SessionManager sessions,
    http.Client? httpClient,
  }) : _baseUri = config.baseUri,
       _sessions = sessions,
       _http = httpClient ?? http.Client(),
       _ownsClient = httpClient == null;

  final Uri _baseUri;
  final SessionManager _sessions;
  final http.Client _http;
  final bool _ownsClient;

  Future<dynamic> request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    if (path.startsWith('/') ||
        Uri.parse(path).hasScheme ||
        Uri.parse(path).hasAuthority ||
        path.split('/').contains('..')) {
      throw ArgumentError.value(path, 'path', 'Use um caminho relativo à API');
    }
    final uri = _baseUri.resolve(path).replace(queryParameters: query);
    final token = _sessions.accessToken;
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (token != null) headers['Authorization'] = 'Bearer $token';

    final response = await _http.send(
      http.Request(method.toUpperCase(), uri)
        ..headers.addAll(headers)
        ..body = body == null ? '' : jsonEncode(body),
    );
    final text = await response.stream.bytesToString();
    if (response.statusCode == 401) {
      if (token != null) await _sessions.expireIfCurrent(token);
      throw const ApiException(401, 'Sessão expirada. Entre novamente.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Falha na requisição à API');
    }
    return text.isEmpty ? null : jsonDecode(text);
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      request('GET', path, query: query);

  Future<dynamic> post(String path, {Object? body}) =>
      request('POST', path, body: body);

  void close() {
    if (_ownsClient) _http.close();
  }
}
