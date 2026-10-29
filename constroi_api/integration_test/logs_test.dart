// Executa somente em Postgres local descartavel constroi_test_*.
import 'dart:convert';
import 'dart:io';

import 'package:constroi_api/ambiente.dart';
import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/senha.dart';
import 'package:constroi_api/token.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../routes/empresas.dart' as empresas;
import '../routes/equipamentos/[id].dart' as equipamento;
import '../routes/equipamentos/_middleware.dart' as equipamentos_auth;
import '../routes/equipamentos/index.dart' as equipamentos;
import '../routes/login.dart' as login;
import '../routes/logs/_middleware.dart' as logs_auth;
import '../routes/logs/index.dart' as logs;
import '../routes/obras/[id]/equipe/[usuarioId].dart' as encerrar_equipe;
import '../routes/obras/[id]/equipe/index.dart' as equipe;
import '../routes/obras/[id]/index.dart' as obra;
import '../routes/obras/_middleware.dart' as obras_auth;
import '../routes/obras/index.dart' as obras;
import '../routes/pedidos/_middleware.dart' as pedidos_auth;
import '../routes/pedidos/index.dart' as pedidos;
import '../routes/produtos/[id].dart' as produto;
import '../routes/produtos/_middleware.dart' as produtos_auth;
import '../routes/produtos/index.dart' as produtos;
import '../routes/usuarios/[id]/inativar.dart' as inativar;
import '../routes/usuarios/[id]/index.dart' as usuario;
import '../routes/usuarios/_middleware.dart' as usuarios_auth;
import '../routes/usuarios/index.dart' as usuarios;

class _ArquivoAmbiente extends Mock implements File {}

