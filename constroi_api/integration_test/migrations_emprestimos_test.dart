import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

void main() {
  late Pool<void> banco;
  late String url;
  const versao = '015_emprestimos.sql';

  Future<void> sql(String texto) async {
    await banco.execute(texto, queryMode: QueryMode.simple);
  }

  Future<ProcessResult> migrar() => Process.run(
    Platform.resolvedExecutable,
    ['run', 'bin/migrate.dart'],
    environment: {
      'MIGRATION_DATABASE_URL': url,
      'MIGRATION_ENV_FILE': '.env.migrations-emprestimos-inexistente',
      'DATABASE_URL': '',
    },
  );
  Future<void> aplicar() async {
    final resultado = await migrar();
    expect(resultado.exitCode, 0, reason: '${resultado.stderr}');
  }

  Future<void> anteriores() async {
    await sql('''
      CREATE TABLE schema_migrations (
        versao varchar(255) PRIMARY KEY,
        aplicada_em timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    final arquivos =
        Directory('migrations')
            .listSync()
            .whereType<File>()
            .where(
              (f) =>
                  f.path.endsWith('.sql') &&
                  f.uri.pathSegments.last.compareTo(versao) < 0,
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final arquivo in arquivos) {
      await sql(await arquivo.readAsString());
      await banco.execute(
        Sql.named('INSERT INTO schema_migrations(versao) VALUES (@v)'),
        parameters: {'v': arquivo.uri.pathSegments.last},
      );
    }
  }

  Future<void> semear() => sql('''
    INSERT INTO empresa(id,nome,cnpj) VALUES (1,'A','A'),(2,'B','B');
    INSERT INTO usuario(id,empresa_id,nome,email,senha_hash,tipo) VALUES
      (1,1,'Responsavel A','a@a','hash','pedreiro'),
      (2,2,'Responsavel B','b@b','hash','pedreiro');
    INSERT INTO obra(id,empresa_id,nome,endereco,status) VALUES
      (1,1,'Obra A','Rua','ativa'),(2,2,'Obra B','Rua','ativa');
    INSERT INTO equipamento(id,empresa_id,nome,patrimonio,status) VALUES
      (1,1,'Betoneira','B1','disponivel');
  ''');
  Future<List<List<Object?>>> definicao() async {
    final colunas = await banco.execute('''
      SELECT column_name,data_type,is_nullable,column_default
      FROM information_schema.columns
      WHERE table_schema='public' AND table_name='emprestimo'
      ORDER BY ordinal_position
    ''');
    final constraints = await banco.execute('''
      SELECT conname,pg_get_constraintdef(oid) FROM pg_constraint
      WHERE conrelid='emprestimo'::regclass ORDER BY conname
    ''');
    final indices = await banco.execute('''
      SELECT tablename,indexname,indexdef FROM pg_indexes
      WHERE schemaname='public' AND tablename IN ('emprestimo','equipamento')
      ORDER BY tablename,indexname
    ''');
    return [
      ...colunas,
      ...constraints,
      ...indices,
    ].map((r) => r.toList()).toList();
  }

  setUpAll(() async {
    url = Platform.environment['CONSTROI_TEST_DATABASE_URL'] ?? '';
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['postgres', 'postgresql'].contains(uri.scheme) ||
        !['localhost', '127.0.0.1', '::1'].contains(uri.host) ||
        uri.pathSegments.length != 1 ||
        !uri.pathSegments.single.startsWith('constroi_test_')) {
      throw StateError('Use banco local descartavel constroi_test_*.');
    }
    banco = Pool<void>.withUrl(url);
    addTearDown(() => banco.close());
  });
  setUp(() => sql('DROP SCHEMA public CASCADE; CREATE SCHEMA public;'));

  test(
    'banco vazio e consolidado coincidem; runner aplica 015 uma vez',
    () async {
      await sql(await File('../Database/schema.sql').readAsString());
      final consolidado = await definicao();
      final semMudanca = await migrar();
      expect(semMudanca.exitCode, 0);
      expect('${semMudanca.stdout}', isNot(contains('Aplicada ')));
      await sql('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
      await aplicar();
      expect(await definicao(), consolidado);
      final segunda = await migrar();
      expect(segunda.exitCode, 0);
      expect('${segunda.stdout}', isNot(contains('Aplicada ')));
      expect(
        (await banco.execute(
          "SELECT count(*) FROM schema_migrations WHERE versao='$versao'",
        )).single[0],
        1,
      );
    },
  );

  test(
    'upgrade preenche empresa, preserva prazos informados e sincroniza aberto',
    () async {
      await anteriores();
      await semear();
      await sql('''
      ALTER TABLE emprestimo ADD COLUMN data_prevista timestamptz;
      INSERT INTO emprestimo(equipamento_id,usuario_id,obra_id,
        data_emprestimo,data_prevista,status) VALUES
        (1,1,1,'2026-10-01T10:00:00Z','2026-10-05T10:00:00Z','aberto');
    ''');
      const campos =
          'SELECT id,equipamento_id,usuario_id,obra_id, '
          'data_emprestimo,data_prevista,status FROM emprestimo';
      final antes = (await banco.execute(campos)).single.toList();
      await aplicar();
      expect((await banco.execute(campos)).single.toList(), antes);
      expect(
        (await banco.execute('SELECT empresa_id FROM emprestimo')).single[0],
        1,
      );
      expect(
        (await banco.execute(
          'SELECT status FROM equipamento WHERE id=1',
        )).single[0],
        'em_uso',
      );
    },
  );

  test(
    'legado sem prazo bloqueia migration atomicamente sem inventar datas',
    () async {
      await anteriores();
      await semear();
      await sql('''
      INSERT INTO emprestimo(equipamento_id,usuario_id,obra_id,status)
      VALUES (1,1,1,'aberto')
    ''');
      final antes = (await banco.execute(
        'SELECT * FROM emprestimo',
      )).single.toList();
      final resultado = await migrar();
      expect(resultado.exitCode, isNot(0));
      expect(
        (await banco.execute('SELECT * FROM emprestimo')).single.toList(),
        antes,
      );
      expect(
        (await banco.execute(
          "SELECT count(*) FROM schema_migrations WHERE versao='$versao'",
        )).single[0],
        0,
      );
      expect(
        (await banco.execute('''
      SELECT count(*) FROM information_schema.columns
      WHERE table_schema='public' AND table_name='emprestimo' AND column_name='empresa_id'
    ''')).single[0],
        0,
      );
    },
  );

  for (final caso in ['empresa cruzada', 'dois abertos']) {
    test('legado com $caso bloqueia upgrade sem perder registros', () async {
      await anteriores();
      await semear();
      await sql('''
        ALTER TABLE emprestimo ADD COLUMN data_prevista timestamptz;
        INSERT INTO emprestimo(equipamento_id,usuario_id,obra_id,data_prevista,status)
        VALUES (1,${caso == 'empresa cruzada' ? 2 : 1},1,
          CURRENT_TIMESTAMP+INTERVAL '1 day','aberto');
      ''');
      if (caso == 'dois abertos') {
        await sql('''
          INSERT INTO emprestimo(equipamento_id,usuario_id,obra_id,data_prevista,status)
          VALUES (1,1,1,CURRENT_TIMESTAMP+INTERVAL '2 days','aberto')
        ''');
      }
      final antes = (await banco.execute(
        'SELECT * FROM emprestimo ORDER BY id',
      )).map((r) => r.toList()).toList();
      expect((await migrar()).exitCode, isNot(0));
      expect(
        (await banco.execute(
          'SELECT * FROM emprestimo ORDER BY id',
        )).map((r) => r.toList()).toList(),
        antes,
      );
      expect(
        (await banco.execute(
          'SELECT status FROM equipamento WHERE id=1',
        )).single[0],
        'disponivel',
      );
    });
  }

  test(
    '015 pode ser reaplicada e restaura indice sem reescrever historico',
    () async {
      await aplicar();
      await semear();
      await sql('''
      INSERT INTO emprestimo(empresa_id,equipamento_id,usuario_id,obra_id,
        data_emprestimo,data_prevista,data_devolucao,status) VALUES
        (1,1,1,1,'2026-10-01T10:00:00Z','2026-10-05T10:00:00Z',
         '2026-10-04T11:00:00Z','devolvido');
    ''');
      final antes = (await banco.execute(
        'SELECT * FROM emprestimo',
      )).single.toList();
      final definicaoAntes = await definicao();
      await sql('DROP INDEX ux_emprestimo_equipamento_aberto');
      await banco.runTx((tx) async {
        await tx.execute(
          await File('migrations/$versao').readAsString(),
          queryMode: QueryMode.simple,
        );
      });
      expect(await definicao(), definicaoAntes);
      expect(
        (await banco.execute('SELECT * FROM emprestimo')).single.toList(),
        antes,
      );
    },
  );
}
