import 'dart:io';

import 'package:dotenv/dotenv.dart';

final _arquivo = DotEnv()..load(File('.env').existsSync() ? ['.env'] : []);

String? variavel(String nome) =>
    escolherVariavel(Platform.environment[nome], _arquivo[nome]);

String? escolherVariavel(String? doSistema, String? doArquivo) {
  final sistema = doSistema?.trim();
  if (sistema != null && sistema.isNotEmpty) return sistema;
  final arquivo = doArquivo?.trim();
  return (arquivo == null || arquivo.isEmpty) ? null : arquivo;
}

bool variavelBooleana(String nome) => interpretarBooleano(nome, variavel(nome));

/// Ignora caixa/espacos nas bordas; rejeita vazio e valores desconhecidos.
bool interpretarBooleano(String nome, String? valor) {
  return switch (valor?.trim().toLowerCase()) {
    null || 'false' => false,
    'true' => true,
    _ => throw FormatException('$nome invalida: use true ou false.'),
  };
}

/// Valida o TLS e remove parâmetros que o console do Neon acrescenta, mas que
/// ainda não são reconhecidos pelo package:postgres.
String normalizarDatabaseUrl(String valor) {
  final uri = Uri.parse(valor);
  final sslMode = uri.queryParameters['sslmode'];
  if (sslMode != 'require' && sslMode != 'verify-full') {
    throw const FormatException(
      'A conexao remota deve usar sslmode=require ou sslmode=verify-full.',
    );
  }

  final parametros = Map<String, String>.from(uri.queryParameters)
    ..remove('channel_binding');
  return uri.replace(queryParameters: parametros).toString();
}
