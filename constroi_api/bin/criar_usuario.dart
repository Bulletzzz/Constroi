import 'dart:io';

import 'package:constroi_api/senha.dart';
import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';

/// Uso: dart run bin/criar_usuario.dart <email> <senha> <nome> <tipo>
Future<void> main(List<String> argumentos) async {
  if (argumentos.length < 4) {
    stderr.writeln(
      'Uso: dart run bin/criar_usuario.dart <email> <senha> <nome> <tipo>',
    );
    exitCode = 1;
    return;
  }

  final ambiente = DotEnv(includePlatformEnvironment: true)
    ..load(File('.env').existsSync() ? ['.env'] : []);
  final databaseUrl = ambiente['DATABASE_URL']?.trim();
  if (databaseUrl == null || databaseUrl.isEmpty) {
    stderr.writeln('DATABASE_URL nao configurada');
    exitCode = 1;
    return;
  }

  final email = argumentos[0];
  final senha = argumentos[1];
  final nome = argumentos[2];
  final tipo = argumentos[3];

  final conexao = await Connection.openFromUrl(databaseUrl);
  try {
    final empresas = await conexao.execute('SELECT id FROM empresa LIMIT 1');
    final empresaId = empresas.isNotEmpty
        ? empresas.first[0]! as int
        : (await conexao.execute(
            Sql.named(
              'INSERT INTO empresa (nome, cnpj) VALUES (@nome, @cnpj)'
              ' RETURNING id',
            ),
            parameters: {'nome': 'Constroi Teste', 'cnpj': '00.000.000/0001-00'},
          ))
            .first[0]! as int;

    await conexao.execute(
      Sql.named('''
        INSERT INTO usuario (empresa_id, nome, email, senha_hash, tipo)
        VALUES (@empresa, @nome, @email, @hash, @tipo)
        ON CONFLICT (LOWER(email)) DO UPDATE
        SET senha_hash = EXCLUDED.senha_hash,
            nome = EXCLUDED.nome,
            tipo = EXCLUDED.tipo
      '''),
      parameters: {
        'empresa': empresaId,
        'nome': nome,
        'email': email,
        'hash': gerarHash(senha),
        'tipo': tipo,
      },
    );

    stdout.writeln('Usuario $email pronto como $tipo na empresa $empresaId');
  } finally {
    await conexao.close();
  }
}
