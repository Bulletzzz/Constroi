import 'dart:io';

import 'package:constroi_api/conexao_api.dart';
import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';

Future<void> main() async {
  try {
    await executar();
  } on Object {
    // Excecoes do driver podem conter a URL. Nunca imprimir credenciais.
    stderr.writeln(
      'Falha na migration. Confira MIGRATION_DATABASE_URL, '
      'permissoes e SQL no ambiente exclusivo de migrations.',
    );
    exitCode = 1;
  }
}

Future<void> executar() async {
  final envPath =
      Platform.environment['MIGRATION_ENV_FILE'] ?? '.env.migrations';
  final envFile = File(envPath);
  final ambiente = DotEnv(includePlatformEnvironment: true)
    ..load(envFile.existsSync() ? [envPath] : []);
  final databaseUrlNormalizada = urlDeMigration({
    if (ambiente['DATABASE_URL'] case final String valor) 'DATABASE_URL': valor,
    if (ambiente['MIGRATION_DATABASE_URL'] case final String valor)
      'MIGRATION_DATABASE_URL': valor,
  });

  final conexao = await Connection.openFromUrl(
    databaseUrlNormalizada,
  );
  try {
    await conexao.execute('''
      CREATE TABLE IF NOT EXISTS schema_migrations (
        versao VARCHAR(255) PRIMARY KEY,
        aplicada_em TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    final arquivos =
        Directory('migrations')
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
