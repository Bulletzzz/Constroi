import 'dart:convert';
import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../routes/obras/[id]/equipe/index.dart' as route;
import '../../routes/obras/_middleware.dart' as protecao;

class _ContextoFalso extends Mock implements RequestContext {}

class _BancoFalso extends Mock implements Pool<void> {}

class _TransacaoFalsa extends Mock implements TxSession {}

class _LinhaFalsa extends Mock implements ResultRow {}

Result _resultadoDados(Map<String, dynamic> dados) {
  final linha = _LinhaFalsa();
  when(linha.toColumnMap).thenReturn(dados);
  return Result(rows: [linha], affectedRows: 1, schema: ResultSchema([]));
}

Result _resultado({bool obraEncontrada = false}) {
  final schema = ResultSchema([
    ResultSchemaColumn(typeOid: 23, type: Type.integer, columnName: 'id'),
  ]);
  return Result(
    rows: [
      if (obraEncontrada) ResultRow(values: [7], schema: schema),
    ],
    affectedRows: 0,
    schema: schema,
  );
}

void main() {
  setUpAll(
    () => registerFallbackValue(
      (TxSession _) async =>
          Result(rows: [], affectedRows: 0, schema: ResultSchema([])),
    ),
  );
  setUpAll(() => registerFallbackValue(Sql.named('SELECT 1')));

  for (final nivel in Nivel.values) {
    group('GET equipe como ${nivel.name}', () {
      late RequestContext contexto;
      late _BancoFalso banco;
      late List<Map<String, dynamic>> consultas;

      setUp(() {
        contexto = _ContextoFalso();
        banco = _BancoFalso();
        consultas = [];
        when(() => contexto.request).thenReturn(
          Request.get(Uri.parse('http://localhost/obras/7/equipe')),
        );
        when(() => contexto.read<Pool<void>>()).thenReturn(banco);
        when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(
          UsuarioAutenticado(id: 3, empresaId: 2, nivel: nivel),
        );
      });

      void responder({required bool obraEncontrada}) {
        when(
          () => banco.execute(any(), parameters: any(named: 'parameters')),
        ).thenAnswer((invocacao) async {
          consultas.add(
            invocacao.namedArguments[#parameters]! as Map<String, dynamic>,
          );
          return _resultado(
            obraEncontrada: consultas.length == 1 && obraEncontrada,
          );
        });
      }

      test('obra inacessivel retorna 404 sem consultar membros', () async {
        responder(obraEncontrada: false);
        final resposta = await route.onRequest(contexto, '7');
        expect(resposta.statusCode, HttpStatus.notFound);
        expect(jsonDecode(await resposta.body()), {
          'erro': 'Obra nao encontrada.',
        });
        expect(consultas, hasLength(1));
        expect(consultas.single, {
          'obra': 7,
          'empresa': 2,
          'usuario': 3,
          'todas': nivel != Nivel.pedreiro,
        });
      });

      test('obra acessivel retorna equipe', () async {
        responder(obraEncontrada: true);
        final resposta = await route.onRequest(contexto, '7');
        expect(resposta.statusCode, HttpStatus.ok);
        expect(jsonDecode(await resposta.body()), {'equipe': <dynamic>[]});
        expect(consultas, hasLength(2));
        expect(consultas.first['todas'], nivel != Nivel.pedreiro);
        expect(consultas.last, {'obra': 7, 'empresa': 2});
      });
    });
  }

  group('POST equipe', () {
    late _ContextoFalso contexto;
    late _BancoFalso banco;
    late List<Map<String, dynamic>> consultas;
    late List<Result> resultados;

    Future<Response> chamar() async => protecao.middleware(
      (contexto) => route.onRequest(contexto, '7'),
    )(contexto);

    setUp(() {
      contexto = _ContextoFalso();
      banco = _BancoFalso();
      consultas = [];
      resultados = [
        _resultado(obraEncontrada: true),
        _resultado(obraEncontrada: true),
        _resultadoDados({
          'id': 11,
          'empresa_id': 2,
          'usuario_id': 9,
          'obra_id': 7,
          'data_inicio': DateTime.utc(2026, 10, 13),
        }),
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
          return Result(rows: [], affectedRows: 1, schema: ResultSchema([]));
        }
        return banco.execute(
          chamada.positionalArguments.first! as Object,
          parameters: parameters,
        );
      });
      when(() => contexto.request).thenReturn(
        Request.post(
          Uri.parse('http://localhost/obras/7/equipe'),
          body: jsonEncode({
            'equipe': {'usuario_id': 9, 'empresa_id': 99},
          }),
        ),
      );
      when(() => contexto.read<Pool<void>>()).thenReturn(banco);
      when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(
        const UsuarioAutenticado(id: 3, empresaId: 2, nivel: Nivel.engenheiro),
      );
      when(
        () => banco.execute(any(), parameters: any(named: 'parameters')),
      ).thenAnswer((chamada) async {
        consultas.add(
          chamada.namedArguments[#parameters]! as Map<String, dynamic>,
        );
        return resultados.removeAt(0);
      });
    });

    for (final nivel in [Nivel.engenheiro, Nivel.master]) {
      test('${nivel.name} cria vinculo usando a empresa da sessao', () async {
        when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(
          UsuarioAutenticado(id: 3, empresaId: 2, nivel: nivel),
        );
        final resposta = await chamar();
        expect(resposta.statusCode, HttpStatus.created);
        expect(consultas, [
          {'obra': 7, 'empresa': 2},
          {'usuario': 9, 'empresa': 2},
          {'empresa': 2, 'usuario': 9, 'obra': 7},
        ]);
        expect(jsonDecode(await resposta.body()), {
          'id': 11,
          'empresa_id': 2,
          'usuario_id': 9,
          'obra_id': 7,
          'data_inicio': '2026-10-13T00:00:00.000Z',
          'data_fim': null,
        });
      });
    }

    test('usuario nao encontrado no escopo retorna 404 e nao insere', () async {
      resultados[1] = _resultado();
      final resposta = await chamar();
      expect(resposta.statusCode, HttpStatus.notFound);
      expect(jsonDecode(await resposta.body()), {
        'erro': 'Usuario nao encontrado.',
      });
      expect(consultas, [
        {'obra': 7, 'empresa': 2},
        {'usuario': 9, 'empresa': 2},
      ]);
      expect(resultados, hasLength(1));
    });

    test(
      'obra fora do escopo retorna 404 antes de consultar usuario',
      () async {
        resultados[0] = _resultado();
        final resposta = await chamar();
        expect(resposta.statusCode, HttpStatus.notFound);
        expect(jsonDecode(await resposta.body()), {
          'erro': 'Obra nao encontrada.',
        });
        expect(consultas, [
          {'obra': 7, 'empresa': 2},
        ]);
      },
    );

    test('vinculo ativo duplicado continua recebendo 409', () async {
      resultados[2] = _resultado();
      final resposta = await chamar();
      expect(resposta.statusCode, HttpStatus.conflict);
      expect(jsonDecode(await resposta.body()), {
        'erro': 'Usuario ja possui vinculo ativo com esta obra.',
      });
      expect(consultas, hasLength(3));
    });

    test('pedreiro continua sem permissao de criar vinculos', () async {
      when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(
        const UsuarioAutenticado(id: 3, empresaId: 2, nivel: Nivel.pedreiro),
      );
      expect((await chamar()).statusCode, HttpStatus.forbidden);
      expect(consultas, isEmpty);
    });

    test('sem token continua recebendo 401 sem consultar o banco', () async {
      when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(null);
      expect((await chamar()).statusCode, HttpStatus.unauthorized);
      expect(consultas, isEmpty);
    });
  });
}
