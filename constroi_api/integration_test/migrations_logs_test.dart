// Banco local descartavel; nunca carrega .env.
import 'dart:convert';
import 'dart:io';

import 'package:constroi_api/logs.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

void main() {
  late Pool<void> banco;
  late String url;
  const versao = '014_log_empresa.sql';
  Future<void> sql(String texto) async {
    await banco.execute(texto, queryMode: QueryMode.simple);
  }

  Future<void> limpar() =>
      sql('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  Future<ProcessResult> migrar() => Process.run(
    Platform.resolvedExecutable,
    ['run', 'bin/migrate.dart'],
    environment: {
      'MIGRATION_DATABASE_URL': url,
      'MIGRATION_ENV_FILE': '.env.migrations-teste-inexistente',
      'DATABASE_URL': '',
    },
  );
  Future<void> migrarTudo() async {
    final res = await migrar();
    expect(res.exitCode, 0, reason: '${res.stderr}');
  }

  Future<void> semear() => sql('''
    INSERT INTO empresa(id,nome,cnpj) VALUES (1,'A','A'),(2,'B','B');
    INSERT INTO usuario(id,empresa_id,nome,email,senha_hash,tipo,ativo) VALUES
      (1,1,'Master A','a@a','hash','master',true),
      (2,1,'Eng A','e@a','hash','engenheiro',true),
      (3,2,'Master B','b@b','hash','master',false);
  ''');
  Future<List<List<Object?>>> definicao() async {
    final colunas = await banco.execute('''
      SELECT column_name,data_type,is_nullable FROM information_schema.columns
      WHERE table_schema='public' AND table_name='log_sistema'
      ORDER BY ordinal_position
    ''');
    final constraints = await banco.execute('''
      SELECT conname,pg_get_constraintdef(oid) FROM pg_constraint
      WHERE conrelid='log_sistema'::regclass ORDER BY conname
    ''');
    final indices = await banco.execute('''
      SELECT indexname,indexdef FROM pg_indexes
      WHERE schemaname='public' AND tablename='log_sistema' ORDER BY indexname
    ''');
    return [
      ...colunas,
      ...constraints,
      ...indices,
    ].map((r) => r.toList()).toList();
  }

  Matcher codigo(String code) =>
      isA<ServerException>().having((e) => e.code, 'SQLSTATE', code);

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
  setUp(limpar);

  test(
    'banco vazio e schema consolidado geram o mesmo log; runner nao reaplica',
    () async {
      await sql(await File('../Database/schema.sql').readAsString());
      final consolidado = await definicao();
      final res = await migrar();
      expect(res.exitCode, 0, reason: '${res.stderr}');
      expect('${res.stdout}', isNot(contains('Aplicada ')));
      await limpar();
      await migrarTudo();
      expect(await definicao(), consolidado);
      final segunda = await migrar();
      expect(segunda.exitCode, 0, reason: '${segunda.stderr}');
      expect('${segunda.stdout}', isNot(contains('Aplicada ')));
      expect(
        (await banco.execute(
          Sql.named(
            'SELECT count(*) FROM schema_migrations WHERE versao=@versao',
          ),
          parameters: {'versao': versao},
        )).single[0],
        1,
      );
    },
  );

  test(
    'upgrade preenche empresas e preserva ids, autores, textos e instantes',
    () async {
      await sql(
        'CREATE TABLE schema_migrations (versao varchar(255) PRIMARY KEY, '
        'aplicada_em timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP)',
      );
      final arquivos =
          Directory('migrations')
              .listSync()
              .whereType<File>()
              .where(
                (f) =>
                    f.path.endsWith('.sql') &&
                    f.uri.pathSegments.last != versao,
              )
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      for (final arquivo in arquivos) {
        await sql(await arquivo.readAsString());
        await banco.execute(
          Sql.named(
            'INSERT INTO schema_migrations(versao) VALUES (@versao)',
          ),
          parameters: {'versao': arquivo.uri.pathSegments.last},
        );
      }
      await semear();
      await sql("""
      INSERT INTO log_sistema(usuario_id,acao,data) VALUES
        (1,'LEGADO A','2026-10-28T23:45:00-03:00'),
        (3,'LEGADO B','2018-01-15T00:00:00-02:00');
    """);
      const campos =
          'SELECT id,usuario_id,acao,data FROM log_sistema ORDER BY id';
      final antes = (await banco.execute(
        campos,
      )).map((r) => r.toList()).toList();
      await migrarTudo();
      expect((await banco.execute(campos)).map((r) => r.toList()), antes);
      expect(
        (await banco.execute(
          'SELECT empresa_id FROM log_sistema ORDER BY id',
        )).map((r) => r[0]),
        [1, 2],
      );
      await migrarTudo();
      expect((await banco.execute(campos)).map((r) => r.toList()), antes);
    },
  );

  test(
    'empresa e obrigatoria, FK impede cruzamento e helper usa empresa do autor',
    () async {
      await migrarTudo();
      await semear();
      await expectLater(
        banco.execute(
          "INSERT INTO log_sistema(usuario_id,acao) VALUES (1,'sem empresa')",
        ),
        throwsA(codigo('23502')),
      );
      await expectLater(
        banco.execute(
          'INSERT INTO log_sistema(empresa_id,usuario_id,acao) '
          "VALUES (2,1,'cruzado')",
        ),
        throwsA(codigo('23503')),
      );
      await banco.runTx(
        (tx) => registrarLog(tx, usuarioId: 3, acao: 'EVENTO usuario=3'),
      );
      expect(
        (await banco.execute(
          'SELECT empresa_id,usuario_id FROM log_sistema',
        )).single.toList(),
        [2, 3],
      );
      await expectLater(
        banco.execute('UPDATE usuario SET empresa_id=1 WHERE id=3'),
        throwsA(codigo('23503')),
      );
      await expectLater(
        banco.runTx((tx) => registrarLog(tx, usuarioId: 999, acao: 'ausente')),
        throwsA(codigo('23502')),
      );
      expect(
        (await banco.execute('SELECT count(*) FROM log_sistema')).single[0],
        1,
      );
    },
  );

  test(
    'consultas reais usam indices por empresa e usuario sem seq scan ou sort',
    () async {
      await migrarTudo();
      await semear();
      await sql("""
      INSERT INTO log_sistema(empresa_id,usuario_id,acao,data)
      SELECT CASE WHEN n%10=0 THEN 1 ELSE 2 END,
        CASE WHEN n%20=0 THEN 1 WHEN n%10=0 THEN 2 ELSE 3 END,
        'EVENTO '||n, '2026-10-01T00:00:00Z'::timestamptz+n*interval '1 second'
      FROM generate_series(1,50000) n;
      ANALYZE log_sistema;
    """);
      final evidencias = <String, Object?>{};
      for (final porUsuario in [false, true]) {
        final res = await banco.execute(
          Sql.named(
            'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) '
            '${consultaLogs(porUsuario: porUsuario)}',
          ),
          parameters: {
            'empresa': 1,
            if (porUsuario) 'usuario': 2,
            'limite': 51,
            'offset': 0,
          },
        );
        final texto = jsonEncode(res.single[0]);
        final indice = porUsuario
            ? 'ix_log_empresa_usuario_periodo'
            : 'ix_log_empresa_periodo';
        expect(texto, contains(indice));
        expect(texto, isNot(contains('"Node Type":"Seq Scan"')));
        expect(texto, isNot(contains('"Node Type":"Sort"')));
        expect(texto, isNot(contains('"Node Type":"Incremental Sort"')));
        evidencias[porUsuario ? 'usuario' : 'empresa'] = res.single[0];
      }
      await File(
        '.dart_tool/logs-review46-explain.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(evidencias));
    },
  );
}
