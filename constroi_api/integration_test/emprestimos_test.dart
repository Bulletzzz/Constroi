import 'dart:convert';
import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/conexao_api.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../routes/emprestimos/[id].dart' as devolucao;
import '../routes/emprestimos/_middleware.dart' as protecao;
import '../routes/emprestimos/index.dart' as emprestimos;
import '../routes/equipamentos/[id].dart' as equipamento;
import '../routes/equipamentos/_middleware.dart' as protecao_equipamento;

void main() {
  late Pool<void> banco;
  Pool<void>? bancoHttp;
  late String url;
  late HttpServer servidor;
  late HttpClient cliente;
  const segredo = 'emprestimos-local-descartavel';

  Future<Result> sql(String texto, [Map<String, Object?>? parametros]) =>
      banco.execute(Sql.named(texto), parameters: parametros);
  Future<void> simples(String texto) async {
    await banco.execute(texto, queryMode: QueryMode.simple);
  }

  Future<({int status, Map<String, dynamic> dados})> chamar(
    String metodo,
    String caminho, {
    Object? corpo,
    String? bruto,
    Nivel? nivel = Nivel.engenheiro,
    int autor = 2,
    int empresa = 1,
  }) async {
    final req = await cliente.openUrl(
      metodo,
      Uri.parse('http://127.0.0.1:${servidor.port}$caminho'),
    );
    if (nivel != null) {
      final token = JWT({
        'empresa_id': empresa,
        'tipo': nivel.name,
      }, subject: '$autor').sign(SecretKey(segredo));
      req.headers.set('authorization', 'Bearer $token');
    }
    if (corpo != null || bruto != null) {
      req.headers.contentType = ContentType.json;
      req.write(bruto ?? jsonEncode(corpo));
    }
    final res = await req.close().timeout(const Duration(seconds: 15));
    final texto = await utf8.decoder.bind(res).join();
    Map<String, dynamic> dados;
    try {
      dados = jsonDecode(texto) as Map<String, dynamic>;
    } on Object {
      dados = {'texto': texto};
    }
    return (status: res.statusCode, dados: dados);
  }

  Map<String, dynamic> corpo({
    Object? equipamentoId = 1,
    Object? usuarioId = 3,
    Object? obraId = 1,
    Object? dias = 2,
  }) => {
    'emprestimo': {
      'equipamento_id': equipamentoId,
      'usuario_id': usuarioId,
      'obra_id': obraId,
      'dias': dias,
      'empresa_id': 999,
      'status': 'devolvido',
      'data_emprestimo': '2000-01-01',
      'data_prevista': '2000-01-02',
    },
  };

  Future<({int status, Map<String, dynamic> dados})> criar({int id = 1}) =>
      chamar('POST', '/emprestimos', corpo: corpo(equipamentoId: id));
  Future<({int status, Map<String, dynamic> dados})> devolver(Object? id) =>
      chamar(
        'PATCH',
        '/emprestimos/$id',
        corpo: {
          'emprestimo': {'status': 'devolvido'},
        },
      );
  Future<Map<String, Object?>> estado() async => {
    'emprestimos': (await sql(
      'SELECT * FROM emprestimo ORDER BY id',
    )).map((r) => r.toList()).toList(),
    'equipamentos': (await sql(
      'SELECT * FROM equipamento ORDER BY id',
    )).map((r) => r.toList()).toList(),
    'logs': (await sql(
      'SELECT * FROM log_sistema ORDER BY id',
    )).map((r) => r.toList()).toList(),
  };

  Future<void> falharLog() => simples(r'''
    CREATE FUNCTION falha_emprestimo_teste() RETURNS trigger AS $$
    BEGIN RAISE EXCEPTION 'falha de log para testar rollback'; END;
    $$ LANGUAGE plpgsql;
    CREATE TRIGGER falha_emprestimo_log BEFORE INSERT ON log_sistema
    FOR EACH ROW EXECUTE FUNCTION falha_emprestimo_teste();
  ''');

  Future<List<({int status, Map<String, dynamic> dados})>> disputar(
    List<Future<({int status, Map<String, dynamic> dados})> Function()> acoes,
  ) async {
    final bloqueador = Pool<void>.withUrl(url);
    late Future<List<({int status, Map<String, dynamic> dados})>> respostas;
    try {
      await bloqueador.runTx((tx) async {
        await tx.execute('SELECT id FROM equipamento WHERE id=1 FOR UPDATE');
        respostas = Future.wait(acoes.map((acao) => acao()));
        final prazo = Stopwatch()..start();
        var bloqueados = 0;
        while (prazo.elapsed < const Duration(seconds: 7)) {
          bloqueados =
              (await sql('''
            SELECT count(*) FROM pg_stat_activity
            WHERE datname=current_database() AND wait_event_type='Lock'
              AND query LIKE '%FROM equipamento%'
          ''')).single[0]!
                  as int;
          if (bloqueados >= acoes.length) break;
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        expect(
          bloqueados,
          greaterThanOrEqualTo(acoes.length),
          reason: 'Todas as requisicoes devem esperar um lock real.',
        );
      });
      return await respostas;
    } finally {
      await bloqueador.close();
    }
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
    banco = Pool<void>.withUrl(
      uri
          .replace(
            queryParameters: {
              ...uri.queryParameters,
              'max_connection_count': '20',
            },
          )
          .toString(),
    );
    addTearDown(() => banco.close());
    await simples('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
    await simples(await File('../Database/schema.sql').readAsString());
    final router = Router()
      ..all('/emprestimos', protecao.middleware(emprestimos.onRequest))
      ..all(
        '/emprestimos/<id>',
        (RequestContext c, String id) =>
            protecao.middleware((c) => devolucao.onRequest(c, id))(c),
      )
      ..all(
        '/equipamentos/<id>',
        (RequestContext c, String id) => protecao_equipamento.middleware(
          (c) => equipamento.onRequest(c, id),
        )(c),
      );
    servidor = await serve(
      router.call
          .use(provider<Pool<void>>((_) => bancoHttp ?? banco))
          .use(
            provider<UsuarioAutenticado?>(
              (c) => autenticar(c.request.headers['authorization'], segredo),
            ),
          ),
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => servidor.close(force: true));
    cliente = HttpClient();
    addTearDown(() => cliente.close(force: true));
  });

  setUp(() async {
    bancoHttp = null;
    await simples('''
      DROP FUNCTION IF EXISTS falha_emprestimo_teste() CASCADE;
      TRUNCATE empresa RESTART IDENTITY CASCADE;
      INSERT INTO empresa(id,nome,cnpj) VALUES (1,'A','A'),(2,'B','B');
      INSERT INTO usuario(id,empresa_id,nome,email,senha_hash,tipo,ativo) VALUES
        (1,1,'Master A','m@a','hash','master',true),
        (2,1,'Eng A','e@a','hash','engenheiro',true),
        (3,1,'Responsavel A','p@a','hash','pedreiro',true),
        (4,2,'Master B','m@b','hash','master',true),
        (5,2,'Responsavel B','p@b','hash','pedreiro',true),
        (6,1,'Inativo A','i@a','hash','pedreiro',false);
      INSERT INTO obra(id,empresa_id,nome,endereco,status) VALUES
        (1,1,'Obra A','Rua','ativa'),(2,2,'Obra B','Rua','ativa');
      INSERT INTO equipamento(id,empresa_id,nome,patrimonio,status) VALUES
        (1,1,'Betoneira A','B1','disponivel'),
        (2,1,'Furadeira A','F1','disponivel'),
        (3,2,'Betoneira B','B1','disponivel');
    ''');
  });

  test('POST respeita contrato, prazo, empresa e autor do log', () async {
    final res = await criar();
    expect(res.status, 201, reason: '${res.dados}');
    expect(res.dados.keys.toSet(), {
      'id',
      'equipamento_id',
      'equipamento_nome',
      'usuario_id',
      'responsavel_nome',
      'obra_id',
      'obra_nome',
      'data_emprestimo',
      'data_prevista',
      'data_devolucao',
      'status',
      'atrasado',
    });
    expect(res.dados['equipamento_nome'], 'Betoneira A');
    expect(res.dados['responsavel_nome'], 'Responsavel A');
    expect(res.dados['obra_nome'], 'Obra A');
    expect(res.dados['status'], 'aberto');
    expect(res.dados['atrasado'], false);
    expect(res.dados['data_devolucao'], isNull);
    expect(
      DateTime.parse(
        '${res.dados['data_prevista']}',
      ).difference(DateTime.parse('${res.dados['data_emprestimo']}')),
      const Duration(days: 2),
    );
    expect((await sql('SELECT empresa_id FROM emprestimo')).single[0], 1);
    expect(
      (await sql('SELECT status FROM equipamento WHERE id=1')).single[0],
      'em_uso',
    );
    final acaoEsperada =
        'EMPRESTIMO_EQUIPAMENTO emprestimo=${res.dados['id']} '
        'equipamento=1 usuario=3 obra=1 dias=2';
    expect(
      (await sql(
        'SELECT empresa_id,usuario_id,acao FROM log_sistema',
      )).single.toList(),
      [1, 2, acaoEsperada],
    );
  });

  test(
    'devolve, empresta novamente e recusa repetir a devolucao antiga',
    () async {
      final primeiro = await criar();
      final devolvido = await devolver(primeiro.dados['id']);
      expect(devolvido.status, 200, reason: '${devolvido.dados}');
      expect(devolvido.dados['status'], 'devolvido');
      expect(devolvido.dados['data_devolucao'], isNotNull);
      expect(devolvido.dados['atrasado'], false);
      expect(
        (await sql('SELECT status FROM equipamento WHERE id=1')).single[0],
        'disponivel',
      );
      final segundo = await criar();
      expect(segundo.status, 201);
      final antes = await estado();
      expect((await devolver(primeiro.dados['id'])).status, 409);
      expect(await estado(), antes);
      expect(
        (await sql('SELECT status FROM equipamento WHERE id=1')).single[0],
        'em_uso',
      );
    },
  );

  test(
    'middleware exige engenheiro em todas as rotas e permite master',
    () async {
      final criado = await criar();
      final antes = await estado();
      for (final nivel in <Nivel?>[null, Nivel.pedreiro]) {
        final esperado = nivel == null ? 401 : 403;
        expect(
          (await chamar('GET', '/emprestimos', nivel: nivel)).status,
          esperado,
        );
        expect(
          (await chamar(
            'POST',
            '/emprestimos',
            corpo: corpo(),
            nivel: nivel,
          )).status,
          esperado,
        );
        expect(
          (await chamar(
            'PATCH',
            '/emprestimos/${criado.dados['id']}',
            corpo: {
              'emprestimo': {'status': 'devolvido'},
            },
            nivel: nivel,
          )).status,
          esperado,
        );
      }
      expect(await estado(), antes);
      expect(
        (await chamar(
          'POST',
          '/emprestimos',
          corpo: corpo(equipamentoId: 2),
          nivel: Nivel.master,
          autor: 1,
        )).status,
        201,
      );
    },
  );

  test('dados, IDs, prazo e status invalidos nao escrevem', () async {
    final antes = await estado();
    for (final valor in [null, '1', 0, -1, 1.5, true, 2147483648]) {
      for (final dados in [
        corpo(equipamentoId: valor),
        corpo(usuarioId: valor),
        corpo(obraId: valor),
        corpo(dias: valor),
      ]) {
        expect(
          (await chamar('POST', '/emprestimos', corpo: dados)).status,
          400,
        );
      }
    }
    for (final dados in [
      <String, dynamic>{},
      <Object?>[],
      {'emprestimo': 'erro'},
    ]) {
      expect((await chamar('POST', '/emprestimos', corpo: dados)).status, 400);
    }
    expect((await chamar('POST', '/emprestimos', bruto: '{')).status, 400);
    expect(
      (await chamar(
        'POST',
        '/emprestimos',
        corpo: corpo(dias: 2147483647),
      )).status,
      400,
    );
    for (final id in ['0', '-1', 'abc', '2147483648']) {
      expect((await devolver(id)).status, 400);
    }
    for (final dados in [
      <String, dynamic>{},
      {'emprestimo': null},
      {
        'emprestimo': {'status': 'aberto'},
      },
      {
        'emprestimo': {'status': 1},
      },
    ]) {
      expect(
        (await chamar('PATCH', '/emprestimos/1', corpo: dados)).status,
        400,
      );
    }
    expect((await chamar('PATCH', '/emprestimos/1', bruto: '{')).status, 400);
    expect((await chamar('DELETE', '/emprestimos')).status, 405);
    expect((await chamar('GET', '/emprestimos/1')).status, 405);
    expect(await estado(), antes);
  });

  test('dias nao tem limite comercial de 30 ou 365', () async {
    final res = await chamar('POST', '/emprestimos', corpo: corpo(dias: 4000));
    expect(res.status, 201, reason: '${res.dados}');
    expect(
      DateTime.parse(
        '${res.dados['data_prevista']}',
      ).difference(DateTime.parse('${res.dados['data_emprestimo']}')),
      const Duration(days: 4000),
    );
  });

  test(
    'referencias alheias, inexistentes ou responsavel inativo retornam 404',
    () async {
      final antes = await estado();
      for (final dados in [
        corpo(equipamentoId: 3),
        corpo(equipamentoId: 999),
        corpo(usuarioId: 4),
        corpo(usuarioId: 999),
        corpo(usuarioId: 6),
        corpo(obraId: 2),
        corpo(obraId: 999),
      ]) {
        expect(
          (await chamar('POST', '/emprestimos', corpo: dados)).status,
          404,
        );
      }
      expect((await devolver(999)).status, 404);
      expect(await estado(), antes);
      final alheio = await chamar(
        'POST',
        '/emprestimos',
        corpo: corpo(equipamentoId: 3, usuarioId: 5, obraId: 2),
        empresa: 2,
        autor: 4,
        nivel: Nivel.master,
      );
      expect(alheio.status, 201);
      final comAlheio = await estado();
      expect((await devolver(alheio.dados['id'])).status, 404);
      expect(await estado(), comAlheio);
    },
  );

  test('equipamento fora de disponivel nao pode ser emprestado', () async {
    for (final status in ['em_uso', 'manutencao', 'quebrado', 'inativo']) {
      await sql('UPDATE equipamento SET status=@status WHERE id=1', {
        'status': status,
      });
      final antes = await estado();
      expect((await criar()).status, 409);
      expect(await estado(), antes);
    }
  });

  test('GET filtra equipamento e status, pagina e isola empresas', () async {
    final primeiro = await criar();
    final segundo = await criar(id: 2);
    await devolver(segundo.dados['id']);
    await chamar(
      'POST',
      '/emprestimos',
      corpo: corpo(equipamentoId: 3, usuarioId: 5, obraId: 2),
      empresa: 2,
      autor: 4,
      nivel: Nivel.master,
    );
    final todos = await chamar('GET', '/emprestimos');
    expect((todos.dados['emprestimos'] as List).map((e) => (e as Map)['id']), [
      segundo.dados['id'],
      primeiro.dados['id'],
    ]);
    final filtrado = await chamar(
      'GET',
      '/emprestimos?equipamento_id=1&status=aberto',
    );
    expect((filtrado.dados['emprestimos'] as List).single, primeiro.dados);
    expect(
      (await chamar(
        'GET',
        '/emprestimos?equipamento_id=3',
      )).dados['emprestimos'],
      isEmpty,
    );
    final paginado = await chamar('GET', '/emprestimos?limit=1&offset=1');
    expect((paginado.dados['emprestimos'] as List).single, primeiro.dados);
    for (final query in [
      'equipamento_id=0',
      'equipamento_id=abc',
      'equipamento_id=2147483648',
      'status=atrasado',
      'status=',
      'limit=0',
      'limit=201',
      'offset=-1',
      'offset=2147483648',
    ]) {
      expect((await chamar('GET', '/emprestimos?$query')).status, 400);
    }
  });

  test('atrasado e calculado somente para emprestimo aberto', () async {
    final criado = await criar();
    await sql('''
      UPDATE emprestimo SET data_emprestimo=CURRENT_TIMESTAMP-INTERVAL '3 days',
        data_prevista=CURRENT_TIMESTAMP-INTERVAL '1 day'
    ''');
    final abertos = await chamar('GET', '/emprestimos?status=aberto');
    expect(
      ((abertos.dados['emprestimos'] as List).single as Map)['atrasado'],
      true,
    );
    final devolvido = await devolver(criado.dados['id']);
    expect(devolvido.status, 200);
    expect(devolvido.dados['atrasado'], false);
  });

  test(
    'indice parcial barra duplicidade com status do cadastro adulterado',
    () async {
      await criar();
      await sql("UPDATE equipamento SET status='disponivel' WHERE id=1");
      final antes = await estado();
      expect((await criar()).status, 409);
      expect(await estado(), antes);
      await expectLater(
        sql('''
      INSERT INTO emprestimo(empresa_id,equipamento_id,usuario_id,obra_id,data_prevista,status)
      VALUES (1,1,3,1,CURRENT_TIMESTAMP+INTERVAL '1 day','aberto')
    '''),
        throwsA(
          isA<ServerException>()
              .having((e) => e.code, 'SQLSTATE', '23505')
              .having(
                (e) => e.constraintName,
                'indice',
                'ux_emprestimo_equipamento_aberto',
              ),
        ),
      );
    },
  );

  test('FKs compostas e CHECKs rejeitam dados invalidos no banco', () async {
    for (final referencias in ['2,1,3,1', '1,3,3,1', '1,1,5,1', '1,1,3,2']) {
      await expectLater(
        sql('''
        INSERT INTO emprestimo(empresa_id,equipamento_id,usuario_id,obra_id,data_prevista,status)
        VALUES ($referencias,CURRENT_TIMESTAMP+INTERVAL '1 day','aberto')
      '''),
        throwsA(
          isA<ServerException>().having((e) => e.code, 'SQLSTATE', '23503'),
        ),
      );
    }
    for (final valores in [
      "CURRENT_TIMESTAMP+INTERVAL '1 day',NULL,'qualquer'",
      "CURRENT_TIMESTAMP-INTERVAL '1 day',NULL,'aberto'",
      "CURRENT_TIMESTAMP+INTERVAL '1 day',NULL,'devolvido'",
      "CURRENT_TIMESTAMP+INTERVAL '1 day',CURRENT_TIMESTAMP,'aberto'",
      "'infinity'::timestamptz,NULL,'aberto'",
    ]) {
      await expectLater(
        sql('''
        INSERT INTO emprestimo(empresa_id,equipamento_id,usuario_id,obra_id,data_prevista,data_devolucao,status)
        VALUES (1,1,3,1,$valores)
      '''),
        throwsA(
          isA<ServerException>().having((e) => e.code, 'SQLSTATE', '23514'),
        ),
      );
    }
    expect((await sql('SELECT count(*) FROM emprestimo')).single[0], 0);
  });

  test(
    'oito POSTs bloqueados no mesmo equipamento confirmam exatamente um',
    () async {
      final respostas = await disputar(
        List.generate(
          8,
          (_) => criar,
        ),
      );
      expect(respostas.where((r) => r.status == 201), hasLength(1));
      expect(respostas.where((r) => r.status == 409), hasLength(7));
      expect((await sql('SELECT count(*) FROM emprestimo')).single[0], 1);
      expect((await sql('SELECT count(*) FROM log_sistema')).single[0], 1);
    },
  );

  test(
    'duas devolucoes bloqueadas confirmam uma vez e mantem um unico log',
    () async {
      final criado = await criar();
      final respostas = await disputar([
        () => devolver(criado.dados['id']),
        () => devolver(criado.dados['id']),
      ]);
      expect(respostas.map((r) => r.status).toList()..sort(), [200, 409]);
      expect(
        (await sql(
          'SELECT count(*) FROM log_sistema '
          "WHERE acao LIKE 'DEVOLUCAO_EQUIPAMENTO %'",
        )).single[0],
        1,
      );
      expect(
        (await sql('SELECT status FROM equipamento WHERE id=1')).single[0],
        'disponivel',
      );
    },
  );

  test(
    'emprestimo e devolucao concorrentes seguem a mesma ordem de locks',
    () async {
      final criado = await criar();
      final respostas = await disputar([
        () => devolver(criado.dados['id']),
        criar,
      ]);
      expect(respostas[0].status, 200);
      expect(respostas[1].status, anyOf(201, 409));
      final abertos = (await sql(
        "SELECT count(*) FROM emprestimo WHERE status='aberto'",
      )).single[0];
      expect(abertos, respostas[1].status == 201 ? 1 : 0);
      expect(
        (await sql('SELECT status FROM equipamento WHERE id=1')).single[0],
        abertos == 1 ? 'em_uso' : 'disponivel',
      );
    },
  );

  test(
    'PATCH do cadastro nao libera equipamento com emprestimo aberto',
    () async {
      await criar();
      final antes = await estado();
      for (final status in [
        'disponivel',
        'manutencao',
        'inativo',
        'quebrado',
      ]) {
        expect(
          (await chamar(
            'PATCH',
            '/equipamentos/1',
            corpo: {
              'equipamento': {'status': status},
            },
          )).status,
          409,
        );
      }
      expect(await estado(), antes);
      expect(
        (await chamar(
          'PATCH',
          '/equipamentos/1',
          corpo: {
            'equipamento': {'nome': 'Nome atualizado'},
          },
        )).status,
        200,
      );
    },
  );

  test(
    'PATCH do equipamento e POST concorrentes nao deixam status divergente',
    () async {
      final respostas = await disputar([
        () => chamar(
          'PATCH',
          '/equipamentos/1',
          corpo: {
            'equipamento': {'status': 'manutencao'},
          },
        ),
        criar,
      ]);
      expect([
        respostas[0].status,
        respostas[1].status,
      ], anyOf(equals([200, 409]), equals([409, 201])));
      expect(
        (await sql('SELECT status FROM equipamento WHERE id=1')).single[0],
        respostas[1].status == 201 ? 'em_uso' : 'manutencao',
      );
    },
  );

  test('falha no log reverte criacao e devolucao integralmente', () async {
    final vazio = await estado();
    await falharLog();
    expect((await criar()).status, 500);
    expect(await estado(), vazio);
    await simples('DROP FUNCTION falha_emprestimo_teste() CASCADE');
    final criado = await criar();
    final aberto = await estado();
    await falharLog();
    expect((await devolver(criado.dados['id'])).status, 500);
    expect(await estado(), aberto);
  });

  test(
    'funciona com o papel real restrito e limite de transacao ativado',
    () async {
      await simples(
        await File('../Database/infra/auditoria_papeis.sql').readAsString(),
      );
      await sql(
        "ALTER ROLE constroi_api_execucao PASSWORD 'Emprestimo#Local123'",
      );
      final uri = Uri.parse(url);
      final restrito = criarPoolApi(
        uri
            .replace(userInfo: 'constroi_api_execucao:Emprestimo%23Local123')
            .toString(),
        conexaoEstrita: true,
      );
      bancoHttp = restrito;
      addTearDown(restrito.close);
      final criado = await criar();
      expect(criado.status, 201, reason: '${criado.dados}');
      expect((await devolver(criado.dados['id'])).status, 200);
    },
  );
}
