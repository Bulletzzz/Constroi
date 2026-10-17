import 'dart:convert';
import 'dart:io';

import 'package:constroi_api/conexao_api.dart';
import 'package:dotenv/dotenv.dart';

Future<void> main() async {
  final caminho = Platform.environment['API_ENV_FILE'] ?? '.env';
  final env = DotEnv(includePlatformEnvironment: true)
    ..load(File(caminho).existsSync() ? [caminho] : []);
  try {
    final url = env['DATABASE_URL'];
    if (url == null || url.isEmpty) throw const FormatException();
    final limite = int.parse(env['DATABASE_TRANSACTION_TIMEOUT_MS'] ?? '30000');
    final pool = criarPoolApi(url, limiteMs: limite);
    try {
      final resultado = await pool.execute('''
        SELECT current_user AS papel,
          (SELECT setting::int FROM pg_settings
            WHERE name='transaction_timeout') AS limite_transacao_ms,
          to_regclass('public.movimentacao_estoque') IS NOT NULL
            AS auditoria_instalada
      ''');
      stdout.writeln(
        jsonEncode({
          ...resultado.single.toColumnMap(),
          'maior_limite_permitido_ms': limiteMaximoTransacaoMs,
          'margem_fechamento_ms': margemFechamentoAuditoriaMs,
        }),
      );
    } finally {
      await pool.close();
    }
  } on Object {
    stderr.writeln(
      'Validacao recusada. Confira papel, permissoes, '
      'PostgreSQL 17+, endpoint direto e limite de transacao.',
    );
    exitCode = 1;
  }
}
