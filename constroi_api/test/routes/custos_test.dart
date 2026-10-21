import 'dart:async';
import 'dart:convert';

import 'package:constroi_api/autenticacao.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../routes/custos/_middleware.dart' as protecao;
import '../../routes/custos/index.dart' as rota;

class _Contexto extends Mock implements RequestContext {}

class _Banco extends Mock implements Pool<void> {}

class _Linha extends Mock implements ResultRow {}

void main() {
  late _Contexto contexto;
  late _Banco banco;
  late Map<String, dynamic> dados;
  late Map<String, Object?> parametros;
  void autenticar(Nivel? nivel) =>
      when(
        () => contexto.read<UsuarioAutenticado?>(),
      ).thenReturn(
        nivel == null
            ? null
            : UsuarioAutenticado(id: 7, empresaId: 3, nivel: nivel),
      );
  void requisicao(String filtros) => when(
    () => contexto.request,
  ).thenReturn(Request.get(Uri.parse('http://localhost/custos$filtros')));
  Future<Response> chamarComLogs(List<String> logs) => runZoned(
    () => rota.onRequest(contexto),
    zoneSpecification: ZoneSpecification(
      print: (_, _, _, mensagem) => logs.add(mensagem),
    ),
  );
  setUpAll(() => registerFallbackValue(Sql.named('')));
  setUp(() {
    contexto = _Contexto();
    banco = _Banco();
    parametros = {};
    autenticar(Nivel.engenheiro);
    requisicao('');
    dados = {'obra_permitida': true, 'lancamentos': <Object?>[]};
    when(() => contexto.read<Pool<void>>()).thenReturn(banco);
    when(
      () => banco.execute(any(), parameters: any(named: 'parameters')),
    ).thenAnswer((invocacao) async {
      parametros = Map<String, Object?>.from(
        invocacao.namedArguments[#parameters] as Map,
      );
      final linha = _Linha();
      when(linha.toColumnMap).thenReturn({'dados': dados});
      return Result(rows: [linha], affectedRows: 0, schema: ResultSchema([]));
    });
  });

  for (final nivel in [Nivel.engenheiro, Nivel.master]) {
    test('${nivel.name} consulta somente a empresa do token', () async {
      autenticar(nivel);
      requisicao('?empresa_id=99&obra_id=10&periodo=mes&limit=2&offset=4');
      dados['lancamentos'] = [
        {'id': 1},
        {'id': 2},
        {'id': 3},
      ];
      final resposta = await protecao.middleware(rota.onRequest)(contexto);
      final corpo = jsonDecode(await resposta.body()) as Map;
      expect(resposta.statusCode, 200);
      expect(parametros, {
        'empresa': 3,
        'obra': 10,
        'periodo': 'mes',
        'limite': 3,
        'offset': 4,
      });
      expect(corpo['lancamentos'], hasLength(2));
      expect(corpo['paginacao'], {'limite': 2, 'offset': 4, 'tem_mais': true});
      expect(corpo.containsKey('obra_permitida'), isFalse);
    });
  }
  for (final caso in [(null, 401), (Nivel.pedreiro, 403)]) {
    test('recusa ${caso.$1} antes de consultar custos', () async {
      autenticar(caso.$1);
      expect(
        (await protecao.middleware(rota.onRequest)(contexto)).statusCode,
        caso.$2,
      );
      verifyNever(
        () => banco.execute(any(), parameters: any(named: 'parameters')),
      );
    });
  }
  test('obra alheia ou inexistente retorna 404 sem revelar dados', () async {
    dados['obra_permitida'] = false;
    requisicao('?obra_id=10');
    final resposta = await rota.onRequest(contexto);
    expect(resposta.statusCode, 404);
    expect(jsonDecode(await resposta.body()), {'erro': 'Obra nao encontrada.'});
  });
  test('valida filtros antes de executar SQL', () async {
    for (final filtro in [
      'obra_id=',
      'obra_id=-1',
      'obra_id=2147483648',
      'limit=0',
      'limit=101',
      'offset=-1',
      'offset=x',
      'offset=2147483648',
      'periodo=',
      'periodo=ano',
    ]) {
      requisicao('?$filtro');
      expect((await rota.onRequest(contexto)).statusCode, 400, reason: filtro);
    }
    verifyNever(
      () => banco.execute(any(), parameters: any(named: 'parameters')),
    );
  });
  test('sem filtro usa historico completo e pagina vazia', () async {
    final resposta = await rota.onRequest(contexto);
    expect(parametros['periodo'], 'total');
    expect(parametros['obra'], isNull);
    expect((jsonDecode(await resposta.body()) as Map)['paginacao'], {
      'limite': 20,
      'offset': 0,
      'tem_mais': false,
    });
  });
  test('falha registra mensagem e pilha apenas no servidor', () async {
    const causa = 'relation "vw_lancamento_custo" does not exist';
    final pilha = StackTrace.fromString('custos.dart: banco.execute');
    when(
      () => banco.execute(any(), parameters: any(named: 'parameters')),
    ).thenAnswer((_) => Future<Result>.error(StateError(causa), pilha));
    final logs = <String>[];
    final resposta = await chamarComLogs(logs);
    expect(resposta.statusCode, 503);
    expect(logs, hasLength(1));
    expect(logs.single, contains('Falha na consulta de custos (StateError)'));
    expect(logs.single, contains(causa));
    expect(logs.single, contains(pilha.toString()));
    expect(jsonDecode(await resposta.body()), {
      'erro': 'Nao foi possivel consultar os custos. Tente novamente.',
    });
  });
  test('URLs PostgreSQL sao removidas da mensagem e da pilha', () async {
    for (final url in [
      'postgres://owner:senha-secreta@db.test/app?sslmode=require',
      'postgresql://owner:senha-secreta@db.test/app?sslmode=require',
      'POSTGRESQL://owner:senha-secreta@db.test/app?sslmode=require',
      'postgresql://owner:senha secreta@db.test/app?sslmode=require',
    ]) {
      final erro = FormatException('Conexao invalida', url);
      final pilha = StackTrace.fromString('conexao.dart:1 $url\ncustos.dart:2');
      when(
        () => banco.execute(any(), parameters: any(named: 'parameters')),
      ).thenAnswer((_) => Future<Result>.error(erro, pilha));
      final logs = <String>[];
      final resposta = await chamarComLogs(logs);
      expect(resposta.statusCode, 503);
      expect(logs, hasLength(1));
      expect(logs.single, contains('FormatException'));
      expect(logs.single, contains('Conexao invalida'));
      expect(logs.single, contains('conexao.dart:1'));
      expect(logs.single, contains('custos.dart:2'));
      expect(logs.single, contains('[conexao PostgreSQL omitida]'));
      final corpo = await resposta.body();
      for (final segredo in [
        url,
        'owner',
        'senha-secreta',
        'senha secreta',
        'db.test',
      ]) {
        expect(logs.single, isNot(contains(segredo)));
        expect(corpo, isNot(contains(segredo)));
      }
    }
  });
  test('resposta malformada do banco registra diagnostico', () async {
    dados['lancamentos'] = 'formato inesperado';
    final logs = <String>[];
    final resposta = await chamarComLogs(logs);
    expect(resposta.statusCode, 503);
    expect(logs, hasLength(1));
    expect(logs.single, contains('TypeError'));
    expect(logs.single, contains('onRequest'));
    expect(await resposta.body(), isNot(contains('TypeError')));
  });
  test('sucesso e erros de validacao nao geram logs de falha', () async {
    final logs = <String>[];
    expect((await chamarComLogs(logs)).statusCode, 200);
    dados['obra_permitida'] = false;
    expect((await chamarComLogs(logs)).statusCode, 404);
    requisicao('?limit=0');
    expect((await chamarComLogs(logs)).statusCode, 400);
    expect(logs, isEmpty);
  });
  test('aceita apenas leitura', () async {
    when(
      () => contexto.request,
    ).thenReturn(Request.post(Uri.parse('http://localhost/custos')));
    expect((await rota.onRequest(contexto)).statusCode, 405);
    verifyNever(
      () => banco.execute(any(), parameters: any(named: 'parameters')),
    );
  });
}
