import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';

Future<void> main() async {
  final envPath = Platform.environment['DATABASE_ENV_FILE'] ??
      '../constroi_api/.env';
  final envFile = File(envPath);
  final ambiente = DotEnv(includePlatformEnvironment: true)
    ..load(envFile.existsSync() ? [envPath] : []);
  final databaseUrl = ambiente['DATABASE_URL']?.trim();

  if (databaseUrl == null || databaseUrl.isEmpty) {
    stderr.writeln('DATABASE_URL nao configurada em $envPath');
    exitCode = 1;
    return;
  }

  final uri = Uri.tryParse(databaseUrl);
  final sslMode = uri?.queryParameters['sslmode'];
  if (sslMode != 'require' && sslMode != 'verify-full') {
    stderr.writeln('A conexao remota deve usar sslmode=require');
    exitCode = 1;
    return;
  }

  final conexao = await Connection.openFromUrl(databaseUrl);
  try {
    await conexao.execute('''
      CREATE TABLE IF NOT EXISTS schema_migrations (
        versao VARCHAR(255) PRIMARY KEY,
        aplicada_em TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    final arquivos = Directory('migrations')
        .listSync()
        .whereType<File>()
        .where((arquivo) => arquivo.path.endsWith('.sql'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final arquivo in arquivos) {
      final versao = arquivo.uri.pathSegments.last;
      final aplicada = await conexao.execute(
        Sql.named(
          'SELECT 1 FROM schema_migrations WHERE versao = @versao LIMIT 1',
        ),
        parameters: {'versao': versao},
      );

      if (aplicada.isNotEmpty) {
        stdout.writeln('Ja aplicada $versao');
        continue;
      }

      final sql = await arquivo.readAsString();
      await conexao.runTx((transacao) async {
        await transacao.execute(sql, queryMode: QueryMode.simple);
        await transacao.execute(
          Sql.named(
            'INSERT INTO schema_migrations (versao) VALUES (@versao)',
          ),
          parameters: {'versao': versao},
        );
      });
      stdout.writeln('Aplicada $versao');
    }
  } finally {
    await conexao.close();
  }
}
