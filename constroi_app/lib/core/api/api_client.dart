import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/session_manager.dart';
import 'api_config.dart';

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message, {this.details = const {}});

  final int statusCode;
  final String message;
  final Map<String, dynamic> details;

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
    final uri = _uri(path, query: query);
    final request = http.Request(method.toUpperCase(), uri);
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    return _send(request);
  }

  Future<dynamic> multipart(
    String method,
    String path, {
    Map<String, String> fields = const {},
    required List<http.MultipartFile> files,
  }) => _send(
    http.MultipartRequest(method.toUpperCase(), _uri(path))
      ..fields.addAll(fields)
      ..files.addAll(files),
  );

  Uri _uri(String path, {Map<String, String>? query}) {
    if (path.startsWith('/') ||
        Uri.parse(path).hasScheme ||
        Uri.parse(path).hasAuthority ||
        path.split('/').contains('..')) {
      throw ArgumentError.value(path, 'path', 'Use um caminho relativo à API');
    }
    return _baseUri.resolve(path).replace(queryParameters: query);
  }

  Future<dynamic> _send(http.BaseRequest request) async {
    final token = _sessions.accessToken;
    final headers = <String, String>{'Accept': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';

    request.headers.addAll(headers);
    final response = await _http.send(request);
    final text = await response.stream.bytesToString();
    final mensagem = _mensagemDaApi(text);

    if (response.statusCode == 401) {
      if (token != null) {
        await _sessions.expireIfCurrent(token);
        throw const ApiException(401, 'Sessão expirada. Entre novamente.');
      }
      throw ApiException(401, mensagem ?? 'Credenciais inválidas.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        mensagem ?? 'Falha na requisição à API',
        details: _detalhesDaApi(text),
      );
    }
    return text.isEmpty ? null : jsonDecode(text);
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      request('GET', path, query: query);

  Future<dynamic> post(String path, {Object? body}) =>
      request('POST', path, body: body);

  Future<dynamic> patch(String path, {Object? body}) =>
      request('PATCH', path, body: body);

  void close() {
    if (_ownsClient) _http.close();
  }

  static String? _mensagemDaApi(String corpo) {
    if (corpo.isEmpty) return null;
    try {
      final decodificado = jsonDecode(corpo);
      if (decodificado is Map && decodificado['erro'] is String) {
        final erro = decodificado['erro'] as String;
        return erro.isEmpty ? null : erro;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static Map<String, dynamic> _detalhesDaApi(String corpo) {
    try {
      final dados = jsonDecode(corpo);
      return dados is Map<String, dynamic> ? dados : const {};
    } on FormatException {
      return const {};
    }
  }
}
