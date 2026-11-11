import 'dart:convert';
import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/despesas.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../routes/custos/_middleware.dart' as protecao;
import '../../routes/custos/despesas/index.dart' as rota;

class _ContextoFalso extends Mock implements RequestContext {}

class _BancoFalso extends Mock implements Pool<void> {}

class _TransacaoFalsa extends Mock implements TxSession {}

class _LinhaFalsa extends Mock implements ResultRow {}

Result _resultado(List<Map<String, dynamic>> dados) => Result(
  rows: dados.map((dados) {
    final linha = _LinhaFalsa();
    when(linha.toColumnMap).thenReturn(dados);
    final valores = dados.values.toList();
    for (var posicao = 0; posicao < valores.length; posicao++) {
      when(() => linha[posicao]).thenReturn(valores[posicao]);
    }
    return linha;
  }).toList(),
  affectedRows: dados.length,
  schema: ResultSchema([]),
);

void main() {
  setUpAll(() {
    registerFallbackValue(Sql.named(''));
    registerFallbackValue(
      (TxSession _) async =>
          Result(rows: [], affectedRows: 0, schema: ResultSchema([])),
    );
  });

  late _ContextoFalso contexto;
  late _BancoFalso banco;
  late List<Result> resultados;
  late List<Map<String, dynamic>> parametros;
  late List<String> eventos;

  final gravada = <String, dynamic>{
    'id': 70,
    'obra_id': 10,
    'categoria_custo_id': 3,
    'descricao': 'Locacao de grua',
    'valor': '18500.00',
    'data_lancamento': DateTime.utc(2026, 11, 9, 12, 30),
  };

  const despesa = <String, dynamic>{
    'obra_id': 10,
    'categoria_custo_id': 3,
    'descricao': '  Locacao de grua  ',
    'valor': '18500.00',
  };

  void requisicao(Object? corpo, [HttpMethod metodo = HttpMethod.post]) {
    when(() => contexto.request).thenReturn(
      Request(
        metodo.name.toUpperCase(),
        Uri.parse('http://localhost/custos/despesas'),
        body: corpo is String ? corpo : jsonEncode(corpo),
        headers: {'content-type': 'application/json'},
      ),
    );
  }

  void autenticar(Nivel nivel) {
    when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(
      UsuarioAutenticado(id: 7, empresaId: 3, nivel: nivel),
    );
  }

  setUp(() {
    contexto = _ContextoFalso();
    banco = _BancoFalso();
    parametros = [];
    eventos = [];
    resultados = [
      _resultado([gravada]),
    ];

    final transacao = _TransacaoFalsa();
    when(() => banco.runTx<Result>(any())).thenAnswer((chamada) {
      final executar =
          chamada.positionalArguments.first
              as Future<Result> Function(TxSession);
      return executar(transacao);
    });
    when(
      () => transacao.execute(any(), parameters: any(named: 'parameters')),
    ).thenAnswer((chamada) async {
      final parameters =
          chamada.namedArguments[#parameters] as Map<String, dynamic>;
      if (parameters.containsKey('acao')) {
        eventos.add(parameters['acao'] as String);
        return Result(rows: [], affectedRows: 1, schema: ResultSchema([]));
      }
      return banco.execute(
        chamada.positionalArguments.first! as Object,
        parameters: parameters,
      );
    });
    when(
      () => banco.execute(any(), parameters: any(named: 'parameters')),
    ).thenAnswer((chamada) async {
      parametros.add(
        Map<String, dynamic>.from(chamada.namedArguments[#parameters] as Map),
      );
      return resultados.removeAt(0);
    });
    when(() => contexto.read<Pool<void>>()).thenReturn(banco);
    autenticar(Nivel.engenheiro);
    requisicao({'despesa': despesa});
  });

  group('valor', () {
    for (final caso in [
      ('1500', '1500.00'),
      ('1500.5', '1500.50'),
      ('1500.50', '1500.50'),
      (' 0.01 ', '0.01'),
      (1500, '1500.00'),
      ('999999999999.99', '999999999999.99'),
    ]) {
      test('${caso.$1} vira ${caso.$2}', () {
        expect(validarValorDespesa(caso.$1), caso.$2);
      });
    }

    for (final invalido in [
      '0',
      '0.00',
      '-10',
      '10,50',
      '1500.555',
      '1234567890123',
      'abc',
      '',
      null,
    ]) {
      test('$invalido nao e aceito', () {
        expect(validarValorDespesa(invalido), isNull);
      });
    }
  });

  group('descricao', () {
    test('apara e aceita ate 255 caracteres', () {
      expect(validarDescricaoDespesa('  Grua  '), 'Grua');
      expect(validarDescricaoDespesa('a' * 255), 'a' * 255);
    });

    for (final invalido in ['', '   ', null, 7]) {
      test('$invalido nao e aceito', () {
        expect(validarDescricaoDespesa(invalido), isNull);
      });
    }

    test('acima de 255 caracteres nao e aceito', () {
      expect(validarDescricaoDespesa('a' * 256), isNull);
    });
  });

  group('rota', () {
    test('grava a despesa, apara a descricao e registra o evento', () async {
      final resposta = await rota.onRequest(contexto);
      expect(resposta.statusCode, HttpStatus.created);
      expect(jsonDecode(await resposta.body()), {
        'id': 70,
        'obra_id': 10,
        'categoria_custo_id': 3,
        'descricao': 'Locacao de grua',
        'valor': '18500.00',
        'data_lancamento': '2026-11-09T12:30:00.000Z',
      });
      expect(parametros.single, {
        'empresa': 3,
        'obra': 10,
        'usuario': 7,
        'categoria': 3,
        'descricao': 'Locacao de grua',
        'valor': '18500.00',
      });
      expect(eventos, ['CRIACAO_DESPESA despesa=70']);
    });

    test('obra de outra empresa retorna 404 e nao registra evento', () async {
      resultados = [
        _resultado([]),
        _resultado([
          {'id': 3},
        ]),
      ];
      final resposta = await rota.onRequest(contexto);
      expect(resposta.statusCode, HttpStatus.notFound);
      expect(jsonDecode(await resposta.body()), {
        'erro': 'Obra nao encontrada para esta empresa.',
      });
      expect(eventos, isEmpty);
    });

    test('categoria inexistente retorna 400', () async {
      resultados = [_resultado([]), _resultado([])];
      final resposta = await rota.onRequest(contexto);
      expect(resposta.statusCode, HttpStatus.badRequest);
      expect(jsonDecode(await resposta.body()), {
        'erro': 'Categoria de custo nao encontrada.',
      });
      expect(eventos, isEmpty);
    });

    for (final caso in [
      {
        'despesa': {...despesa, 'obra_id': 0},
      },
      {
        'despesa': {...despesa, 'obra_id': '10'},
      },
      {
        'despesa': {...despesa, 'obra_id': null},
      },
      {
        'despesa': {...despesa, 'categoria_custo_id': -1},
      },
      {
        'despesa': {...despesa, 'descricao': '  '},
      },
      {
        'despesa': {...despesa, 'valor': '0'},
      },
      {
        'despesa': {...despesa, 'valor': '10,50'},
      },
      <String, dynamic>{},
      {'despesa': 'texto'},
      {'lancamento': despesa},
    ]) {
      test('corpo invalido $caso retorna 400 sem tocar o banco', () async {
        requisicao(caso);
        expect(
          (await rota.onRequest(contexto)).statusCode,
          HttpStatus.badRequest,
        );
        expect(parametros, isEmpty);
        expect(eventos, isEmpty);
      });
    }

    test('JSON malformado retorna 400 sem tocar o banco', () async {
      requisicao('{');
      expect(
        (await rota.onRequest(contexto)).statusCode,
        HttpStatus.badRequest,
      );
      expect(parametros, isEmpty);
    });

    for (final metodo in [HttpMethod.get, HttpMethod.patch, HttpMethod.put]) {
      test('${metodo.name} retorna 405 sem tocar o banco', () async {
        requisicao({'despesa': despesa}, metodo);
        expect(
          (await rota.onRequest(contexto)).statusCode,
          HttpStatus.methodNotAllowed,
        );
        expect(parametros, isEmpty);
      });
    }

    test('pedreiro nao alcanca o lancamento de despesa', () async {
      autenticar(Nivel.pedreiro);
      final resposta = await protecao
          .middleware((_) async => Response())
          .call(contexto);
      expect(resposta.statusCode, HttpStatus.forbidden);
      expect(parametros, isEmpty);
    });
  });
}
