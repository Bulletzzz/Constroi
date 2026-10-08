import 'dart:convert';
import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../routes/estoque/_middleware.dart' as protecao;
import '../../routes/estoque/index.dart' as rota;

class _ContextoFalso extends Mock implements RequestContext {}

class _BancoFalso extends Mock implements Pool<void> {}

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
  late List<Result> resultados;
  late List<Map<String, dynamic>> parametros;
  const item = <String, dynamic>{
    'id': 1,
    'obra_id': 10,
    'produto_id': 2,
    'nome': 'Cimento',
    'unidade': 'saco',
    'sku': 'CIM-01',
    'quantidade': '4.50',
    'estoque_minimo': '5.00',
    'baixo': true,
  };

  void requisicao(String query) => when(() => contexto.request).thenReturn(
    Request.get(Uri.parse('http://localhost/estoque?$query')),
  );
  void autenticar(Nivel nivel) =>
      when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(
        UsuarioAutenticado(id: 7, empresaId: 3, nivel: nivel),
      );

  setUpAll(() => registerFallbackValue(Sql.named('')));
  setUp(() {
    contexto = _ContextoFalso();
    banco = _BancoFalso();
    parametros = [];
    resultados = [
      _resultado([
        {'id': 10},
      ]),
      _resultado([item]),
    ];
    autenticar(Nivel.pedreiro);
    requisicao('obra_id=10');
    when(() => contexto.read<Pool<void>>()).thenReturn(banco);
    when(
      () => banco.execute(any(), parameters: any(named: 'parameters')),
    ).thenAnswer((chamada) async {
      parametros.add(
        Map<String, dynamic>.from(
          chamada.namedArguments[#parameters] as Map,
        ),
      );
      return resultados.removeAt(0);
    });
  });

  for (final nivel in Nivel.values) {
    test(
      'consulta como ${nivel.name} usa empresa e visibilidade da obra',
      () async {
        autenticar(nivel);
        final resposta = await protecao.middleware(rota.onRequest)(contexto);
        expect(resposta.statusCode, HttpStatus.ok);
        expect(jsonDecode(await resposta.body()), {
          'estoque': [item],
        });
        expect(parametros.first, {
          'obra': 10,
          'empresa': 3,
          'usuario': 7,
          'todas': nivel != Nivel.pedreiro,
        });
        expect(parametros.last, {
          'empresa': 3,
          'obra': 10,
          'busca': '',
          'baixo': false,
          'limite': 50,
          'offset': 0,
        });
      },
    );
    test('obra inacessivel como ${nivel.name} nao consulta saldos', () async {
      autenticar(nivel);
      resultados = [_resultado([])];
      final resposta = await rota.onRequest(contexto);
      expect(resposta.statusCode, HttpStatus.notFound);
      expect(jsonDecode(await resposta.body()), {
        'erro': 'Obra nao encontrada.',
      });
      expect(parametros, hasLength(1));
    });
  }

  test('combina filtros, apara busca e mantem caracteres literais', () async {
    requisicao('obra_id=10&busca=%20CIM%25_%20&baixo=true&limit=20&offset=40');
    expect((await rota.onRequest(contexto)).statusCode, HttpStatus.ok);
    expect(parametros.last, {
      'empresa': 3,
      'obra': 10,
      'busca': 'CIM%_',
      'baixo': true,
      'limite': 20,
      'offset': 40,
    });
  });
  test('obra acessivel sem saldos retorna lista vazia', () async {
    resultados = [
      _resultado([
        {'id': 10},
      ]),
      _resultado([]),
    ];
    final resposta = await rota.onRequest(contexto);
    expect(resposta.statusCode, HttpStatus.ok);
    expect(jsonDecode(await resposta.body()), {'estoque': <Object?>[]});
  });
  for (final query in [
    '',
    'obra_id=0',
    'obra_id=-1',
    'obra_id=abc',
    'obra_id=2147483648',
    'obra_id=10&baixo=1',
    'obra_id=10&baixo=',
    'obra_id=10&limit=0',
    'obra_id=10&limit=201',
    'obra_id=10&limit=abc',
    'obra_id=10&offset=-1',
    'obra_id=10&offset=10001',
    'obra_id=10&busca=${'a' * 151}',
  ]) {
    test('filtro invalido $query retorna 400 sem acesso ao banco', () async {
      requisicao(query);
      expect(
        (await rota.onRequest(contexto)).statusCode,
        HttpStatus.badRequest,
      );
      expect(parametros, isEmpty);
    });
  }
  test('sem token retorna 401 sem acesso ao banco', () async {
    when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(null);
    expect(
      (await protecao.middleware(rota.onRequest)(contexto)).statusCode,
      HttpStatus.unauthorized,
    );
    expect(parametros, isEmpty);
  });
  test('POST retorna 405 sem escrita no banco', () async {
    when(() => contexto.request).thenReturn(
      Request.post(Uri.parse('http://localhost/estoque?obra_id=10')),
    );
    expect(
      (await protecao.middleware(rota.onRequest)(contexto)).statusCode,
      HttpStatus.methodNotAllowed,
    );
    expect(parametros, isEmpty);
  });
}
