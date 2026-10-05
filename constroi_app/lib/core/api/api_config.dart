import 'package:flutter/foundation.dart';

class ApiConfig {
  ApiConfig(String baseUrl, {bool allowInsecureForDevelopment = false})
    : baseUri = _montarBase(baseUrl, allowInsecureForDevelopment);

  final Uri baseUri;

  factory ApiConfig.fromEnvironment() => ApiConfig(
    const String.fromEnvironment('API_BASE_URL'),
    allowInsecureForDevelopment: const bool.fromEnvironment(
      'ALLOW_INSECURE_API',
    ),
  );

  static Uri _montarBase(String valor, bool permitirHttp) =>
      valor.startsWith('/')
      ? _mesmaOrigem(valor)
      : _absoluta(valor, permitirHttp);

  static Uri _mesmaOrigem(String caminho) {
    if (!kIsWeb) {
      throw ArgumentError.value(
        caminho,
        'baseUrl',
        'Caminho relativo só vale no Flutter Web. '
            'No Android e iOS informe a URL completa da API.',
      );
    }
    return _comBarraFinal(Uri.base.resolve(caminho));
  }

  static Uri _absoluta(String valor, bool permitirHttp) {
    final uri = Uri.tryParse(valor);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
      throw ArgumentError.value(
        valor,
        'baseUrl',
        'Informe uma URL base válida',
      );
    }
    if (uri.scheme != 'https' &&
        !(uri.scheme == 'http' && !kReleaseMode && permitirHttp)) {
      throw ArgumentError.value(valor, 'baseUrl', 'A API deve usar HTTPS');
    }
    if (uri.hasQuery || uri.hasFragment || uri.userInfo.isNotEmpty) {
      throw ArgumentError.value(valor, 'baseUrl', 'URL base inválida');
    }
    return _comBarraFinal(uri);
  }

  static Uri _comBarraFinal(Uri uri) =>
      uri.replace(path: '${uri.path.replaceFirst(RegExp(r'/$'), '')}/');
}
