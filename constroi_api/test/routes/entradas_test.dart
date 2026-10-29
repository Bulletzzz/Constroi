import 'dart:convert';
import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../routes/entradas/_middleware.dart' as protecao;
import '../../routes/entradas/index.dart' as rota;

class _ContextoFalso extends Mock implements RequestContext {}

class _BancoFalso extends Mock implements Pool<void> {}

class _TransacaoFalsa extends Mock implements TxSession {}

class _LinhaFalsa extends Mock implements ResultRow {}

class _ErroBanco extends Mock implements ServerException {}

Result _resultado(List<Map<String, dynamic>> dados) => Result(
  rows: dados.map((dados) {
    final linha = _LinhaFalsa();
    when(linha.toColumnMap).thenReturn(dados);
    return linha;
  }).toList(),
  affectedRows: dados.length,
  schema: ResultSchema([]),
);

void main() {
  late _ContextoFalso contexto;
  late _BancoFalso banco;
  late _TransacaoFalsa transacao;
  late List<Result> resultados;
  late List<Map<String, Object?>> parametros;
  int? falhaNaConsulta;
  ServerException? erro;

  const entrada = {
    'obra_id': 10,
    'usuario_id': 99,
    'justificativa': ' Material recebido sem nota fiscal ',
    'itens': [
      {'produto_id': 20, 'quantidade': 2.5},
      {'produto_id': 21, 'quantidade': 1},
    ],
  };

  void requisicao(Object? dados) {
    when(() => contexto.request).thenReturn(
      Request.post(
        Uri.parse('http://localhost/entradas'),
        body: jsonEncode(dados),
      ),
    );
  }

  void autenticar(Nivel nivel) {
    when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(
      UsuarioAutenticado(id: 7, empresaId: 3, nivel: nivel),
    );
  }

  setUpAll(() {
    registerFallbackValue(Sql.named(''));
    registerFallbackValue((TxSession _) async => Response());
  });

  setUp(() {
    contexto = _ContextoFalso();
    banco = _BancoFalso();
    transacao = _TransacaoFalsa();
    parametros = [];
    falhaNaConsulta = null;
    erro = null;
    resultados = [
      _resultado([
        {'id': 10},
      ]),
      _resultado([
        {'id': 20},
        {'id': 21},
      ]),
      _resultado([
        {
          'id': 30,
          'usuario_id': 7,
          'obra_id': 10,
          'xml_nota_fiscal': null,
          'justificativa': 'Material recebido sem nota fiscal',
          'data': DateTime.utc(2026, 10, 25),
        },
      ]),
      _resultado([
        {'id': 40, 'produto_id': 20, 'quantidade': '2.50'},
      ]),
      _resultado([
        {'saldo': '7.50'},
      ]),
      _resultado([]),
      _resultado([
        {'id': 41, 'produto_id': 21, 'quantidade': '1.00'},
      ]),
      _resultado([
        {'saldo': '1.00'},
      ]),
      _resultado([]),
    ];
    autenticar(Nivel.engenheiro);
    when(() => contexto.read<Pool<void>>()).thenReturn(banco);
    when(() => banco.runTx<Response>(any())).thenAnswer((chamada) {
      final executar =
          chamada.positionalArguments.first
              as Future<Response> Function(TxSession);
      return executar(transacao);
    });
    when(
      () => transacao.execute(any(), parameters: any(named: 'parameters')),
    ).thenAnswer((chamada) async {
      parametros.add(
        Map<String, Object?>.from(chamada.namedArguments[#parameters] as Map),
      );
      if (parametros.length == falhaNaConsulta) {
        if (erro != null) throw erro!;
        throw StateError('Falha na transacao.');
      }
      return resultados.removeAt(0);
    });
    requisicao({'entrada': entrada});
  });

  for (final nivel in [Nivel.engenheiro, Nivel.master]) {
    test('${nivel.name} cria entrada sem nota e grava estoque e log', () async {
      autenticar(nivel);
      final resposta = await protecao.middleware(rota.onRequest)(contexto);
      final dados = jsonDecode(await resposta.body()) as Map<String, dynamic>;

      expect(resposta.statusCode, HttpStatus.created);
      expect(dados['usuario_id'], 7);
      expect(dados['xml_nota_fiscal'], isNull);
      expect(dados['justificativa'], 'Material recebido sem nota fiscal');
      expect(dados['data'], '2026-10-25T00:00:00.000Z');
      expect(dados['itens'], [
        {'id': 40, 'produto_id': 20, 'quantidade': '2.50'},
        {'id': 41, 'produto_id': 21, 'quantidade': '1.00'},
      ]);
      expect(parametros[0], {'obra': 10, 'empresa': 3});
      expect(parametros[1], {
        'empresa': 3,
        'produtos': [20, 21],
      });
      expect(parametros[2], {
        'usuario': 7,
        'obra': 10,
        'justificativa': 'Material recebido sem nota fiscal',
      });
      expect(parametros[3], {
        'entrada': 30,
        'produto': 20,
        'quantidade': '2.50',
      });
      expect(parametros[4], {'obra': 10, 'produto': 20, 'quantidade': '2.50'});
      expect(parametros[5], {
        'usuario': 7,
        'acao':
            'ENTRADA_MANUAL entrada=30 obra=10 produto=20 '
            'quantidade=2.50 saldo=7.50',
      });
      expect(parametros[6], {
        'entrada': 30,
        'produto': 21,
        'quantidade': '1.00',
      });
      expect(parametros[7], {'obra': 10, 'produto': 21, 'quantidade': '1.00'});
      expect(parametros[8], {
        'usuario': 7,
        'acao':
            'ENTRADA_MANUAL entrada=30 obra=10 produto=21 '
            'quantidade=1.00 saldo=1.00',
      });
      expect(resultados, isEmpty);
      verify(() => banco.runTx<Response>(any())).called(1);
    });
  }

  test(
    'ordena produtos antes das gravacoes mesmo com itens invertidos',
    () async {
      requisicao({
        'entrada': {
          ...entrada,
          'itens': (entrada['itens']! as List).reversed.toList(),
        },
      });
      final resposta = await rota.onRequest(contexto);
      expect(resposta.statusCode, HttpStatus.created);
      expect(parametros[3]['produto'], 20);
      expect(parametros[4]['produto'], 20);
      expect(parametros[6]['produto'], 21);
      expect(parametros[7]['produto'], 21);
    },
  );

  test('sem token retorna 401 sem acessar o banco', () async {
    when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(null);
    final resposta = await protecao.middleware(rota.onRequest)(contexto);
    expect(resposta.statusCode, HttpStatus.unauthorized);
    verifyNever(() => banco.runTx<Response>(any()));
  });

  test('pedreiro retorna 403 sem acessar o banco', () async {
    autenticar(Nivel.pedreiro);
    final resposta = await protecao.middleware(rota.onRequest)(contexto);
    expect(resposta.statusCode, HttpStatus.forbidden);
    verifyNever(() => banco.runTx<Response>(any()));
  });

  test('obra inexistente ou de outra empresa retorna 404', () async {
    resultados[0] = _resultado([]);
    final resposta = await rota.onRequest(contexto);
    expect(resposta.statusCode, HttpStatus.notFound);
    expect(parametros, hasLength(1));
  });

  test('produto inexistente ou de outra empresa impede a entrada', () async {
    resultados[1] = _resultado([
      {'id': 20},
    ]);
    final resposta = await rota.onRequest(contexto);
    expect(resposta.statusCode, HttpStatus.badRequest);
    expect(parametros, hasLength(2));
  });

  test('justificativa e obrigatoria e limitada a 255 caracteres', () async {
    for (final justificativa in [null, '', '   ', 123, 'a' * 256]) {
      requisicao({
        'entrada': {...entrada, 'justificativa': justificativa},
      });
      expect(
        (await rota.onRequest(contexto)).statusCode,
        HttpStatus.badRequest,
      );
    }
    verifyNever(() => banco.runTx<Response>(any()));
  });

  test('recusa itens invalidos sem acessar o banco', () async {
    for (final itens in [
      null,
      'itens',
      <Object?>[],
      [null],
      [
        {'produto_id': 20, 'quantidade': 1},
        {'produto_id': 20, 'quantidade': 2},
      ],
      for (final id in [null, '20', 0, -1, 1.5, 2147483648])
        [
          {'produto_id': id, 'quantidade': 1},
        ],
      for (final quantidade in [null, '2', 0, -1, 0.001, 10000000000])
        [
          {'produto_id': 20, 'quantidade': quantidade},
        ],
    ]) {
      requisicao({
        'entrada': {...entrada, 'itens': itens},
      });
      expect(
        (await rota.onRequest(contexto)).statusCode,
        HttpStatus.badRequest,
      );
    }
    verifyNever(() => banco.runTx<Response>(any()));
  });

  test('recusa corpo e obra invalidos sem acessar o banco', () async {
    for (final dados in [
      null,
      <Object?>[],
      <String, dynamic>{},
      {'entrada': 'invalida'},
      for (final id in [null, '10', 0, -1, 1.5, 2147483648])
        {
          'entrada': {...entrada, 'obra_id': id},
        },
    ]) {
      requisicao(dados);
      expect(
        (await rota.onRequest(contexto)).statusCode,
        HttpStatus.badRequest,
      );
    }
    verifyNever(() => banco.runTx<Response>(any()));
  });

  for (final consulta in [6, 7, 8, 9]) {
    test(
      'falha na consulta $consulta propaga para reverter a transacao',
      () async {
        falhaNaConsulta = consulta;
        await expectLater(rota.onRequest(contexto), throwsStateError);
        expect(parametros, hasLength(consulta));
        verify(() => banco.runTx<Response>(any())).called(1);
      },
    );
  }

  test('estouro de saldo retorna 409 apos falhar a transacao', () async {
    final excecao = _ErroBanco();
    when(() => excecao.code).thenReturn('22003');
    falhaNaConsulta = 8;
    erro = excecao;
    final resposta = await rota.onRequest(contexto);
    expect(resposta.statusCode, HttpStatus.conflict);
    expect(parametros, hasLength(8));
  });

  test('outros erros de banco propagam para reverter a transacao', () async {
    final excecao = _ErroBanco();
    when(() => excecao.code).thenReturn('23503');
    falhaNaConsulta = 9;
    erro = excecao;
    await expectLater(rota.onRequest(contexto), throwsA(same(excecao)));
  });

  test('JSON malformado retorna 400 sem acessar o banco', () async {
    when(() => contexto.request).thenReturn(
      Request.post(Uri.parse('http://localhost/entradas'), body: '{'),
    );
    expect((await rota.onRequest(contexto)).statusCode, HttpStatus.badRequest);
    verifyNever(() => banco.runTx<Response>(any()));
  });

  test('metodos diferentes de POST retornam 405', () async {
    for (final metodo in ['GET', 'PATCH', 'DELETE']) {
      when(() => contexto.request).thenReturn(
        Request(metodo, Uri.parse('http://localhost/entradas')),
      );
      expect(
        (await rota.onRequest(contexto)).statusCode,
        HttpStatus.methodNotAllowed,
      );
    }
    verifyNever(() => banco.runTx<Response>(any()));
  });
}
