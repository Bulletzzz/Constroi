import 'dart:convert';
import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../routes/painel/_middleware.dart' as protecao;
import '../../routes/painel/index.dart' as rota;

class _Contexto extends Mock implements RequestContext {}

class _Banco extends Mock implements Pool<void> {}

class _Linha extends Mock implements ResultRow {}

void main() {
  late _Contexto contexto;
  late _Banco banco;
  late Map<String, dynamic> dados;
  late Map<String, Object?> parametros;

  void autenticar(Nivel? nivel) =>
      when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(
        nivel == null
            ? null
            : UsuarioAutenticado(id: 7, empresaId: 3, nivel: nivel),
      );
  void requisicao(String filtros) => when(() => contexto.request).thenReturn(
    Request.get(Uri.parse('http://localhost/painel$filtros')),
  );
  setUpAll(() => registerFallbackValue(Sql.named('')));
  setUp(() {
    contexto = _Contexto();
    banco = _Banco();
    parametros = {};
    autenticar(Nivel.master);
    requisicao('');
    dados = {
      'obra_permitida': true,
      'obras': <Object?>[],
      'obra_id': null,
      'atualizado_em': '2026-10-07T12:00:00Z',
      'indicadores': {
        'total_itens': 2,
        'rupturas_criticas': 1,
        'requisicoes_pendentes': 4,
        'obras_ativas': 1,
        'valor_estimado': '120.50',
        'itens_sem_preco': 1,
      },
      'movimentacoes': List.generate(6, (i) => {'id': 'ENT-$i'}),
    };
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

  for (final nivel in Nivel.values) {
    test(
      'usa o escopo do token para ${nivel.name} e protege valores',
      () async {
        autenticar(nivel);
        requisicao('?empresa_id=99&usuario_id=99&gestor=true&obra_id=10');
        final resposta = await protecao.middleware(rota.onRequest)(contexto);
        final corpo = jsonDecode(await resposta.body()) as Map;
        expect(resposta.statusCode, HttpStatus.ok);
        expect(parametros, {
          'empresa': 3,
          'usuario': 7,
          'gestor': nivel != Nivel.pedreiro,
          'obra': 10,
          'limite': 6,
          'offset': 0,
        });
        expect(
          (corpo['indicadores'] as Map).containsKey('valor_estimado'),
          nivel != Nivel.pedreiro,
        );
        expect(
          (corpo['indicadores'] as Map).containsKey('itens_sem_preco'),
          nivel != Nivel.pedreiro,
        );
        expect(corpo.containsKey('obra_permitida'), isFalse);
        expect(corpo['movimentacoes'], hasLength(5));
        expect(corpo['paginacao'], {
          'limite': 5,
          'offset': 0,
          'tem_mais': true,
        });
      },
    );
  }

  test('sem token responde 401 antes de consultar o banco', () async {
    autenticar(null);
    expect(
      (await protecao.middleware(rota.onRequest)(contexto)).statusCode,
      HttpStatus.unauthorized,
    );
    verifyNever(
      () => banco.execute(any(), parameters: any(named: 'parameters')),
    );
  });

  test('obra de outra empresa ou sem vinculo nao revela dados', () async {
    dados['obra_permitida'] = false;
    requisicao('?obra_id=10');
    final resposta = await rota.onRequest(contexto);
    expect(resposta.statusCode, HttpStatus.notFound);
    expect(jsonDecode(await resposta.body()), {'erro': 'Obra nao encontrada.'});
  });

  test('paginacao respeita limite, offset e fim da lista', () async {
    dados['movimentacoes'] = <Object?>[];
    requisicao('?limit=50&offset=100');
    final resposta = await rota.onRequest(contexto);
    expect(parametros['limite'], 51);
    expect(parametros['offset'], 100);
    expect((jsonDecode(await resposta.body()) as Map)['paginacao'], {
      'limite': 50,
      'offset': 100,
      'tem_mais': false,
    });
  });

  test('filtros invalidos nao consultam o banco', () async {
    for (final filtro in [
      'obra_id=',
      'obra_id=0',
      'obra_id=-1',
      'obra_id=2147483648',
      'obra_id=x',
      'limit=0',
      'limit=51',
      'offset=-1',
      'offset=10001',
      'offset=x',
    ]) {
      requisicao('?$filtro');
      expect(
        (await rota.onRequest(contexto)).statusCode,
        HttpStatus.badRequest,
        reason: filtro,
      );
    }
    verifyNever(
      () => banco.execute(any(), parameters: any(named: 'parameters')),
    );
  });

  test('falha do banco responde erro generico sem credenciais', () async {
    when(
      () => banco.execute(any(), parameters: any(named: 'parameters')),
    ).thenThrow(StateError('postgresql://segredo'));
    final resposta = await rota.onRequest(contexto);
    expect(resposta.statusCode, HttpStatus.serviceUnavailable);
    expect(await resposta.body(), isNot(contains('segredo')));
  });

  test('rota e somente leitura', () async {
    when(
      () => contexto.request,
    ).thenReturn(Request.post(Uri.parse('http://localhost/painel')));
    expect(
      (await rota.onRequest(contexto)).statusCode,
      HttpStatus.methodNotAllowed,
    );
    verifyNever(
      () => banco.execute(any(), parameters: any(named: 'parameters')),
    );
  });
}
