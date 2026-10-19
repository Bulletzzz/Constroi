import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/baixa_estoque.dart';
import 'package:constroi_api/conexao_api.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

void main() {
  late Pool<void> administrador;
  late String url;
  late String urlApi;
  late String papeis;
  Pool<void> poolEstrito(
    String conexao, {
    int limiteMs = limiteMaximoTransacaoMs,
  }) => criarPoolApi(conexao, conexaoEstrita: true, limiteMs: limiteMs);
  Future<void> configurar() =>
      administrador.execute(papeis, queryMode: QueryMode.simple);
  Future<ProcessResult> migrar({String? conexao}) => Process.run(
    Platform.resolvedExecutable,
    ['run', 'bin/migrate.dart'],
    environment: {
      'MIGRATION_DATABASE_URL': conexao ?? url,
      'MIGRATION_ENV_FILE': '.env.migrations-inexistente-teste',
      'DATABASE_URL': urlApi,
    },
  );
  setUpAll(() async {
    url = Platform.environment['CONSTROI_TEST_DATABASE_URL'] ?? '';
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['postgres', 'postgresql'].contains(uri.scheme) ||
        !['localhost', '127.0.0.1', '::1'].contains(uri.host) ||
        uri.pathSegments.length != 1 ||
        !uri.pathSegments.single.startsWith('constroi_test_')) {
      throw StateError(
        'Use banco local descartavel constroi_test_*. Nunca le .env.',
      );
    }
    urlApi = uri.replace(userInfo: 'constroi_api_execucao').toString();
    administrador = Pool<void>.withUrl(url);
    addTearDown(() => administrador.close());
    await administrador.execute(
      'DROP SCHEMA public CASCADE; CREATE SCHEMA public;',
      queryMode: QueryMode.simple,
    );
    final primeira = await migrar();
    expect(primeira.exitCode, 0, reason: '${primeira.stderr}');
    final segunda = await migrar();
    expect(segunda.exitCode, 0, reason: '${segunda.stderr}');
    expect('${segunda.stdout}', isNot(contains('Aplicada ')));
    papeis = await File(
      '../Database/infra/auditoria_papeis.sql',
    ).readAsString();
    await configurar();
    // Fixtures de permissoes, nao e a migration da auditoria (card 83).
    await administrador.execute('''
      CREATE TABLE movimentacao_estoque (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,evento text NOT NULL);
      CREATE TABLE infra_bloqueio (id int PRIMARY KEY,valor int NOT NULL);
      INSERT INTO infra_bloqueio VALUES (1,0);
    ''', queryMode: QueryMode.simple);
    final app = poolEstrito(urlApi);
    try {
      await app.execute(
        "INSERT INTO movimentacao_estoque(evento) VALUES ('default_acl')",
      );
    } finally {
      await app.close();
    }
  });
  setUp(() async {
    await configurar();
    await administrador.execute(
      'TRUNCATE empresa RESTART IDENTITY CASCADE; '
      'TRUNCATE movimentacao_estoque; UPDATE infra_bloqueio SET valor=0;',
      queryMode: QueryMode.simple,
    );
  });

  Future<void> semMovimentos() async {
    expect(
      (await administrador.execute(
        'SELECT count(*) FROM movimentacao_estoque',
      )).single[0],
      0,
    );
  }

  test(
    'modo padrao aceita o dono atual sem exigir timeout provisionado',
    () async {
      final app = criarPoolApi(url);
      addTearDown(app.close);
      final estado = await app.execute('''
      SELECT r.rolsuper, current_setting('transaction_timeout')
      FROM pg_roles r WHERE r.rolname=current_user
    ''');
      expect(estado.single[0], isTrue);
      expect(estado.single[1], '0');
      await app.runTx((tx) => tx.execute('SELECT 1'));
    },
  );
  test(
    'flag desligada preserva timeout zero; ligada recusa a mesma credencial',
    () async {
      await administrador.execute(r'''
      DO $$ BEGIN EXECUTE format(
        'ALTER ROLE constroi_api_execucao IN DATABASE %I '
        'SET transaction_timeout=0',current_database()); END $$;
    ''');
      final atual = criarPoolApi(urlApi);
      final estrito = criarPoolApi(urlApi, conexaoEstrita: true);
      addTearDown(atual.close);
      addTearDown(estrito.close);
      expect(
        (await atual.execute('SHOW transaction_timeout')).single[0],
        '0',
      );
      await expectLater(
        estrito.execute('SELECT 1'),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'papel real permite INSERT/SELECT e recusa UPDATE/DELETE/TRUNCATE e DDL',
    () async {
      final app = poolEstrito(urlApi);
      addTearDown(app.close);
      await app.execute(
        "INSERT INTO movimentacao_estoque(evento) VALUES ('ok')",
      );
      expect(
        (await app.execute(
          'SELECT evento FROM movimentacao_estoque',
        )).single[0],
        'ok',
      );
      for (final comando in [
        "UPDATE movimentacao_estoque SET evento='nao'",
        'DELETE FROM movimentacao_estoque',
        'TRUNCATE movimentacao_estoque',
        'CREATE TABLE proibida(id int)',
        'DELETE FROM schema_migrations',
      ]) {
        await expectLater(
          app.execute(comando),
          throwsA(
            isA<ServerException>().having((e) => e.code, 'sqlstate', '42501'),
          ),
        );
      }
    },
  );
  test(
    'pool rejeita usuario privilegiado e permissao de UPDATE indevida',
    () async {
      final dono = poolEstrito(url);
      addTearDown(dono.close);
      await expectLater(dono.execute('SELECT 1'), throwsA(isA<StateError>()));
      await administrador.execute(
        'GRANT UPDATE ON movimentacao_estoque TO constroi_api_execucao',
      );
      final app = poolEstrito(urlApi);
      addTearDown(app.close);
      await expectLater(app.execute('SELECT 1'), throwsA(isA<StateError>()));
    },
  );
  test('varias queries curtas nao reiniciam o limite da transacao', () async {
    final app = poolEstrito(urlApi, limiteMs: 300);
    addTearDown(app.close);
    final relogio = Stopwatch()..start();
    await expectLater(
      app.runTx((tx) async {
        await tx.execute(
          "INSERT INTO movimentacao_estoque(evento) VALUES ('rollback')",
        );
        for (var i = 0; i < 10; i++) {
          await tx.execute('SELECT pg_sleep(0.1)');
        }
      }),
      throwsA(isA<ServerException>().having((e) => e.code, 'timeout', '25P04')),
    );
    expect(relogio.elapsed, lessThan(const Duration(seconds: 5)));
    await semMovimentos();
    // O pool descarta a conexao terminada e valida a nova.
    expect((await app.execute('SELECT 1')).single[0], 1);
  });
  test(
    'limite inclui inatividade entre duas queries e reverte escrita',
    () async {
      final app = poolEstrito(urlApi, limiteMs: 300);
      addTearDown(app.close);
      await expectLater(
        app.runTx((tx) async {
          await tx.execute(
            "INSERT INTO movimentacao_estoque(evento) VALUES ('ocioso')",
          );
          final pid = (await tx.execute('SELECT pg_backend_pid()')).single[0];
          await Future<void>.delayed(const Duration(milliseconds: 600));
          final vivos = await administrador.execute(
            Sql.named('SELECT count(*) FROM pg_stat_activity WHERE pid=@pid'),
            parameters: {'pid': pid},
          );
          expect(
            vivos.single[0],
            0,
            reason: 'Servidor deve encerrar a sessao ociosa',
          );
          await tx.execute('SELECT 1');
        }),
        throwsA(isA<PgException>()),
      );
      await semMovimentos();
    },
  );
  test('limite inclui espera real por lock e reverte o movimento', () async {
    final app = poolEstrito(urlApi, limiteMs: 700);
    addTearDown(app.close);
    await administrador.runTx((bloqueador) async {
      await bloqueador.execute(
        'SELECT * FROM infra_bloqueio WHERE id=1 FOR UPDATE',
      );
      final erro = expectLater(
        app.runTx((tx) async {
          await tx.execute(
            "INSERT INTO movimentacao_estoque(evento) VALUES ('lock')",
          );
          await tx.execute('UPDATE infra_bloqueio SET valor=1 WHERE id=1');
        }),
        throwsA(
          isA<ServerException>().having((e) => e.code, 'timeout', '25P04'),
        ),
      );
      var viuLock = false;
      for (var i = 0; i < 20; i++) {
        final locks = await administrador.execute(
          'SELECT count(*) FROM pg_stat_activity '
          'WHERE datname=current_database() '
          "AND application_name='constroi-api' "
          "AND wait_event_type='Lock'",
        );
        if ((locks.single[0]! as int) > 0) {
          viuLock = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(viuLock, isTrue, reason: 'Requisicao deve esperar um lock real');
      await erro;
    });
    await semMovimentos();
    expect(
      (await administrador.execute(
        'SELECT valor FROM infra_bloqueio',
      )).single[0],
      0,
    );
  });
  test(
    'migration nao usa DATABASE_URL como fallback nem imprime segredo',
    () async {
      final resultado = await migrar(conexao: '');
      expect(resultado.exitCode, isNot(0));
      expect('${resultado.stderr}', contains('MIGRATION_DATABASE_URL'));
      expect('${resultado.stderr}', isNot(contains(url)));
    },
  );
  test('limite desligado no papel impede abrir a conexao da API', () async {
    await administrador.execute(r'''
      DO $$ BEGIN EXECUTE format(
        'ALTER ROLE constroi_api_execucao IN DATABASE %I '
        'SET transaction_timeout=0',current_database()); END $$;
    ''');
    final app = poolEstrito(urlApi);
    addTearDown(app.close);
    await expectLater(app.execute('SELECT 1'), throwsA(isA<StateError>()));
  });
  test('guard tambem detecta UPDATE concedido somente numa coluna', () async {
    await administrador.execute(
      'GRANT UPDATE(evento) ON movimentacao_estoque TO constroi_api_execucao',
    );
    addTearDown(
      () => administrador.execute(
        'REVOKE UPDATE(evento) ON movimentacao_estoque '
        'FROM constroi_api_execucao',
      ),
    );
    final app = poolEstrito(urlApi);
    addTearDown(app.close);
    await expectLater(app.execute('SELECT 1'), throwsA(isA<StateError>()));
  });
  test('diagnostico publica limite e margem sem expor URL', () async {
    final resultado = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'bin/verificar_auditoria.dart'],
      environment: {
        'API_ENV_FILE': '.env.api-inexistente-teste',
        'DATABASE_URL': urlApi,
        'DATABASE_TRANSACTION_TIMEOUT_MS': '30000',
        'AUDITORIA_CONEXAO_ESTRITA': 'false',
      },
    );
    expect(resultado.exitCode, 0, reason: '${resultado.stderr}');
    final json = jsonDecode('${resultado.stdout}') as Map<String, dynamic>;
    expect(json['limite_transacao_ms'], 30000);
    expect(json['margem_fechamento_ms'], 31000);
    expect('${resultado.stdout}', isNot(contains(urlApi)));
  });
  test(
    'diagnostico recusa dono mesmo quando a flag da API esta desligada',
    () async {
      final resultado = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'bin/verificar_auditoria.dart'],
        environment: {
          'API_ENV_FILE': '.env.api-inexistente-teste',
          'DATABASE_URL': url,
          'AUDITORIA_CONEXAO_ESTRITA': 'false',
        },
      );
      expect(resultado.exitCode, isNot(0));
      expect('${resultado.stderr}', contains('Validacao recusada'));
      expect('${resultado.stderr}', isNot(contains(url)));
      expect('${resultado.stdout}', isNot(contains('margem_fechamento_ms')));
    },
  );
  test('membership de escrita irrestrita tambem e recusada', () async {
    await administrador.execute(
      'GRANT pg_write_all_data TO constroi_api_execucao',
    );
    addTearDown(
      () => administrador.execute(
        'REVOKE pg_write_all_data FROM constroi_api_execucao',
      ),
    );
    final app = poolEstrito(urlApi);
    addTearDown(app.close);
    await expectLater(app.execute('SELECT 1'), throwsA(isA<StateError>()));
  });
  test(
    'aprovacao de estoque existente funciona com a conexao restrita',
    () async {
      await administrador.execute('''
      INSERT INTO empresa(id,nome,cnpj) VALUES (1,'Teste','1');
      INSERT INTO usuario(id,empresa_id,nome,email,senha_hash,tipo)
        VALUES (1,1,'Engenheiro','e@e','hash','engenheiro');
      INSERT INTO obra(id,empresa_id,nome,endereco,status)
        VALUES (1,1,'Obra','Rua','ativa');
      INSERT INTO produto(id,empresa_id,nome,unidade)
        VALUES (1,1,'Cimento','saco');
      INSERT INTO estoque(obra_id,produto_id,quantidade) VALUES (1,1,1);
      INSERT INTO pedido(id,usuario_id,obra_id,protocolo,status)
        VALUES (1,1,1,'TESTE-INFRA','pendente');
      INSERT INTO item_pedido(pedido_id,produto_id,quantidade) VALUES (1,1,1);
    ''', queryMode: QueryMode.simple);
      final app = poolEstrito(urlApi);
      addTearDown(app.close);
      final resposta = await aprovarPedidoComBaixa(
        app,
        pedidoId: 1,
        usuario: const UsuarioAutenticado(
          id: 1,
          empresaId: 1,
          nivel: Nivel.engenheiro,
        ),
      );
      expect(resposta['status'], 'aprovado');
      expect(
        (await app.execute('SELECT quantidade::text FROM estoque')).single[0],
        '0.00',
      );
      expect(
        (await app.execute('SELECT count(*) FROM log_sistema')).single[0],
        1,
      );
    },
  );
}
