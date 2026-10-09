import 'dart:convert';
import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../routes/pedidos/[id]/aprovar.dart' as rota;

/// RNF20 contra um Postgres de verdade.
///
/// Mock nao prova trava: com banco falso as duas aprovacoes passariam do
/// mesmo jeito com ou sem FOR UPDATE. Este teste so roda quando
/// TESTE_DATABASE_URL aponta para um banco descartavel, porque recria o
/// schema inteiro a partir de Database/schema.sql. Nunca aponte para o Neon.
///
///   TESTE_DATABASE_URL=postgres://postgres:senha@localhost:5432/constroi \
///     dart test test/integracao
class _ContextoFalso extends Mock implements RequestContext {}

const _engenheiro = UsuarioAutenticado(
  id: 1,
  empresaId: 1,
  nivel: Nivel.engenheiro,
);

void main() {
  final url = Platform.environment['TESTE_DATABASE_URL'];
  if (url == null) {
    test(
      'RNF20 contra Postgres real',
      () {},
      skip: 'Defina TESTE_DATABASE_URL com um banco descartavel.',
    );
    return;
  }
  late Pool<void> banco;

  Future<Response> aprovar(int pedidoId) {
    final contexto = _ContextoFalso();
    when(() => contexto.request).thenReturn(
      Request.post(Uri.parse('http://localhost/pedidos/$pedidoId/aprovar')),
    );
    when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(_engenheiro);
    when(() => contexto.read<Pool<void>>()).thenReturn(banco);
    return rota.onRequest(contexto, '$pedidoId');
  }

  Future<int> pedido(String protocolo, num quantidade) async {
    final linhas = await banco.execute(
      Sql.named('''
        INSERT INTO pedido (usuario_id, obra_id, protocolo, status)
        VALUES (2, 1, @protocolo, 'pendente') RETURNING id
      '''),
      parameters: {'protocolo': protocolo},
    );
    final id = linhas.first.first! as int;
    await banco.execute(
      Sql.named('''
        INSERT INTO item_pedido (pedido_id, produto_id, quantidade)
        VALUES (@pedido, 1, @quantidade)
      '''),
      parameters: {'pedido': id, 'quantidade': '$quantidade'},
    );
    return id;
  }

  Future<String> saldo() async {
    final linhas = await banco.execute(
      'SELECT quantidade FROM estoque WHERE obra_id = 1 AND produto_id = 1',
    );
    return '${linhas.first.first}';
  }

  Future<int> logs() async {
    final linhas = await banco.execute('SELECT COUNT(*) FROM log_sistema');
    return linhas.first.first! as int;
  }

  setUpAll(() async {
    final uri = Uri.parse(url);
    final credenciais = uri.userInfo.split(':');
    banco = Pool.withEndpoints(
      [
        Endpoint(
          host: uri.host,
          port: uri.hasPort ? uri.port : 5432,
          database: uri.pathSegments.first,
          username: credenciais.first,
          password: credenciais.length > 1 ? credenciais[1] : null,
        ),
      ],
      settings: const PoolSettings(
        maxConnectionCount: 4,
        sslMode: SslMode.disable,
      ),
    );
    await banco.execute(
      'DROP SCHEMA public CASCADE; CREATE SCHEMA public;',
      queryMode: QueryMode.simple,
    );
    await banco.execute(
      File('../Database/schema.sql').readAsStringSync(),
      queryMode: QueryMode.simple,
    );
    await banco.execute(
      '''
      INSERT INTO empresa (nome, cnpj) VALUES ('Teste', '00.000.000/0001-00');
      INSERT INTO usuario (empresa_id, nome, email, senha_hash, tipo) VALUES
        (1, 'Engenheiro', 'eng@teste', 'x', 'engenheiro'),
        (1, 'Pedreiro', 'ped@teste', 'x', 'pedreiro');
      INSERT INTO obra (empresa_id, nome, endereco, status)
        VALUES (1, 'Obra', 'Rua', 'ativa');
      INSERT INTO produto (empresa_id, nome, unidade)
        VALUES (1, 'Cimento CP-II', 'saco');
      INSERT INTO estoque (obra_id, produto_id, quantidade) VALUES (1, 1, 0);
      ''',
      queryMode: QueryMode.simple,
    );
  });

  setUp(() async {
    await banco.execute(
      'TRUNCATE log_sistema, item_pedido, pedido; '
      'UPDATE estoque SET quantidade = 1;',
      queryMode: QueryMode.simple,
    );
  });

  tearDownAll(() => banco.close());

  test(
    'dois pedidos disputando o ultimo saco: so um sai e o saldo fica zero',
    () async {
      final primeiro = await pedido('PED-A', 1);
      final segundo = await pedido('PED-B', 1);

      final respostas = await Future.wait([
        aprovar(primeiro),
        aprovar(segundo),
      ]);
      final status = respostas.map((r) => r.statusCode).toList()..sort();

      expect(status, [HttpStatus.ok, HttpStatus.conflict]);
      expect(await saldo(), '0.00');
      expect(await logs(), 1);
      final pendentes = await banco.execute(
        "SELECT COUNT(*) FROM pedido WHERE status = 'pendente'",
      );
      expect(pendentes.first.first, 1);
    },
  );

  test(
    'o mesmo pedido aprovado duas vezes ao mesmo tempo baixa uma vez so',
    () async {
      await banco.execute('UPDATE estoque SET quantidade = 5');
      final id = await pedido('PED-C', 2);

      final respostas = await Future.wait([aprovar(id), aprovar(id)]);
      final status = respostas.map((r) => r.statusCode).toList()..sort();

      expect(status, [HttpStatus.ok, HttpStatus.conflict]);
      expect(await saldo(), '3.00');
      expect(await logs(), 1);
    },
  );

  test('sem saldo recusa, deixa o pedido pendente e nao grava log', () async {
    final id = await pedido('PED-D', 2);

    final resposta = await aprovar(id);
    final corpo = jsonDecode(await resposta.body()) as Map<String, dynamic>;

    expect(resposta.statusCode, HttpStatus.conflict);
    expect(corpo['faltando'], [
      {
        'produto_id': 1,
        'produto_nome': 'Cimento CP-II',
        'solicitada': '2.00',
        'saldo': '1.00',
      },
    ]);
    expect(await saldo(), '1.00');
    expect(await logs(), 0);
    final pedidos = await banco.execute(
      Sql.named('SELECT status FROM pedido WHERE id = @id'),
      parameters: {'id': id},
    );
    expect(pedidos.first.first, 'pendente');
  });

  test('aprovacao grava status, baixa e log no mesmo commit', () async {
    final id = await pedido('PED-E', 1);

    final resposta = await aprovar(id);
    final corpo = jsonDecode(await resposta.body()) as Map<String, dynamic>;

    expect(resposta.statusCode, HttpStatus.ok);
    expect(corpo['status'], 'aprovado');
    expect(corpo['baixas'], [
      {'produto_id': 1, 'saldo': '0.00'},
    ]);
    final log = await banco.execute('SELECT usuario_id, acao FROM log_sistema');
    expect(log.single[0], 1);
    expect(
      log.single[1],
      'Pedido PED-E aprovado: baixa de 1.00 do produto 1 na obra 1',
    );
  });

  test(
    'o CHECK de quantidade >= 0 recusa saldo negativo direto no banco',
    () async {
      await expectLater(
        banco.execute('UPDATE estoque SET quantidade = quantidade - 2'),
        throwsA(
          isA<ServerException>().having((e) => e.code, 'code', '23514'),
        ),
      );
      expect(await saldo(), '1.00');
    },
  );
}
