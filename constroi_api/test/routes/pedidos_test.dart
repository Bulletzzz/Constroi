import 'dart:convert';
import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/pedidos.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../routes/pedidos/_middleware.dart' as protecao;
import '../../routes/pedidos/index.dart' as rota;

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
  late List<String> protocolos;
  late bool falharItem;

  const usuario = UsuarioAutenticado(
    id: 7,
    empresaId: 3,
    nivel: Nivel.pedreiro,
  );
  const corpo = {
    'pedido': {
      'obra_id': 10,
      'usuario_id': 99,
      'status': 'aprovado',
      'protocolo': 'forjado',
      'justificativa': ' Material para a obra ',
      'itens': [
        {'produto_id': 20, 'quantidade': 2.5},
        {'produto_id': 21, 'quantidade': 1},
      ],
    },
  };

  void requisicao(Object? dados) {
    when(() => contexto.request).thenReturn(
      Request.post(
        Uri.parse('http://localhost/pedidos'),
        body: jsonEncode(dados),
      ),
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
    falharItem = false;
    protocolos = ['PED-NOVO'];
    resultados = [
      _resultado([
        {'id': 10},
      ]),
      _resultado([
        {'id': 1},
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
          'protocolo': 'PED-NOVO',
          'status': 'pendente',
          'justificativa': 'Material para a obra',
          'data': DateTime.utc(2026, 10, 4),
        },
      ]),
      _resultado([
        {'id': 40, 'produto_id': 20, 'quantidade': '2.50'},
      ]),
      _resultado([
        {'id': 41, 'produto_id': 21, 'quantidade': '1.00'},
      ]),
    ];
    when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(usuario);
    when(() => contexto.read<Pool<void>>()).thenReturn(banco);
    when(() => contexto.read<GeradorProtocolo>()).thenReturn(
      () => protocolos.removeAt(0),
    );
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
      if (falharItem && parametros.last['produto'] == 21) {
        throw StateError('Falha ao inserir o segundo item.');
      }
      return resultados.removeAt(0);
    });
    requisicao(corpo);
  });

  test('cria pedido e itens na mesma transacao com dados do token', () async {
    final resposta = await protecao.middleware(rota.onRequest)(contexto);
    final dados = jsonDecode(await resposta.body()) as Map<String, dynamic>;
    expect(resposta.statusCode, HttpStatus.created);
    expect(dados['status'], 'pendente');
    expect(dados['protocolo'], 'PED-NOVO');
    expect(dados['usuario_id'], 7);
    expect(dados['itens'], hasLength(2));
    expect(dados['data'], '2026-10-04T00:00:00.000Z');
    expect(parametros[0], {'obra': 10, 'empresa': 3});
    expect(parametros[2], {
      'empresa': 3,
      'produtos': [20, 21],
    });
    expect(parametros[3]['usuario'], 7);
    expect(parametros[3]['protocolo'], 'PED-NOVO');
    expect(parametros[3]['justificativa'], 'Material para a obra');
    expect(parametros[4], {'pedido': 30, 'produto': 20, 'quantidade': '2.50'});
    expect(parametros[5], {'pedido': 30, 'produto': 21, 'quantidade': '1.00'});
    verify(() => banco.runTx<Response>(any())).called(1);
    expect(resultados, isEmpty);
  });

  test(
    'colisao de protocolo gera nova tentativa antes de salvar itens',
    () async {
      resultados.insert(3, _resultado([]));
      protocolos.insert(0, 'PED-EXISTENTE');
      final resposta = await rota.onRequest(contexto);
      expect(resposta.statusCode, HttpStatus.created);
      expect(parametros[3]['protocolo'], 'PED-EXISTENTE');
      expect(parametros[4]['protocolo'], 'PED-NOVO');
      expect(parametros.where((p) => p.containsKey('pedido')), hasLength(2));
      expect(resultados, isEmpty);
    },
  );

  test('colisoes persistentes retornam 503 sem inserir itens', () async {
    resultados = [
      ...resultados.take(3),
      ...List.generate(5, (_) => _resultado([])),
    ];
    protocolos = List.filled(5, 'PED-EXISTENTE', growable: true);
    final resposta = await rota.onRequest(contexto);
    expect(resposta.statusCode, HttpStatus.serviceUnavailable);
    expect(parametros.where((p) => p.containsKey('pedido')), isEmpty);
    expect(resultados, isEmpty);
  });

  test('sem token retorna 401 antes de acessar o banco', () async {
    when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(null);
    final resposta = await protecao.middleware(rota.onRequest)(contexto);
    expect(resposta.statusCode, HttpStatus.unauthorized);
    verifyNever(() => banco.runTx<Response>(any()));
  });

  test('obra inexistente ou de outra empresa retorna 404', () async {
    resultados[0] = _resultado([]);
    final resposta = await rota.onRequest(contexto);
    expect(resposta.statusCode, HttpStatus.notFound);
    expect(parametros, hasLength(1));
  });

  test('pedreiro sem vinculo ativo retorna 403', () async {
    resultados[1] = _resultado([]);
    final resposta = await rota.onRequest(contexto);
    expect(resposta.statusCode, HttpStatus.forbidden);
    expect(parametros, hasLength(2));
  });

  for (final nivel in [Nivel.engenheiro, Nivel.master]) {
    test('${nivel.name} pode pedir sem vinculo na obra', () async {
      when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(
        UsuarioAutenticado(id: 7, empresaId: 3, nivel: nivel),
      );
      resultados.removeAt(1);
      final resposta = await protecao.middleware(rota.onRequest)(contexto);
      expect(resposta.statusCode, HttpStatus.created);
      expect(parametros, hasLength(5));
    });
  }

  test('produto inexistente ou de outra empresa nao grava pedido', () async {
    resultados[2] = _resultado([
      {'id': 20},
    ]);
    final resposta = await rota.onRequest(contexto);
    expect(resposta.statusCode, HttpStatus.badRequest);
    expect(parametros, hasLength(3));
  });

  test(
    'falha ao inserir item propaga o erro para reverter a transacao',
    () async {
      falharItem = true;
      await expectLater(rota.onRequest(contexto), throwsStateError);
      expect(parametros.last['produto'], 21);
      verify(() => banco.runTx<Response>(any())).called(1);
    },
  );

  test(
    'corpo invalido e itens invalidos retornam 400 sem acessar o banco',
    () async {
      for (final dados in [
        null,
        <String, dynamic>{},
        {
          'pedido': {'obra_id': 10, 'itens': <Object?>[]},
        },
        {
          'pedido': {
            ...corpo['pedido']!,
            'justificativa': 123,
          },
        },
      ]) {
        requisicao(dados);
        final resposta = await rota.onRequest(contexto);
        expect(resposta.statusCode, HttpStatus.badRequest);
      }
      verifyNever(() => banco.runTx<Response>(any()));
    },
  );

  test('JSON malformado retorna 400', () async {
    when(() => contexto.request).thenReturn(
      Request.post(Uri.parse('http://localhost/pedidos'), body: '{'),
    );
    expect((await rota.onRequest(contexto)).statusCode, HttpStatus.badRequest);
    verifyNever(() => banco.runTx<Response>(any()));
  });

  test('metodos diferentes de GET e POST retornam 405', () async {
    when(() => contexto.request).thenReturn(
      Request.delete(Uri.parse('http://localhost/pedidos')),
    );
    expect(
      (await rota.onRequest(contexto)).statusCode,
      HttpStatus.methodNotAllowed,
    );
    verifyNever(() => banco.runTx<Response>(any()));
  });
}
