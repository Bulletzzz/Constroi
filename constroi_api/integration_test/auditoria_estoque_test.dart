// Banco local descartavel: cada teste de migration recria public.
import 'dart:io';
import 'dart:math';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/baixa_estoque.dart';
import 'package:constroi_api/conexao_api.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

void main() {
  late Pool<void> banco;
  late String url;
  const versao = '013_movimentacao_estoque.sql';
  Future<Result> sql(String texto, [Map<String, Object?>? parametros]) =>
      banco.execute(Sql.named(texto), parameters: parametros);
  Future<void> simples(String texto) =>
      banco.execute(texto, queryMode: QueryMode.simple);
  Future<void> limpar() =>
      simples('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  Future<ProcessResult> migrar() => Process.run(
    Platform.resolvedExecutable,
    ['run', 'bin/migrate.dart'],
    environment: {
      'MIGRATION_DATABASE_URL': url,
      'MIGRATION_ENV_FILE': '.env.migrations-inexistente-teste',
      'DATABASE_URL': '',
    },
  );
  Future<void> migrarAntesDaAuditoria() async {
    await simples('''
      CREATE TABLE schema_migrations (
        versao VARCHAR(255) PRIMARY KEY,
        aplicada_em TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    final arquivos =
        Directory('migrations')
            .listSync()
            .whereType<File>()
            .where(
              (f) =>
                  f.path.endsWith('.sql') && f.uri.pathSegments.last != versao,
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final arquivo in arquivos) {
      await simples(await arquivo.readAsString());
      await sql('INSERT INTO schema_migrations(versao) VALUES (@versao)', {
        'versao': arquivo.uri.pathSegments.last,
      });
    }
  }

  Future<void> semear() => simples('''
    INSERT INTO empresa(id,nome,cnpj) VALUES (1,'A','A'),(2,'B','B');
    INSERT INTO usuario(id,empresa_id,nome,email,senha_hash,tipo) VALUES
      (1,1,'Eng A','a@a','hash','engenheiro'),
      (2,2,'Eng B','b@b','hash','engenheiro');
    INSERT INTO obra(id,empresa_id,nome,endereco,status) VALUES
      (1,1,'A','Rua','ativa'),(2,2,'B','Rua','ativa'),(3,1,'A2','Rua','ativa');
    INSERT INTO produto(id,empresa_id,nome,unidade) VALUES
      (1,1,'Cimento','saco'),(2,2,'Alheio','kg'),(3,1,'Areia','kg');
    INSERT INTO estoque(obra_id,produto_id,quantidade) VALUES (1,1,4);
    INSERT INTO pedido(id,usuario_id,obra_id,protocolo,status) VALUES
      (1,1,1,'AUD-1','aprovado'),(2,2,2,'AUD-2','aprovado'),
      (3,1,3,'AUD-3','aprovado'),(4,1,1,'AUD-4','aprovado');
    INSERT INTO log_sistema(usuario_id,acao) VALUES
      (1,'BAIXA_ESTOQUE legado sem valores reconstruiveis');
  ''');
  Future<Result> inserir([Map<String, Object?> alteracoes = const {}]) => sql(
    '''
    INSERT INTO movimentacao_estoque (
      empresa_id,obra_id,produto_id,pedido_id,registrado_por_usuario_id,
      tipo,quantidade,saldo_anterior,saldo_posterior,
      protocolo_pedido,produto_nome,unidade
    ) VALUES (@empresa,@obra,@produto,@pedido,@usuario,@tipo,
      @quantidade::numeric,@anterior::numeric,@posterior::numeric,
      @protocolo,@nome,@unidade) RETURNING id,ocorrido_em
  ''',
    {
      'empresa': 1,
      'obra': 1,
      'produto': 1,
      'pedido': 1,
      'usuario': 1,
      'tipo': 'saida_pedido',
      'quantidade': '1.00',
      'anterior': '5.00',
      'posterior': '4.00',
      'protocolo': 'AUD-1',
      'nome': 'Cimento',
      'unidade': 'saco',
      ...alteracoes,
    },
  );
  Matcher codigo(String valor) =>
      isA<ServerException>().having((e) => e.code, 'SQLSTATE', valor);
  Future<List<List<Object?>>> definicaoAuditoria() async {
    final colunas = await sql('''
      SELECT column_name,data_type,is_nullable,column_default,
             numeric_precision,numeric_scale,character_maximum_length,is_identity
      FROM information_schema.columns WHERE table_schema='public'
        AND table_name='movimentacao_estoque' ORDER BY ordinal_position
    ''');
    final constraints = await sql('''
      SELECT conname,pg_get_constraintdef(oid) FROM pg_constraint
      WHERE conrelid='movimentacao_estoque'::regclass ORDER BY conname
    ''');
    final indices = await sql('''
      SELECT indexname,indexdef FROM pg_indexes WHERE schemaname='public'
        AND tablename='movimentacao_estoque' ORDER BY indexname
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
      throw StateError(
        'Use CONSTROI_TEST_DATABASE_URL local descartavel constroi_test_*. '
        'Nunca le .env.',
      );
    }
    banco = Pool<void>.withUrl(url);
    addTearDown(banco.close);
  });
  setUp(() async {
    await limpar();
    await simples(await File('../Database/schema.sql').readAsString());
    await semear();
  });

  test(
    'runner migra banco vazio, segunda execucao e no-op e schema confere',
    () async {
      final consolidado = await definicaoAuditoria();
      await limpar();
      final primeira = await migrar();
      expect(primeira.exitCode, 0, reason: '${primeira.stderr}');
      expect('${primeira.stdout}', contains('Aplicada $versao'));
      final segunda = await migrar();
      expect(segunda.exitCode, 0, reason: '${segunda.stderr}');
      expect('${segunda.stdout}', isNot(contains('Aplicada ')));
      expect(await definicaoAuditoria(), consolidado);
      expect(
        (await sql('SELECT count(*) FROM schema_migrations')).single[0],
        13,
      );
    },
  );

  test(
    'upgrade com historico preserva dados e nao inventa movimentos antigos',
    () async {
      await limpar();
      await migrarAntesDaAuditoria();
      await semear();
      final antes = (await sql(
        'SELECT * FROM log_sistema ORDER BY id',
      )).map((r) => r.toList()).toList();
      final resultado = await migrar();
      expect(resultado.exitCode, 0, reason: '${resultado.stderr}');
      expect('${resultado.stdout}', contains('Aplicada $versao'));
      expect(
        (await sql(
          'SELECT * FROM log_sistema ORDER BY id',
        )).map((r) => r.toList()).toList(),
        antes,
      );
      expect(
        (await sql('SELECT quantidade::text FROM estoque')).single[0],
        '4.00',
      );
      expect(
        (await sql('SELECT status FROM pedido WHERE id=1')).single[0],
        'aprovado',
      );
      expect(
        (await sql('SELECT count(*) FROM movimentacao_estoque')).single[0],
        0,
      );
      await inserir();
      expect(
        (await sql('SELECT count(*) FROM movimentacao_estoque')).single[0],
        1,
      );
    },
  );

  test(
    'infra provisionada antes da 013 concede escrita restrita na tabela nova',
    () async {
      await limpar();
      await migrarAntesDaAuditoria();
      await semear();
      await simples(
        await File('../Database/infra/auditoria_papeis.sql').readAsString(),
      );
      final aleatorio = Random.secure();
      final senha = List.generate(
        32,
        (_) => aleatorio.nextInt(16).toRadixString(16),
      ).join();
      await simples("ALTER ROLE constroi_api_execucao PASSWORD '$senha'");
      final resultado = await migrar();
      expect(resultado.exitCode, 0, reason: '${resultado.stderr}');
      await simples('''
      UPDATE pedido SET status='pendente' WHERE id=1;
      INSERT INTO item_pedido(pedido_id,produto_id,quantidade) VALUES (1,1,1);
    ''');
      final app = criarPoolApi(
        Uri.parse(
          url,
        ).replace(userInfo: 'constroi_api_execucao:$senha').toString(),
        conexaoEstrita: true,
      );
      addTearDown(app.close);
      expect(
        (await aprovarPedidoComBaixa(
          app,
          pedidoId: 1,
          usuario: const UsuarioAutenticado(
            id: 1,
            empresaId: 1,
            nivel: Nivel.engenheiro,
          ),
        ))['status'],
        'aprovado',
      );
      expect(
        (await app.execute(
          'SELECT quantidade::text,saldo_posterior::text '
          'FROM movimentacao_estoque',
        )).single.toList(),
        ['1.00', '3.00'],
      );
      for (final comando in [
        "UPDATE movimentacao_estoque SET produto_nome='nao'",
        'DELETE FROM movimentacao_estoque',
        'TRUNCATE movimentacao_estoque',
      ]) {
        await expectLater(app.execute(comando), throwsA(codigo('42501')));
      }
    },
  );

  test('data vem do relogio do banco e nao do inicio da transacao', () async {
    await banco.runTx((tx) async {
      final inicio =
          (await tx.execute('SELECT clock_timestamp()')).single[0]! as DateTime;
      await tx.execute('SELECT pg_sleep(0.03)');
      // Mesmo insert do helper, agora dentro de uma transacao ja iniciada.
      final resultado = await tx.execute('''
        INSERT INTO movimentacao_estoque (
          empresa_id,obra_id,produto_id,pedido_id,registrado_por_usuario_id,tipo,
          quantidade,saldo_anterior,saldo_posterior,protocolo_pedido,produto_nome,unidade
        ) VALUES (1,1,1,1,1,'saida_pedido',1,5,4,'AUD-1','Cimento','saco')
        RETURNING ocorrido_em
      ''');
      expect((resultado.single[0]! as DateTime).isAfter(inicio), isTrue);
    });
  });

  for (final caso in <(String, Map<String, Object?>, String)>[
    ('quantidade zero', {'quantidade': '0', 'posterior': '5'}, '23514'),
    ('quantidade negativa', {'quantidade': '-1', 'posterior': '6'}, '23514'),
    ('quantidade NaN', {'quantidade': 'NaN'}, '23514'),
    ('anterior NaN', {'anterior': 'NaN'}, '23514'),
    ('posterior NaN', {'posterior': 'NaN'}, '23514'),
    ('saldo anterior negativo', {'anterior': '-1'}, '23514'),
    ('saldo posterior negativo', {'posterior': '-1'}, '23514'),
    ('saldos inconsistentes', {'posterior': '3.99'}, '23514'),
    ('tipo fora do escopo', {'tipo': 'entrada'}, '23514'),
    ('quantidade infinita', {'quantidade': 'Infinity'}, '22003'),
    ('saldo anterior infinito', {'anterior': 'Infinity'}, '22003'),
    ('saldo posterior infinito', {'posterior': '-Infinity'}, '22003'),
    ('limite excedido', {'anterior': '10000000000.00'}, '22003'),
    ('obra de outra empresa', {'obra': 2, 'pedido': 2}, '23503'),
    ('produto de outra empresa', {'produto': 2}, '23503'),
    ('aprovador de outra empresa', {'usuario': 2}, '23503'),
    ('pedido de outra obra da mesma empresa', {'pedido': 3}, '23503'),
    ('pedido de outra empresa', {'pedido': 2}, '23503'),
    ('campo obrigatorio', {'tipo': null}, '23502'),
  ]) {
    test('banco rejeita ${caso.$1}', () async {
      await expectLater(inserir(caso.$2), throwsA(codigo(caso.$3)));
      expect(
        (await sql('SELECT count(*) FROM movimentacao_estoque')).single[0],
        0,
      );
    });
  }

  test(
    'limite decimal e centesimos sao exatos; duplicidade e barrada no banco',
    () async {
      await inserir({
        'quantidade': '0.01',
        'anterior': '9999999999.99',
        'posterior': '9999999999.98',
      });
      await expectLater(inserir(), throwsA(codigo('23505')));
      expect(
        (await sql(
          'SELECT saldo_anterior::text,saldo_posterior::text '
          'FROM movimentacao_estoque',
        )).single.toList(),
        ['9999999999.99', '9999999999.98'],
      );
    },
  );

  for (final tabela in ['pedido', 'produto', 'usuario', 'obra']) {
    test('historico impede excluir $tabela referenciado', () async {
      await inserir();
      // Remove itens, saldos e logs antes de tentar excluir o cadastro.
      await simples(
        'DELETE FROM item_pedido; DELETE FROM estoque; '
        'DELETE FROM log_sistema;',
      );
      await expectLater(
        sql('DELETE FROM $tabela WHERE id=1'),
        throwsA(codigo('23503')),
      );
      expect(
        (await sql('SELECT count(*) FROM movimentacao_estoque')).single[0],
        1,
      );
    });
  }

  test(
    'consulta por periodo, obra, produto e aprovador isola empresa e unidades',
    () async {
      // Datas fixas da fixture administrativa. A API nao aceita datas.
      await inserir();
      await inserir({
        'pedido': 4,
        'produto': 3,
        'nome': 'Areia',
        'unidade': 'kg',
        'protocolo': 'AUD-4',
      });
      await inserir({
        'empresa': 2,
        'obra': 2,
        'produto': 2,
        'pedido': 2,
        'usuario': 2,
      });
      await sql(
        "UPDATE movimentacao_estoque SET ocorrido_em='2026-10-01 00:00:00-03'",
      );
      await inserir({'pedido': 3, 'obra': 3});
      await sql(
        'UPDATE movimentacao_estoque '
        "SET ocorrido_em='2026-11-01 00:00:00-03' WHERE pedido_id=3",
      );
      for (final filtro in [
        '',
        'AND obra_id=1',
        'AND produto_id=1',
        'AND registrado_por_usuario_id=1',
      ]) {
        final resultado = await sql('''
        SELECT produto_id,unidade,quantidade::text FROM movimentacao_estoque
        WHERE empresa_id=1 AND ocorrido_em >= '2026-10-01 00:00:00-03'::timestamptz
          AND ocorrido_em < '2026-11-01 00:00:00-03'::timestamptz $filtro
        ORDER BY ocorrido_em DESC,id DESC
      ''');
        expect(resultado, hasLength(filtro == 'AND produto_id=1' ? 1 : 2));
        expect(resultado.every((r) => r[0] != 2), isTrue);
        expect(
          resultado.map((r) => r[1]).toSet(),
          filtro == 'AND produto_id=1' ? {'saco'} : {'saco', 'kg'},
        );
      }
    },
  );
}
