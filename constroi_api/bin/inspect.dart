import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';

Future<void> main() async {
  final envPath = Platform.environment['DATABASE_ENV_FILE'] ??
      '../constroi_api/.env';
  final ambiente = DotEnv(includePlatformEnvironment: true)
    ..load(File(envPath).existsSync() ? [envPath] : []);
  final databaseUrl = ambiente['DATABASE_URL']?.trim();
  if (databaseUrl == null || databaseUrl.isEmpty) {
    stderr.writeln('DATABASE_URL nao configurada');
    exitCode = 1;
    return;
  }

  final conexao = await Connection.openFromUrl(databaseUrl);
  try {
    final colunas = await conexao.execute('''
      SELECT table_name, column_name, data_type, is_nullable
      FROM information_schema.columns
      WHERE table_schema = 'public'
      ORDER BY table_name, ordinal_position
    ''');

    String? tabelaAtual;
    for (final linha in colunas) {
      final tabela = linha[0]! as String;
      if (tabela != tabelaAtual) {
        tabelaAtual = tabela;
        stdout.writeln('\n$tabela');
      }
      stdout.writeln('  ${linha[1]} | ${linha[2]} | nullable=${linha[3]}');
    }
  } finally {
    await conexao.close();
  }
}
