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
  test('falha do banco nao expõe credenciais', () async {
    when(
      () => banco.execute(any(), parameters: any(named: 'parameters')),
    ).thenThrow(StateError('postgresql://segredo'));
    final resposta = await rota.onRequest(contexto);
    expect(resposta.statusCode, 503);
    expect(await resposta.body(), isNot(contains('segredo')));
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
