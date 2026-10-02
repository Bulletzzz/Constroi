import 'dart:io';

import 'package:dotenv/dotenv.dart';

final _ambiente = DotEnv(includePlatformEnvironment: true)
  ..load(File('.env').existsSync() ? ['.env'] : []);

/// Le do .env quando existe e cai para a variavel de ambiente do sistema,
/// que e como o docker-compose entrega os valores.
String? variavel(String nome) {
  final valor = _ambiente[nome]?.trim();
  return (valor == null || valor.isEmpty) ? null : valor;
}

/// Valida o TLS e remove parâmetros que o console do Neon acrescenta, mas que
/// ainda não são reconhecidos pelo package:postgres.
String normalizarDatabaseUrl(String valor) {
  final uri = Uri.parse(valor);
  final sslMode = uri.queryParameters['sslmode'];
  if (sslMode != 'require' && sslMode != 'verify-full') {
    throw FormatException(
      'A conexao remota deve usar sslmode=require ou sslmode=verify-full.',
      valor,
    );
  }

  final parametros = Map<String, String>.from(uri.queryParameters)
    ..remove('channel_binding');
  return uri.replace(queryParameters: parametros).toString();
}
