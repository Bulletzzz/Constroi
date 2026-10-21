import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

void main() {
  late Connection banco;
  late String url;

  Future<ProcessResult> migrar() => Process.run(
    Platform.resolvedExecutable,
    ['run', 'bin/migrate.dart'],
    environment: {
      'MIGRATION_DATABASE_URL': url,
      'MIGRATION_ENV_FILE': '.env.migrations-teste-inexistente',
      'DATABASE_URL': '',
    },
  );

  Future<void> verificarRunner({required bool aplica}) async {
    final resultado = await migrar();
    expect(resultado.exitCode, 0, reason: '${resultado.stderr}');
    expect('${resultado.stdout}'.contains('Aplicada '), aplica);
    expect(
      (await banco.execute('SELECT count(*) FROM schema_migrations')).single[0],
      Directory('migrations')
          .listSync()
          .whereType<File>()
          .where(
            (arquivo) => arquivo.path.endsWith('.sql'),
          )
          .length,
    );
  }

  setUpAll(() async {
    url = Platform.environment['CONSTROI_TEST_DATABASE_URL'] ?? '';
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['postgresql', 'postgres'].contains(uri.scheme) ||
        !['localhost', '127.0.0.1', '::1'].contains(uri.host) ||
        uri.pathSegments.length != 1 ||
        !uri.pathSegments.single.startsWith('constroi_test_')) {
      throw StateError('Use banco local descartavel constroi_test_*.');
    }
    // A mesma URL atende as suites com pool; conexao direta/runner nao
    // aceitam essa opcao do pool. Preserva TLS e as demais configuracoes.
    final parametros = Map<String, String>.from(uri.queryParameters)
      ..remove('max_connection_count');
    url = uri.replace(queryParameters: parametros).toString();
    banco = await Connection.openFromUrl(url);
    addTearDown(() => banco.close());
  });

  setUp(
    () => banco.execute(
      'DROP SCHEMA public CASCADE; CREATE SCHEMA public;',
      queryMode: QueryMode.simple,
    ),
  );

  test(
    'schema consolidado registra 011 e runner nao reaplica migrations',
    () async {
      await banco.execute(
        await File('../Database/schema.sql').readAsString(),
        queryMode: QueryMode.simple,
      );
      expect(
        (await banco.execute(
          'SELECT count(*) FROM schema_migrations '
          "WHERE versao='011_entrada_nfe.sql'",
        )).single[0],
        1,
      );
      await verificarRunner(aplica: false);
    },
  );

  test('011 pode ser reaplicada sem perder XML nem constraints', () async {
    await banco.execute(
      await File('../Database/schema.sql').readAsString(),
      queryMode: QueryMode.simple,
    );
    await banco.execute('''
      INSERT INTO empresa (nome,cnpj) VALUES ('A','A');
      INSERT INTO usuario (empresa_id,nome,email,senha_hash,tipo)
        VALUES (1,'Eng','a@a','hash','engenheiro');
      INSERT INTO obra (empresa_id,nome,endereco,status)
        VALUES (1,'Obra','Rua','ativa');
      INSERT INTO entrada_estoque (usuario_id,obra_id,xml_nota_fiscal)
        VALUES (1,1,'<legado/>');
      INSERT INTO entrada_estoque
        (usuario_id,obra_id,xml_nota_fiscal,empresa_nfe_id,chave_nfe)
        VALUES (1,1,'<nota/>',1,repeat('1',44));
      DELETE FROM schema_migrations WHERE versao='011_entrada_nfe.sql';
    ''', queryMode: QueryMode.simple);
    final antes = await banco.execute(
      'SELECT * FROM entrada_estoque ORDER BY id',
    );
    await verificarRunner(aplica: true);
    await banco.runTx(
      (tx) async => tx.execute(
        await File('migrations/011_entrada_nfe.sql').readAsString(),
        queryMode: QueryMode.simple,
      ),
    );
    expect(
      (await banco.execute(
        'SELECT * FROM entrada_estoque ORDER BY id',
      )).map((r) => r.toList()).toList(),
      antes.map((r) => r.toList()).toList(),
    );
    expect(
      (await banco.execute('''
        SELECT count(*) FROM pg_constraint
        WHERE conrelid='entrada_estoque'::regclass AND conname IN
          ('fk_entrada_nfe_empresa','ck_entrada_nfe_chave','ux_entrada_nfe_empresa')
      ''')).single[0],
      3,
    );
    await verificarRunner(aplica: false);
  });

  test(
    'banco vazio recebe todas as migrations e segunda rodada nao altera',
    () async {
      await verificarRunner(aplica: true);
      await verificarRunner(aplica: false);
    },
  );
}
