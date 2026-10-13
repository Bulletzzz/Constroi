import 'dart:convert';
import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/pedidos.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../routes/pedidos/[id].dart' as rota;
import '../../routes/pedidos/_middleware.dart' as protecao;

class _ContextoFalso extends Mock implements RequestContext {}

class _BancoFalso extends Mock implements Pool<void> {}

class _TransacaoFalsa extends Mock implements TxSession {}

class _LinhaFalsa extends Mock implements ResultRow {}

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
  late Map<String, dynamic> pedido;
  late bool falharLog;

  void requisicao(Object? dados) {
    when(() => contexto.request).thenReturn(
      Request.patch(
        Uri.parse('http://localhost/pedidos/30'),
        body: jsonEncode(dados),
      ),
    );
  }

  Future<Response> decidir({String id = '30'}) async => protecao.middleware(
    (contexto) => rota.onRequest(contexto, id),
  )(contexto);

  void autenticar(Nivel nivel) {
    when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(
      UsuarioAutenticado(id: 7, empresaId: 3, nivel: nivel),
    );
  }

  setUpAll(() {
    registerFallbackValue(Sql.named(''));
    registerFallbackValue((TxSession _) async => Response());
    registerFallbackValue(() => gerarProtocolo);
  });

  setUp(() {
    contexto = _ContextoFalso();
    banco = _BancoFalso();
    transacao = _TransacaoFalsa();
    parametros = [];
    falharLog = false;
    pedido = {
      'id': 30,
      'usuario_id': 99,
      'obra_id': 10,
      'protocolo': 'PED-EXISTENTE',
      'status': 'aprovado',
      'justificativa': 'Material para a obra',
      'data': DateTime.utc(2026, 10, 4),
    };
    resultados = [
      _resultado([
        {'status': 'pendente'},
      ]),
      _resultado([pedido]),
      _resultado([]),
    ];
    autenticar(Nivel.engenheiro);
    when(() => contexto.read<Pool<void>>()).thenReturn(banco);
    when(() => contexto.provide<GeradorProtocolo>(any())).thenReturn(contexto);
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
      if (falharLog && parametros.last.containsKey('acao')) {
        throw StateError('Falha ao gravar o log.');
      }
      return resultados.removeAt(0);
    });
    requisicao({
      'pedido': {'status': 'aprovado'},
    });
  });

  for (final nivel in [Nivel.engenheiro, Nivel.master]) {
    test(
      '${nivel.name} aprova e registra a decisao na mesma transacao',
      () async {
        autenticar(nivel);
        requisicao({
          'pedido': {
            'status': ' APROVADO ',
            'usuario_id': 999,
            'empresa_id': 999,
          },
        });
        final resposta = await decidir();
        final corpo = jsonDecode(await resposta.body()) as Map<String, dynamic>;
        expect(resposta.statusCode, HttpStatus.ok);
        expect(corpo, {...pedido, 'data': '2026-10-04T00:00:00.000Z'});
        expect(parametros, [
          {'id': 30, 'empresa': 3},
          {'id': 30, 'status': 'aprovado', 'justificativa': null},
          {'usuario': 7, 'acao': 'Pedido 30 aprovado.'},
        ]);
        verify(() => banco.runTx<Response>(any())).called(1);
        expect(resultados, isEmpty);
      },
    );
  }

  test('recusa salva a justificativa sem espacos nas extremidades', () async {
    pedido['status'] = 'recusado';
    pedido['justificativa'] = 'Material desnecessario';
    requisicao({
      'pedido': {
        'status': 'recusado',
        'justificativa': ' Material desnecessario ',
      },
    });
    final resposta = await decidir();
    final corpo = jsonDecode(await resposta.body()) as Map<String, dynamic>;
    expect(resposta.statusCode, HttpStatus.ok);
    expect(corpo['status'], 'recusado');
    expect(corpo['justificativa'], 'Material desnecessario');
    expect(parametros[1], {
      'id': 30,
      'status': 'recusado',
      'justificativa': 'Material desnecessario',
    });
    expect(parametros.last, {'usuario': 7, 'acao': 'Pedido 30 recusado.'});
  });

  test(
    'recusa sem justificativa retorna 400 antes de acessar o banco',
    () async {
      for (final dados in [
        {'status': 'recusado'},
        {'status': 'recusado', 'justificativa': null},
        {'status': 'recusado', 'justificativa': ''},
        {'status': 'recusado', 'justificativa': ' \n\t '},
      ]) {
        requisicao({'pedido': dados});
        final resposta = await decidir();
        expect(resposta.statusCode, HttpStatus.badRequest);
        expect(jsonDecode(await resposta.body()), {
          'erro': 'Informe a justificativa da recusa.',
        });
      }
      verifyNever(() => banco.runTx<Response>(any()));
    },
  );

  test('corpo, status e justificativa invalidos retornam 400', () async {
    for (final dados in [
      null,
      <Object?>[],
      <String, dynamic>{},
      {'status': 'aprovado'},
      {'pedido': <Object?>[]},
      {'pedido': <String, dynamic>{}},
      {
        'pedido': {'status': 'pendente'},
      },
      {
        'pedido': {'status': 1},
      },
      {
        'pedido': {'status': 'aprovado', 'justificativa': 123},
      },
      {
        'pedido': {'status': 'recusado', 'justificativa': 'a' * 256},
      },
    ]) {
      requisicao(dados);
      expect((await decidir()).statusCode, HttpStatus.badRequest);
    }
    verifyNever(() => banco.runTx<Response>(any()));
  });

  test('JSON malformado retorna 400', () async {
    when(() => contexto.request).thenReturn(
      Request.patch(Uri.parse('http://localhost/pedidos/30'), body: '{'),
    );
    expect((await decidir()).statusCode, HttpStatus.badRequest);
    verifyNever(() => banco.runTx<Response>(any()));
  });

  test('sem token retorna 401 e pedreiro retorna 403', () async {
    when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(null);
    expect((await decidir()).statusCode, HttpStatus.unauthorized);
    autenticar(Nivel.pedreiro);
    expect((await decidir()).statusCode, HttpStatus.forbidden);
    verifyNever(() => banco.runTx<Response>(any()));
  });

  test(
    'pedido inexistente ou de outra empresa retorna 404 sem decidir',
    () async {
      resultados = [_resultado([])];
      expect((await decidir()).statusCode, HttpStatus.notFound);
      expect(parametros, [
        {'id': 30, 'empresa': 3},
      ]);
    },
  );

  for (final status in ['aprovado', 'recusado']) {
    test(
      'pedido $status nao pode ser aprovado ou recusado novamente',
      () async {
        for (final decisao in ['aprovado', 'recusado']) {
          resultados = [
            _resultado([
              {'status': status},
            ]),
          ];
          requisicao({
            'pedido': {'status': decisao, 'justificativa': 'Nova decisao'},
          });
          final resposta = await decidir();
          expect(resposta.statusCode, HttpStatus.conflict);
          expect(jsonDecode(await resposta.body()), {
            'erro': 'Este pedido ja foi decidido.',
          });
        }
        expect(parametros, hasLength(2));
        expect(parametros.every((p) => p.containsKey('empresa')), isTrue);
      },
    );
  }

  test('falha no log propaga o erro para reverter a decisao', () async {
    falharLog = true;
    await expectLater(decidir(), throwsStateError);
    expect(parametros.last, {'usuario': 7, 'acao': 'Pedido 30 aprovado.'});
    verify(() => banco.runTx<Response>(any())).called(1);
  });

  test('IDs invalidos retornam 400 sem acessar o banco', () async {
    for (final id in ['', 'abc', '0', '-1', '1.5', '2147483648']) {
      expect((await decidir(id: id)).statusCode, HttpStatus.badRequest);
    }
    verifyNever(() => banco.runTx<Response>(any()));
  });
}
