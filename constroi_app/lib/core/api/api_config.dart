import 'package:flutter/foundation.dart';

class ApiConfig {
  ApiConfig(String baseUrl, {bool allowInsecureForDevelopment = false})
    : baseUri = _parseBaseUrl(baseUrl, allowInsecureForDevelopment);

  final Uri baseUri;

  factory ApiConfig.fromEnvironment() => ApiConfig(
    const String.fromEnvironment('API_BASE_URL'),
    allowInsecureForDevelopment: const bool.fromEnvironment(
      'ALLOW_INSECURE_API',
    ),
  );

  static Uri _parseBaseUrl(String value, bool allowInsecure) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
      throw ArgumentError.value(
        value,
        'baseUrl',
        'Informe uma URL base válida',
      );
    }
    if (uri.scheme != 'https' &&
        !(uri.scheme == 'http' && !kReleaseMode && allowInsecure)) {
      throw ArgumentError.value(value, 'baseUrl', 'A API deve usar HTTPS');
    }
    if (uri.hasQuery || uri.hasFragment || uri.userInfo.isNotEmpty) {
      throw ArgumentError.value(value, 'baseUrl', 'URL base inválida');
    }
    return uri.replace(path: '${uri.path.replaceFirst(RegExp(r'/$'), '')}/');
  }
}
