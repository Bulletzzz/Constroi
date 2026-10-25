// CONSTROI_TEST_DATABASE_URL deve apontar para um PostgreSQL
// local descartavel, com banco chamado constroi_test_*. Nunca le o .env da API.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/baixa_estoque.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../routes/pedidos/[id].dart' as rota;
import '../routes/pedidos/_middleware.dart' as protecao;

void main() {
  late Pool<void> banco;
  late String databaseUrl;
  late HttpServer servidor;
  late HttpClient cliente;
  var sequencia = 0;
  const segredo = 'segredo-local-descartavel-de-integracao';
  const engenheiro = UsuarioAutenticado(
    id: 3,
    empresaId: 1,
    nivel: Nivel.engenheiro,
  );

  Future<Result> sql(String query, [Map<String, Object?>? parametros]) =>
      banco.execute(Sql.named(query), parameters: parametros);

  Future<int> pedido(
    List<(int, String)> itens, {
    int obra = 1,
    int usuario = 1,
    String? justificativa,
  }) async {
    final resultado = await sql(
      '''
      INSERT INTO pedido (usuario_id, obra_id, protocolo, status, justificativa)
      VALUES (@usuario, @obra, @protocolo, 'pendente', @justificativa) RETURNING id
    ''',
      {
        'usuario': usuario,
        'obra': obra,
        'protocolo': 'PED-TEST-${sequencia++}',
        'justificativa': justificativa,
      },
    );
    final id = resultado.single[0]! as int;
    for (final (produto, quantidade) in itens) {
      await sql(
        '''
        INSERT INTO item_pedido (pedido_id, produto_id, quantidade)
        VALUES (@pedido, @produto, @quantidade::numeric)
        ''',
        {'pedido': id, 'produto': produto, 'quantidade': quantidade},
      );
    }
    return id;
  }

  Future<({int status, Map<String, dynamic> dados})> decidir(
    int id, {
    String status = 'aprovado',
    Object? justificativa,
    Nivel? nivel = Nivel.engenheiro,
    int empresa = 1,
    int usuario = 3,
  }) async {
    final request = await cliente.patchUrl(
      Uri.parse('http://127.0.0.1:${servidor.port}/pedidos/$id'),
    );
    if (nivel != null) {
      final token = JWT({
        'empresa_id': empresa,
        'tipo': nivel.name,
      }, subject: '$usuario').sign(SecretKey(segredo));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'pedido': {
          'status': status,
          'justificativa': justificativa,
          'usuario_id': 999,
          'empresa_id': 999,
          'registrado_por_usuario_id': 999,
        },
      }),
    );
    final response = await request.close().timeout(const Duration(seconds: 10));
    final body = await utf8.decoder.bind(response).join();
    return (
      status: response.statusCode,
      dados: jsonDecode(body) as Map<String, dynamic>,
    );
  }

  Future<({int status, Map<String, dynamic> dados})> aprovar(
    int id, {
    Nivel? nivel = Nivel.engenheiro,
    int empresa = 1,
    int usuario = 3,
  }) => decidir(id, nivel: nivel, empresa: empresa, usuario: usuario);

  Future<Map<String, dynamic>> estado(int id) async {
    final pedido = (await sql(
      'SELECT status, justificativa, justificativa_recusa '
      'FROM pedido WHERE id = @id',
      {'id': id},
    )).single.toColumnMap();
    final saldos = await sql(
      'SELECT produto_id, quantidade::text FROM estoque '
      'WHERE obra_id = 1 ORDER BY produto_id',
    );
    final logs = await sql(
      'SELECT usuario_id, acao FROM log_sistema ORDER BY id',
    );
    final movimentos = await sql('''
      SELECT empresa_id, obra_id, produto_id, pedido_id,
             registrado_por_usuario_id, tipo, quantidade::text,
             saldo_anterior::text, saldo_posterior::text,
             protocolo_pedido, produto_nome, unidade, ocorrido_em
      FROM movimentacao_estoque ORDER BY id
    ''');
    return {
      ...pedido,
      'saldos': saldos.map((r) => r.toList()).toList(),
      'logs': logs.map((r) => r.toList()).toList(),
      'movimentos': movimentos.map((r) => r.toColumnMap()).toList(),
    };
  }

  Future<void> aguardarBloqueios(String trecho, int quantidade) async {
    final prazo = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(prazo)) {
      final resultado = await sql(
        '''
        SELECT COUNT(*) FROM pg_stat_activity
        WHERE datname = current_database() AND wait_event_type = 'Lock'
          AND query LIKE @trecho
      ''',
        {'trecho': '%$trecho%'},
      );
      if ((resultado.single[0]! as int) >= quantidade) return;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    fail(
      'As $quantidade requisicoes nao chegaram ao bloqueio PostgreSQL: $trecho',
    );
  }

  Future<List<({int status, Map<String, dynamic> dados})>> disputar(
    List<int> pedidos, {
    bool mesmoPedido = false,
    List<String>? decisoes,
  }) async {
    final bloqueador = Pool<void>.withUrl(databaseUrl);
    late Future<List<({int status, Map<String, dynamic> dados})>> respostas;
    try {
      await bloqueador.runTx((tx) async {
        await tx.execute(
          mesmoPedido
              ? Sql.named('SELECT id FROM pedido WHERE id = @pedido FOR UPDATE')
              : Sql.named(
                  'SELECT id FROM estoque WHERE obra_id = 1 '
                  'ORDER BY produto_id FOR UPDATE',
                ),
          parameters: mesmoPedido ? {'pedido': pedidos.first} : null,
        );
        respostas = Future.wait([
          for (var i = 0; i < pedidos.length; i++)
            decidir(
              pedidos[i],
              status: decisoes?[i] ?? 'aprovado',
              justificativa: 'Material desnecessario',
            ),
        ]);
        // Todas as requisicoes devem esperar um lock PostgreSQL real.
        await aguardarBloqueios(
          mesmoPedido ? 'FROM pedido p' : 'FROM estoque e',
          pedidos.length,
        );
      });
      return await respostas;
    } finally {
      await bloqueador.close();
    }
  }

  setUpAll(() async {
    databaseUrl = Platform.environment['CONSTROI_TEST_DATABASE_URL'] ?? '';
    final uri = Uri.tryParse(databaseUrl);
    if (uri == null ||
        !['postgres', 'postgresql'].contains(uri.scheme) ||
        !['localhost', '127.0.0.1', '::1'].contains(uri.host) ||
        uri.pathSegments.length != 1 ||
        !uri.pathSegments.single.startsWith('constroi_test_')) {
      throw StateError(
        'Configure CONSTROI_TEST_DATABASE_URL com um banco local '
        'descartavel chamado constroi_test_*. Esta suite nao utiliza o .env.',
      );
    }
    banco = Pool<void>.withUrl(databaseUrl);
    addTearDown(() => banco.close());
    await banco.execute(
      'DROP SCHEMA public CASCADE; CREATE SCHEMA public;',
      queryMode: QueryMode.simple,
    );
    await banco.execute(
      await File('../Database/schema.sql').readAsString(),
      queryMode: QueryMode.simple,
    );
    final handler = protecao
        .middleware(
          (context) =>
              rota.onRequest(context, context.request.uri.pathSegments.last),
        )
        .use(provider<Pool<void>>((_) => banco))
        .use(
          provider<UsuarioAutenticado?>(
            (context) =>
                autenticar(context.request.headers['authorization'], segredo),
          ),
        );
    servidor = await serve(handler, InternetAddress.loopbackIPv4, 0);
    addTearDown(() => servidor.close(force: true));
    cliente = HttpClient();
    addTearDown(() => cliente.close(force: true));
  });

  setUp(() async {
    await banco.execute('''
      DROP TRIGGER IF EXISTS falha_log_teste ON log_sistema;
      DROP TRIGGER IF EXISTS falha_aprovacao_teste ON pedido;
      DROP TRIGGER IF EXISTS falha_movimento_teste ON movimentacao_estoque;
      DROP FUNCTION IF EXISTS falha_teste();
      TRUNCATE empresa RESTART IDENTITY CASCADE;
      INSERT INTO empresa (id,nome,cnpj) VALUES (1,'A','A'),(2,'B','B');
      INSERT INTO usuario (id,empresa_id,nome,email,senha_hash,tipo) VALUES
        (1,1,'Pedreiro 1','ped1@a','hash','pedreiro'),
        (2,1,'Pedreiro 2','ped2@a','hash','pedreiro'),
        (3,1,'Engenheiro','eng@a','hash','engenheiro'),
        (4,1,'Master','master@a','hash','master'),
        (5,2,'Engenheiro B','eng@b','hash','engenheiro');
      INSERT INTO obra (id,empresa_id,nome,endereco,status) VALUES
        (1,1,'Obra A','Rua','ativa'),(2,2,'Obra B','Rua','ativa');
      INSERT INTO produto (id,empresa_id,nome,unidade) VALUES
        (1,1,'Cimento','saco'),(2,1,'Areia','kg'),(3,2,'Alheio','kg');
      INSERT INTO estoque (obra_id,produto_id,quantidade) VALUES
        (1,1,5),(1,2,5),(2,3,5);
    ''', queryMode: QueryMode.simple);
  });

  test(
    'HTTP aprova, baixa decimais e registra materiais com o ator autenticado',
    () async {
      final id = await pedido([(1, '2.50'), (2, '1.25')]);
      final resposta = await aprovar(id);
      expect(resposta.status, 200);
      expect(resposta.dados['status'], 'aprovado');
      expect(resposta.dados['baixas'], [
        {'produto_id': 1, 'quantidade': '2.50', 'saldo': '2.50'},
        {'produto_id': 2, 'quantidade': '1.25', 'saldo': '3.75'},
      ]);
      final dados = await estado(id);
      expect(dados['status'], 'aprovado');
      final logs = (dados['logs'] as List).cast<List<Object?>>();
      expect(logs, hasLength(2));
      expect(logs.every((log) => log.first == 3), isTrue);
      expect(
        logs.first[1],
        contains('pedido=$id obra=1 produto=1 quantidade=2.50 saldo=2.50'),
      );
      final movimentos = (dados['movimentos'] as List)
          .cast<Map<String, dynamic>>();
      expect(movimentos, hasLength(2));
      expect(movimentos.first, {
        'empresa_id': 1,
        'obra_id': 1,
        'produto_id': 1,
        'pedido_id': id,
        'registrado_por_usuario_id': 3,
        'tipo': 'saida_pedido',
        'quantidade': '2.50',
        'saldo_anterior': '5.00',
        'saldo_posterior': '2.50',
        'protocolo_pedido': startsWith('PED-TEST-'),
        'produto_nome': 'Cimento',
        'unidade': 'saco',
        'ocorrido_em': isA<DateTime>(),
      });
      expect(movimentos.last['quantidade'], '1.25');
      expect(movimentos.last['saldo_anterior'], '5.00');
      expect(movimentos.last['saldo_posterior'], '3.75');
    },
  );

  test(
    'master aprova e pedreiro/sem token nao conseguem alterar o saldo',
    () async {
      final id = await pedido([(1, '1.00')]);
      final antes = await estado(id);
      expect(
        (await aprovar(id, nivel: Nivel.pedreiro, usuario: 1)).status,
        403,
      );
      expect((await aprovar(id, nivel: null)).status, 401);
      expect(await estado(id), antes);
      expect((await aprovar(id, nivel: Nivel.master, usuario: 4)).status, 200);
      expect((await estado(id))['logs'], [
        [4, contains('BAIXA_ESTOQUE')],
      ]);
    },
  );

  test('pedido de outra empresa ou inexistente retorna 404', () async {
    final id = await pedido([(3, '1.00')], obra: 2, usuario: 5);
    final antes = await estado(id);
    expect((await aprovar(id)).status, 404);
    expect((await aprovar(2147483647)).status, 404);
    expect(await estado(id), antes);
  });

  test('produto ou solicitante de outra empresa nao recebe baixa', () async {
    final produtoAlheio = await pedido([(3, '1.00')]);
    final antes = await estado(produtoAlheio);
    final resposta = await aprovar(produtoAlheio);
    expect(resposta.status, 400);
    expect(resposta.dados['erro'], contains('materiais validos'));
    expect(await estado(produtoAlheio), antes);
    final solicitanteAlheio = await pedido([(1, '1.00')], usuario: 5);
    expect((await aprovar(solicitanteAlheio)).status, 404);
    expect((await estado(produtoAlheio))['saldos'], [
      [1, '5.00'],
      [2, '5.00'],
    ]);
    expect((await estado(produtoAlheio))['logs'], isEmpty);
  });

  test(
    'pedido sem itens retorna 400 e preserva pedido, saldos e logs',
    () async {
      final vazio = await pedido([]);
      final antes = await estado(vazio);
      final resposta = await aprovar(vazio);
      expect(resposta.status, 400);
      expect(resposta.dados['erro'], contains('materiais validos'));
      expect(await estado(vazio), antes);
    },
  );

  test(
    'pedido sem registro de estoque ou com saldo zero retorna 409',
    () async {
      final id = await pedido([(1, '1.00')]);
      await sql('DELETE FROM estoque WHERE obra_id = 1 AND produto_id = 1');
      expect((await aprovar(id)).status, 409);
      await sql(
        'INSERT INTO estoque (obra_id,produto_id,quantidade) VALUES (1,1,0)',
      );
      expect((await aprovar(id)).status, 409);
      expect((await estado(id))['status'], 'pendente');
      expect((await estado(id))['logs'], isEmpty);
    },
  );

  test(
    'saldo insuficiente no segundo material reverte a primeira baixa e seu log',
    () async {
      final id = await pedido([(1, '2.50'), (2, '6.00')]);
      final antes = await estado(id);
      expect((await aprovar(id)).status, 409);
      expect(await estado(id), antes);
    },
  );

  test('itens legados repetidos sao somados antes da baixa', () async {
    final id = await pedido([(1, '1.00'), (1, '0.25')]);
    final resposta = await aprovar(id);
    expect(resposta.status, 200);
    expect(resposta.dados['baixas'], [
      {'produto_id': 1, 'quantidade': '1.25', 'saldo': '3.75'},
    ]);
    expect((await estado(id))['logs'], hasLength(1));
    final movimentos = (await estado(id))['movimentos'] as List;
    expect(movimentos, hasLength(1));
    expect((movimentos.single as Map)['quantidade'], '1.25');
  });

  test(
    'itens legados repetidos com total sem saldo nao provocam baixa parcial',
    () async {
      final id = await pedido([(1, '3.00'), (1, '3.00')]);
      final antes = await estado(id);
      expect((await aprovar(id)).status, 409);
      expect(await estado(id), antes);
    },
  );

  test(
    'NUMERIC preserva saldo de centesimos sem arredondamento em double',
    () async {
      await sql(
        'UPDATE estoque SET quantidade = 0.03 '
        'WHERE obra_id = 1 AND produto_id = 1',
      );
      final resposta = await aprovar(await pedido([(1, '0.01')]));
      expect(resposta.status, 200);
      final baixa =
          (resposta.dados['baixas'] as List).single as Map<String, dynamic>;
      expect(baixa['saldo'], '0.02');
      final dados = await estado(resposta.dados['id'] as int);
      final movimentos = (dados['movimentos'] as List)
          .cast<Map<String, dynamic>>();
      final movimento = movimentos.single;
      expect(movimento['quantidade'], '0.01');
      expect(movimento['saldo_anterior'], '0.03');
      expect(movimento['saldo_posterior'], '0.02');
    },
  );

  test('repetir aprovacao retorna 409 sem duplicar baixa ou logs', () async {
    final id = await pedido([(1, '1.00')]);
    expect((await aprovar(id)).status, 200);
    final depois = await estado(id);
    expect((await aprovar(id)).status, 409);
    expect(await estado(id), depois);
  });

  test(
    'recusa preserva o motivo original e registra o ator sem baixar',
    () async {
      final id = await pedido(
        [(1, '10.00')],
        justificativa: 'Material para concretagem',
      );
      final antes = await estado(id);
      final resposta = await decidir(
        id,
        status: 'recusado',
        justificativa: '  Material desnecessario  ',
      );
      expect(resposta.status, 200);
      expect(resposta.dados['status'], 'recusado');
      expect(resposta.dados['justificativa'], 'Material para concretagem');
      expect(resposta.dados['justificativa_recusa'], 'Material desnecessario');
      final depois = await estado(id);
      expect(depois['saldos'], antes['saldos']);
      expect(depois['movimentos'], isEmpty);
      expect(depois['justificativa'], 'Material para concretagem');
      expect(depois['justificativa_recusa'], 'Material desnecessario');
      expect(depois['logs'], [
        [3, startsWith('RECUSA_PEDIDO pedido=$id obra=1 protocolo=')],
      ]);

      final request = await cliente.getUrl(
        Uri.parse('http://127.0.0.1:${servidor.port}/pedidos/$id'),
      );
      final token = JWT({
        'empresa_id': 1,
        'tipo': 'pedreiro',
      }, subject: '1').sign(SecretKey(segredo));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final response = await request.close();
      expect(response.statusCode, 200);
      final dados = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
      expect(dados['justificativa'], 'Material para concretagem');
      expect(dados['justificativa_recusa'], 'Material desnecessario');
    },
  );

  test('recusa invalida, sem permissao ou fora da empresa nao grava', () async {
    final id = await pedido([(1, '1.00')]);
    final antes = await estado(id);
    for (final justificativa in [null, '', '   ', 1, 'a' * 256]) {
      expect(
        (await decidir(
          id,
          status: 'recusado',
          justificativa: justificativa,
        )).status,
        400,
      );
    }
    expect(
      (await decidir(
        id,
        status: 'recusado',
        justificativa: 'Motivo',
        nivel: null,
      )).status,
      401,
    );
    expect(
      (await decidir(
        id,
        status: 'recusado',
        justificativa: 'Motivo',
        nivel: Nivel.pedreiro,
        usuario: 1,
      )).status,
      403,
    );
    expect(
      (await decidir(
        id,
        status: 'recusado',
        justificativa: 'Motivo',
        empresa: 2,
        usuario: 5,
      )).status,
      404,
    );
    expect(
      (await decidir(
        2147483647,
        status: 'recusado',
        justificativa: 'Motivo',
      )).status,
      404,
    );
    final solicitanteAlheio = await pedido([(1, '1.00')], usuario: 5);
    expect(
      (await decidir(
        solicitanteAlheio,
        status: 'recusado',
        justificativa: 'Motivo',
      )).status,
      404,
    );
    expect(await estado(id), antes);
  });

  test(
    'master recusa com 255 caracteres e nenhuma decisao pode ser refeita',
    () async {
      final id = await pedido([(1, '1.00')]);
      final justificativa = 'a' * 255;
      final resposta = await decidir(
        id,
        status: 'recusado',
        justificativa: '  $justificativa  ',
        nivel: Nivel.master,
        usuario: 4,
      );
      expect(resposta.status, 200);
      expect(resposta.dados['justificativa_recusa'], justificativa);
      final depois = await estado(id);
      expect(depois['logs'], [
        [4, contains('RECUSA_PEDIDO')],
      ]);
      expect(
        (await decidir(
          id,
          status: 'recusado',
          justificativa: 'Outro motivo',
        )).status,
        409,
      );
      expect((await aprovar(id)).status, 409);
      expect(await estado(id), depois);

      final aprovado = await pedido([(1, '1.00')]);
      expect((await aprovar(aprovado)).status, 200);
      final depoisDaBaixa = await estado(aprovado);
      expect(
        (await decidir(
          aprovado,
          status: 'recusado',
          justificativa: 'Outro motivo',
        )).status,
        409,
      );
      expect(await estado(aprovado), depoisDaBaixa);
    },
  );

  for (final decisoes in [
    ['recusado', 'recusado'],
    ['aprovado', 'recusado'],
  ]) {
    test('decisoes simultaneas $decisoes confirmam apenas uma vez', () async {
      final id = await pedido([(1, '1.00')]);
      final respostas = await disputar(
        [id, id],
        mesmoPedido: true,
        decisoes: decisoes,
      );
      expect(respostas.map((r) => r.status).toList()..sort(), [200, 409]);
      final vencedor = respostas.singleWhere((r) => r.status == 200);
      final depois = await estado(id);
      expect(depois['status'], vencedor.dados['status']);
      expect(depois['saldos'], [
        if (vencedor.dados['status'] == 'aprovado')
          [1, '4.00']
        else
          [1, '5.00'],
        [2, '5.00'],
      ]);
      expect(depois['logs'], hasLength(1));
    });
  }

  test('falha no log reverte recusa e justificativa', () async {
    final id = await pedido([(1, '1.00')], justificativa: 'Motivo original');
    final antes = await estado(id);
    await banco.execute(r'''
      CREATE FUNCTION falha_teste() RETURNS trigger AS $$
      BEGIN RAISE EXCEPTION 'falha injetada para testar rollback'; END;
      $$ LANGUAGE plpgsql;
      CREATE TRIGGER falha_log_teste BEFORE INSERT ON log_sistema
      FOR EACH ROW EXECUTE FUNCTION falha_teste();
    ''', queryMode: QueryMode.simple);
    final request = await cliente.patchUrl(
      Uri.parse('http://127.0.0.1:${servidor.port}/pedidos/$id'),
    );
    final token = JWT({
      'empresa_id': 1,
      'tipo': 'engenheiro',
    }, subject: '3').sign(SecretKey(segredo));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'pedido': {'status': 'recusado', 'justificativa': 'Motivo da recusa'},
      }),
    );
    final response = await request.close();
    expect(response.statusCode, 500);
    await response.drain<void>();
    expect(await estado(id), antes);
  });

  test(
    'oito aprovacoes disputam saldo 1: um 200, sete 409 e um movimento',
    () async {
      await sql(
        'UPDATE estoque SET quantidade=1 WHERE obra_id=1 AND produto_id=1',
      );
      final ids = <int>[];
      for (var i = 0; i < 8; i++) {
        ids.add(await pedido([(1, '1.00')]));
      }
      final respostas = await disputar(ids);
      expect(respostas.where((r) => r.status == 200), hasLength(1));
      expect(respostas.where((r) => r.status == 409), hasLength(7));
      final dados = await estado(ids.first);
      expect(dados['saldos'], [
        [1, '0.00'],
        [2, '5.00'],
      ]);
      expect(dados['logs'], hasLength(1));
      final movimentos = (dados['movimentos'] as List)
          .cast<Map<String, dynamic>>();
      expect(movimentos, hasLength(1));
      final vencedor = respostas.singleWhere((r) => r.status == 200);
      expect(movimentos.single['pedido_id'], vencedor.dados['id']);
      expect(movimentos.single['saldo_anterior'], '1.00');
      expect(movimentos.single['saldo_posterior'], '0.00');
      expect(
        (await sql(
          "SELECT count(*) FROM pedido WHERE status='pendente'",
        )).single[0],
        7,
      );
    },
  );

  test(
    'alterar cadastro e protocolo nao reescreve as copias historicas',
    () async {
      final id = await pedido([(1, '1.00')]);
      expect((await aprovar(id)).status, 200);
      final antes = (await estado(id))['movimentos'];
      await sql("UPDATE produto SET nome='Novo', unidade='un' WHERE id=1");
      await sql("UPDATE pedido SET protocolo='NOVO' WHERE id=@id", {'id': id});
      expect((await estado(id))['movimentos'], antes);
    },
  );

  test(
    'dois pedidos simultaneos disputam o ultimo saco: um 200 e um 409',
    () async {
      await sql(
        'UPDATE estoque SET quantidade = 1 '
        'WHERE obra_id = 1 AND produto_id = 1',
      );
      final primeiro = await pedido([(1, '1.00')]);
      final segundo = await pedido([(1, '1.00')], usuario: 2);
      final respostas = await disputar([primeiro, segundo]);
      expect(respostas.map((r) => r.status).toList()..sort(), [200, 409]);
      final statuses = await sql('SELECT status FROM pedido ORDER BY status');
      expect(statuses.map((r) => r[0]).toList(), ['aprovado', 'pendente']);
      expect((await estado(primeiro))['saldos'], [
        [1, '0.00'],
        [2, '5.00'],
      ]);
      expect((await estado(primeiro))['logs'], hasLength(1));
    },
  );

  test(
    'duas aprovacoes simultaneas do mesmo pedido baixam uma unica vez',
    () async {
      final id = await pedido([(1, '1.00')]);
      final respostas = await disputar([id, id], mesmoPedido: true);
      expect(respostas.map((r) => r.status).toList()..sort(), [200, 409]);
      expect((await estado(id))['saldos'], [
        [1, '4.00'],
        [2, '5.00'],
      ]);
      expect((await estado(id))['logs'], hasLength(1));
    },
  );

  test('pedidos com itens em ordem oposta concluem sem deadlock', () async {
    final primeiro = await pedido([(1, '1.00'), (2, '1.00')]);
    final segundo = await pedido([(2, '1.00'), (1, '1.00')]);
    final respostas = await disputar([primeiro, segundo]);
    expect(respostas.map((r) => r.status).toList(), [200, 200]);
    expect((await estado(primeiro))['saldos'], [
      [1, '3.00'],
      [2, '3.00'],
    ]);
    expect((await estado(primeiro))['logs'], hasLength(4));
  });

  for (final tabela in ['log_sistema', 'pedido', 'movimentacao_estoque']) {
    test('falha ao gravar $tabela reverte saldos, logs e aprovacao', () async {
      final id = await pedido([(1, '1.00'), (2, '1.00')]);
      final antes = await estado(id);
      await banco.execute('''
        CREATE FUNCTION falha_teste() RETURNS trigger AS \$\$
        BEGIN RAISE EXCEPTION 'falha injetada para testar rollback'; END;
        \$\$ LANGUAGE plpgsql;
        CREATE TRIGGER ${tabela == 'pedido'
          ? 'falha_aprovacao_teste'
          : tabela == 'log_sistema'
          ? 'falha_log_teste'
          : 'falha_movimento_teste'}
        BEFORE ${tabela == 'pedido' ? 'UPDATE' : 'INSERT'} ON $tabela
        FOR EACH ROW ${tabela == 'log_sistema'
          ? "WHEN (NEW.acao LIKE '%produto=2 %')"
          : tabela == 'movimentacao_estoque'
          ? 'WHEN (NEW.produto_id=2)'
          : ''}
        EXECUTE FUNCTION falha_teste();
      ''', queryMode: QueryMode.simple);
      await expectLater(
        aprovarPedidoComBaixa(banco, pedidoId: id, usuario: engenheiro),
        throwsA(isA<ServerException>()),
      );
      expect(await estado(id), antes);
    });
  }

  test(
    'CHECK ck_estoque_quantidade rejeita saldo negativo no proprio PostgreSQL',
    () async {
      await expectLater(
        sql(
          'UPDATE estoque SET quantidade = -1 '
          'WHERE obra_id = 1 AND produto_id = 1',
        ),
        throwsA(
          isA<ServerException>()
              .having((e) => e.code, 'SQLSTATE', '23514')
              .having(
                (e) => e.constraintName,
                'constraint',
                'ck_estoque_quantidade',
              ),
        ),
      );
      final id = await pedido([(1, '1.00')]);
      expect((await estado(id))['saldos'], [
        [1, '5.00'],
        [2, '5.00'],
      ]);
    },
  );
}