void main() {
  late Pool<void> banco;
  late HttpServer servidor;
  late HttpClient cliente;
  const segredo = 'logs-integracao-apenas-local';
  const senha = 'Segredo#Descartavel123';
  Future<void> sql(String texto) async {
    await banco.execute(texto, queryMode: QueryMode.simple);
  }

  Future<({int status, Map<String, dynamic> dados})> chamar(
    String caminho, {
    String metodo = 'GET',
    Map<String, dynamic>? corpo,
    Nivel? nivel = Nivel.master,
    int ator = 1,
    int empresa = 1,
  }) async {
    final req = await cliente.openUrl(
      metodo,
      Uri.parse('http://127.0.0.1:${servidor.port}$caminho'),
    );
    if (nivel != null) {
      req.headers.set(
        'authorization',
        'Bearer ${gerarToken(
          segredo: segredo,
          usuarioId: ator,
          empresaId: empresa,
          tipo: nivel.name,
        )}',
      );
    }
    if (corpo != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(corpo));
    }
    final res = await req.close();
    final texto = await utf8.decoder.bind(res).join();
    return (
      status: res.statusCode,
      dados: texto.isEmpty || !texto.startsWith('{')
          ? <String, dynamic>{}
          : jsonDecode(texto) as Map<String, dynamic>,
    );
  }

  Future<List<Map<String, dynamic>>> registros() async => (await banco.execute(
    'SELECT usuario_id,acao FROM log_sistema ORDER BY id',
  )).map((r) => r.toColumnMap()).toList();

  setUpAll(() async {
    // Configuracao isolada do login: nunca carrega as credenciais locais.
    final arquivo = _ArquivoAmbiente();
    when(arquivo.existsSync).thenReturn(true);
    when(arquivo.readAsLinesSync).thenReturn(['JWT_SECRET=$segredo']);
    IOOverrides.runZoned(
      () => expect(variavel('JWT_SECRET'), segredo),
      createFile: (_) => arquivo,
    );
    final url = Platform.environment['CONSTROI_TEST_DATABASE_URL'] ?? '';
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
    banco = Pool<void>.withUrl(url);
    addTearDown(() => banco.close());
    await sql('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
    final migracao = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'bin/migrate.dart'],
      environment: {
        'MIGRATION_DATABASE_URL': url,
        'MIGRATION_ENV_FILE': '.env.migrations-inexistente-teste',
        'DATABASE_URL': '',
      },
    );
    expect(migracao.exitCode, 0, reason: '${migracao.stderr}');
    final router = Router()
      ..all('/login', login.onRequest)
      ..all('/logs', logs_auth.middleware(logs.onRequest))
      ..all('/empresas', empresas.onRequest)
      ..all('/produtos', produtos_auth.middleware(produtos.onRequest))
      ..all(
        '/produtos/<id>',
        (RequestContext c, String id) =>
            produtos_auth.middleware((c) => produto.onRequest(c, id))(c),
      )
      ..all(
        '/equipamentos',
        equipamentos_auth.middleware(equipamentos.onRequest),
      )
      ..all(
        '/equipamentos/<id>',
        (RequestContext c, String id) => equipamentos_auth.middleware(
          (c) => equipamento.onRequest(c, id),
        )(c),
      )
      ..all('/usuarios', usuarios_auth.middleware(usuarios.onRequest))
      ..all(
        '/usuarios/<id>',
        (RequestContext c, String id) =>
            usuarios_auth.middleware((c) => usuario.onRequest(c, id))(c),
      )
      ..all(
        '/usuarios/<id>/inativar',
        (RequestContext c, String id) =>
            usuarios_auth.middleware((c) => inativar.onRequest(c, id))(c),
      )
      ..all('/obras', obras_auth.middleware(obras.onRequest))
      ..all(
        '/obras/<id>',
        (RequestContext c, String id) =>
            obras_auth.middleware((c) => obra.onRequest(c, id))(c),
      )
      ..all(
        '/obras/<id>/equipe',
        (RequestContext c, String id) =>
            obras_auth.middleware((c) => equipe.onRequest(c, id))(c),
      )
      ..all(
        '/obras/<id>/equipe/<usuario>',
        (RequestContext c, String id, String u) => obras_auth.middleware(
          (c) => encerrar_equipe.onRequest(c, id, u),
        )(c),
      )
      ..all('/pedidos', pedidos_auth.middleware(pedidos.onRequest));
    servidor = await serve(
      router.call
          .use(provider<Pool<void>>((_) => banco))
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
    await sql('TRUNCATE empresa RESTART IDENTITY CASCADE');
    await sql('''
      INSERT INTO empresa(nome,cnpj) VALUES ('A','A'),('B','B');
      INSERT INTO usuario(empresa_id,nome,email,senha_hash,tipo) VALUES
        (1,'Master A','master@a.test','hash','master'),
        (1,'Eng A','eng@a.test','hash','engenheiro'),
        (2,'Master B','master@b.test','hash','master');
      INSERT INTO obra(empresa_id,nome,endereco,status) VALUES (1,'Obra A','Rua','ativa');
      INSERT INTO produto(empresa_id,nome,unidade) VALUES (1,'Cimento','saco');
    ''');
  });

  test(
    'master consulta apenas a propria empresa; demais perfis nao consultam',
    () async {
      await sql(
        'INSERT INTO log_sistema(usuario_id,acao) '
        "VALUES (1,'A'),(2,'A2'),(3,'B')",
      );
      expect((await chamar('/logs', nivel: null)).status, 401);
      for (final nivel in [Nivel.pedreiro, Nivel.engenheiro]) {
        expect((await chamar('/logs', nivel: nivel)).status, 403);
      }
      expect((await chamar('/logs', metodo: 'POST')).status, 405);
      final resposta = await chamar('/logs');
      expect(resposta.status, 200);
      expect(
        (resposta.dados['logs'] as List).cast<Map<String, dynamic>>().map(
          (r) => r['acao'],
        ),
        [
          'A2',
          'A',
        ],
      );
      expect(
        (await chamar('/logs', ator: 3, empresa: 2)).dados['logs'],
        hasLength(1),
      );
      expect((await chamar('/logs?usuario_id=3')).dados['logs'], isEmpty);
      expect((await chamar('/logs?usuario_id=99999')).dados['logs'], isEmpty);
      expect(await registros(), hasLength(3));
    },
  );

  test('filtros combinados usam UTC, inicio incluso e fim exclusivo', () async {
    await sql("""
      INSERT INTO log_sistema(usuario_id,acao,data) VALUES
        (2,'antes','2026-10-29T02:59:59Z'),(2,'inicio','2026-10-29T03:00:00Z'),
        (1,'outro usuario','2026-10-29T03:30:00Z'),
        (2,'dentro','2026-10-29T03:59:59Z'),(2,'fim','2026-10-29T04:00:00Z');
    """);
    final resposta = await chamar(
      '/logs?usuario_id=2&data_inicio=2026-10-29T00:00:00-03:00'
      '&data_fim=2026-10-29T04:00:00Z',
    );
    expect(
      (resposta.dados['logs'] as List).cast<Map<String, dynamic>>().map(
        (r) => r['acao'],
      ),
      [
        'dentro',
        'inicio',
      ],
    );
    expect(
      (await chamar('/logs?data_inicio=2026-10-30')).dados['logs'],
      isEmpty,
    );
    expect((await chamar('/logs?data_fim=2026-10-29')).dados['logs'], isEmpty);
    expect(
      (await chamar('/logs?data_inicio=2026-10-29')).dados['logs'],
      hasLength(5),
    );
  });

  test(
    'paginacao desempata por id e informa proxima pagina',
    () async {
      await sql(
        'INSERT INTO log_sistema(usuario_id,acao,data) '
        "SELECT 1, n::text, '2026-10-29T00:00:00Z'::timestamptz "
        'FROM generate_series(1,5) n',
      );
      final primeira = await chamar('/logs?limit=2');
      expect(
        (primeira.dados['logs'] as List).cast<Map<String, dynamic>>().map(
          (r) => r['acao'],
        ),
        [
          '5',
          '4',
        ],
      );
      expect(primeira.dados['paginacao'], {
        'limit': 2,
        'offset': 0,
        'tem_mais': true,
      });
      final ultima = await chamar('/logs?limit=2&offset=4');
      expect(
        (ultima.dados['logs'] as List).cast<Map<String, dynamic>>().map(
          (r) => r['acao'],
        ),
        [
          '1',
        ],
      );
      expect(
        (ultima.dados['paginacao'] as Map<String, dynamic>)['tem_mais'],
        false,
      );
      expect((await chamar('/logs?offset=5')).dados['logs'], isEmpty);
    },
  );

  for (final filtro in [
    'usuario_id=0',
    'usuario_id=2147483648',
    'usuario_id=x',
    'limit=0',
    'limit=201',
    'limit=x',
    'offset=-1',
    'offset=10001',
    'data_inicio=',
    'data_inicio=2026-02-30',
    'data_inicio=2026-13-01',
    'data_inicio=2026-10-29T25:00Z',
    'data_inicio=0001-01-01T00:00:00%2B01:00',
    'data_inicio=2026-10-29T12:00:00',
    'data_inicio=2026-10-30&data_fim=2026-10-29',
    'data_inicio=2026-10-29&data_fim=2026-10-29',
  ]) {
    test('rejeita filtro invalido: $filtro', () async {
      expect((await chamar('/logs?$filtro')).status, 400);
    });
  }

  test(
    'rotas de escrita registram ator autenticado e recurso sem dados sensiveis',
    () async {
      final eventos = <String>[];
      Future<Map<String, dynamic>> gravar(
        String path,
        String metodo,
        Map<String, dynamic>? corpo,
        String evento,
        int status,
      ) async {
        final res = await chamar(path, metodo: metodo, corpo: corpo);
        expect(res.status, status, reason: '$metodo $path: ${res.dados}');
        eventos.add(evento);
        final lista = await registros();
        expect(lista, hasLength(eventos.length));
        expect(lista.last['usuario_id'], 1);
        expect(lista.last['acao'], startsWith('$evento '));
        return res.dados;
      }

      final p = await gravar(
        '/produtos',
        'POST',
        {
          'produto': {'nome': 'Areia', 'unidade': 'kg', 'usuario_id': 3},
        },
        'CRIACAO_PRODUTO',
        201,
      );
      await gravar(
        '/produtos/${p['id']}',
        'PATCH',
        {
          'produto': {'nome': 'Areia fina'},
        },
        'ALTERACAO_PRODUTO',
        200,
      );
      final e = await gravar(
        '/equipamentos',
        'POST',
        {
          'equipamento': {
            'nome': 'Betoneira',
            'patrimonio': 'EQ-1',
            'status': 'disponivel',
          },
        },
        'CRIACAO_EQUIPAMENTO',
        201,
      );
      await gravar(
        '/equipamentos/${e['id']}',
        'PATCH',
        {
          'equipamento': {'nome': 'Betoneira 2'},
        },
        'ALTERACAO_EQUIPAMENTO',
        200,
      );
      final u = await gravar(
        '/usuarios',
        'POST',
        {
          'usuario': {
            'nome': 'Pessoa',
            'email': 'pessoa@a.test',
            'senha': senha,
            'tipo': 'pedreiro',
          },
        },
        'CRIACAO_USUARIO',
        201,
      );
      await gravar(
        '/usuarios/${u['id']}',
        'PATCH',
        {
          'usuario': {'nome': 'Pessoa nova', 'senha': senha},
        },
        'ALTERACAO_USUARIO',
        200,
      );
      final o = await gravar(
        '/obras',
        'POST',
        {
          'obra': {
            'nome': 'Obra nova',
            'endereco': 'Rua nova',
            'status': 'ativa',
          },
        },
        'CRIACAO_OBRA',
        201,
      );
      await gravar(
        '/obras/${o['id']}',
        'PATCH',
        {
          'obra': {'nome': 'Obra alterada'},
        },
        'ALTERACAO_OBRA',
        200,
      );
      await gravar(
        '/obras/${o['id']}/equipe',
        'POST',
        {
          'equipe': {'usuario_id': u['id']},
        },
        'VINCULO_EQUIPE',
        201,
      );
      await gravar(
        '/obras/${o['id']}/equipe/${u['id']}',
        'DELETE',
        null,
        'ENCERRAMENTO_EQUIPE',
        200,
      );
      await gravar(
        '/usuarios/${u['id']}/inativar',
        'PATCH',
        null,
        'INATIVACAO_USUARIO',
        200,
      );
      await gravar(
        '/pedidos',
        'POST',
        {
          'pedido': {
            'obra_id': 1,
            'itens': [
              {'produto_id': 1, 'quantidade': 1},
            ],
          },
        },
        'CRIACAO_PEDIDO',
        201,
      );
      final texto = jsonEncode(await registros());
      for (final segredo in [
        senha,
        'senha_hash',
        'refresh_token',
        'pessoa@a.test',
      ]) {
        expect(texto, isNot(contains(segredo)));
      }
    },
  );

  test(
    'empresa e primeiro master sao registrados na mesma transacao',
    () async {
      final res = await chamar(
        '/empresas',
        metodo: 'POST',
        nivel: null,
        corpo: {
          'empresa': {'nome': 'Nova', 'cnpj': 'NOVA'},
          'usuario': {
            'nome': 'Master novo',
            'email': 'novo@nova.test',
            'senha': senha,
          },
        },
      );
      expect(res.status, 201);
      final log = (await registros()).single;
      expect(
        log['usuario_id'],
        (res.dados['usuario'] as Map<String, dynamic>)['id'],
      );
      expect(log['acao'], startsWith('CRIACAO_EMPRESA empresa='));
    },
  );

  test(
    'login valido registra somente id; senha errada nao gera log de sucesso',
    () async {
      await banco.execute(
        Sql.named('UPDATE usuario SET senha_hash=@hash WHERE id=1'),
        parameters: {'hash': gerarHash(senha)},
      );
      expect(
        (await chamar(
          '/login',
          metodo: 'POST',
          nivel: null,
          corpo: {
            'email': 'master@a.test',
            'senha': 'errada',
          },
        )).status,
        401,
      );
      expect(await registros(), isEmpty);
      final res = await chamar(
        '/login',
        metodo: 'POST',
        nivel: null,
        corpo: {
          'email': 'master@a.test',
          'senha': senha,
        },
      );
      expect(res.status, 200);
      expect(await registros(), [
        {'usuario_id': 1, 'acao': 'LOGIN usuario=1'},
      ]);
      expect(
        (await banco.execute('SELECT count(*) FROM sessao_usuario')).single[0],
        1,
      );
      expect(
        jsonEncode(await registros()),
        isNot(contains(res.dados['token'])),
      );
      expect(
        jsonEncode(await registros()),
        isNot(contains(res.dados['refresh_token'])),
      );
    },
  );

  test('404, conflito e validacao nao geram logs de sucesso', () async {
    expect(
      (await chamar(
        '/produtos',
        metodo: 'POST',
        corpo: {
          'produto': {'nome': 'Cimento', 'unidade': 'saco'},
        },
      )).status,
      409,
    );
    expect(
      (await chamar(
        '/produtos/99999',
        metodo: 'PATCH',
        corpo: {
          'produto': {'nome': 'Ausente'},
        },
      )).status,
      404,
    );
    expect(
      (await chamar(
        '/produtos',
        metodo: 'POST',
        corpo: {
          'produto': {'nome': ''},
        },
      )).status,
      400,
    );
    expect(await registros(), isEmpty);
  });

  test(
    'falha no log reverte insercao, atualizacao e bootstrap da empresa',
    () async {
      await sql(r"""
      CREATE FUNCTION recusar_log_teste() RETURNS trigger LANGUAGE plpgsql AS
      $$ BEGIN RAISE EXCEPTION 'falha de log simulada'; END $$;
      CREATE TRIGGER recusar_log BEFORE INSERT ON log_sistema
      FOR EACH ROW EXECUTE FUNCTION recusar_log_teste();
    """);
      try {
        expect(
          (await chamar(
            '/produtos',
            metodo: 'POST',
            corpo: {
              'produto': {'nome': 'Rollback', 'unidade': 'kg'},
            },
          )).status,
          500,
        );
        expect(
          (await chamar(
            '/produtos/1',
            metodo: 'PATCH',
            corpo: {
              'produto': {'nome': 'Rollback'},
            },
          )).status,
          500,
        );
        expect(
          (await chamar(
            '/pedidos',
            metodo: 'POST',
            corpo: {
              'pedido': {
                'obra_id': 1,
                'itens': [
                  {'produto_id': 1, 'quantidade': 1},
                ],
              },
            },
          )).status,
          500,
        );
        expect(
          (await chamar(
            '/empresas',
            metodo: 'POST',
            nivel: null,
            corpo: {
              'empresa': {'nome': 'Rollback', 'cnpj': 'ROLLBACK'},
              'usuario': {
                'nome': 'Master',
                'email': 'rollback@teste.test',
                'senha': senha,
              },
            },
          )).status,
          500,
        );
        expect(
          (await banco.execute(
            'SELECT nome FROM produto ORDER BY id',
          )).map((r) => r[0]),
          ['Cimento'],
        );
        expect(
          (await banco.execute('SELECT count(*) FROM empresa')).single[0],
          2,
        );
        expect(
          (await banco.execute('SELECT count(*) FROM usuario')).single[0],
          3,
        );
        expect(
          (await banco.execute('SELECT count(*) FROM pedido')).single[0],
          0,
        );
        expect(
          (await banco.execute('SELECT count(*) FROM item_pedido')).single[0],
          0,
        );
        expect(await registros(), isEmpty);
      } finally {
        await sql(
          'DROP TRIGGER recusar_log ON log_sistema; '
          'DROP FUNCTION recusar_log_teste();',
        );
      }
    },
  );
}
