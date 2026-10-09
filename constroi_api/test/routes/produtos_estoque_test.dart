import 'dart:convert';
import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../routes/produtos/[id].dart' as detalhe;
import '../../routes/produtos/_middleware.dart' as protecao;
import '../../routes/produtos/index.dart' as lista;

class _ContextoFalso extends Mock implements RequestContext {}

class _BancoFalso extends Mock implements Pool<void> {}

class _LinhaFalsa extends Mock implements ResultRow {}

class _ErroSku extends Mock implements ServerException {}

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
  const produto = <String, dynamic>{
    'id': 2,
    'empresa_id': 3,
    'nome': 'Cimento',
    'unidade': 'saco',
    'sku': 'CIM-01',
    'estoque_minimo': '5.00',
  };
  void requisicao(HttpMethod metodo, Map<String, dynamic> dados) {
    when(() => contexto.request).thenReturn(
      Request(
        metodo.name.toUpperCase(),
        Uri.parse('http://localhost/produtos/2'),
        body: jsonEncode({'produto': dados}),
        headers: {'content-type': 'application/json'},
      ),
    );
  }

  setUpAll(() => registerFallbackValue(Sql.named('')));
  setUp(() {
    contexto = _ContextoFalso();
    banco = _BancoFalso();
    parametros = [];
    resultados = [
      _resultado([]),
      _resultado([produto]),
    ];
    when(() => contexto.read<Pool<void>>()).thenReturn(banco);
    when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(
      const UsuarioAutenticado(id: 7, empresaId: 3, nivel: Nivel.engenheiro),
    );
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
  test('criacao antiga continua aceitando apenas nome e unidade', () async {
    requisicao(HttpMethod.post, {'nome': 'Cimento', 'unidade': 'saco'});
    final resposta = await lista.onRequest(contexto);
    expect(resposta.statusCode, HttpStatus.created);
    expect(parametros.last, {
      'empresa': 3,
      'nome': 'Cimento',
      'unidade': 'saco',
      'sku': null,
      'minimo': '0',
    });
  });
  test('criacao persiste SKU aparado e minimo decimal', () async {
    requisicao(HttpMethod.post, {
      'nome': 'Cimento',
      'unidade': 'saco',
      'sku': ' CIM-01 ',
      'estoque_minimo': '5,00',
    });
    final resposta = await lista.onRequest(contexto);
    expect(resposta.statusCode, HttpStatus.created);
    expect(jsonDecode(await resposta.body()), produto);
    expect(parametros.last['sku'], 'CIM-01');
    expect(parametros.last['minimo'], '5.00');
  });
  test('PATCH atualiza apenas minimo sem exigir nome ou unidade', () async {
    resultados = [
      _resultado([produto]),
    ];
    requisicao(HttpMethod.patch, {'estoque_minimo': 5});
    final resposta = await detalhe.onRequest(contexto, '2');
    expect(resposta.statusCode, HttpStatus.ok);
    expect(parametros.single, {'minimo': '5', 'id': 2, 'empresa': 3});
  });
  test('PATCH SKU null remove codigo sem alterar minimo', () async {
    resultados = [
      _resultado([
        {...produto, 'sku': null},
      ]),
    ];
    requisicao(HttpMethod.patch, {'sku': null});
    final resposta = await detalhe.onRequest(contexto, '2');
    expect(resposta.statusCode, HttpStatus.ok);
    expect(parametros.single, {'sku': null, 'id': 2, 'empresa': 3});
    expect((jsonDecode(await resposta.body()) as Map)['sku'], isNull);
  });
  test('GET lista e detalhe devolvem os novos campos', () async {
    requisicao(HttpMethod.get, {});
    resultados = [
      _resultado([produto]),
      _resultado([produto]),
    ];
    expect(jsonDecode(await (await lista.onRequest(contexto)).body()), {
      'produtos': [produto],
    });
    expect(
      jsonDecode(await (await detalhe.onRequest(contexto, '2')).body()),
      produto,
    );
  });
  for (final dados in <Map<String, dynamic>>[
    {'sku': 12},
    {'sku': 'a' * 51},
    {'estoque_minimo': null},
    {'estoque_minimo': -1},
    {'estoque_minimo': 0.001},
    {'estoque_minimo': '10000000000'},
  ]) {
    test('recusa complemento invalido $dados em POST e PATCH', () async {
      requisicao(HttpMethod.post, {
        'nome': 'Cimento',
        'unidade': 'saco',
        ...dados,
      });
      expect(
        (await lista.onRequest(contexto)).statusCode,
        HttpStatus.badRequest,
      );
      requisicao(HttpMethod.patch, dados);
      expect(
        (await detalhe.onRequest(contexto, '2')).statusCode,
        HttpStatus.badRequest,
      );
      expect(parametros, isEmpty);
    });
  }
  test('SKU duplicado retorna 409 na criacao e na edicao', () async {
    final erro = _ErroSku();
    when(() => erro.code).thenReturn('23505');
    when(() => erro.constraintName).thenReturn('ux_produto_sku_empresa');
    when(
      () => banco.execute(any(), parameters: any(named: 'parameters')),
    ).thenThrow(erro);
    requisicao(HttpMethod.post, {
      'nome': 'Cimento',
      'unidade': 'saco',
      'sku': 'CIM',
    });
    expect((await lista.onRequest(contexto)).statusCode, HttpStatus.conflict);
    requisicao(HttpMethod.patch, {'sku': 'CIM'});
    expect(
      (await detalhe.onRequest(contexto, '2')).statusCode,
      HttpStatus.conflict,
    );
  });
  test('pedreiro nao altera minimo nem SKU', () async {
    when(() => contexto.read<UsuarioAutenticado?>()).thenReturn(
      const UsuarioAutenticado(id: 7, empresaId: 3, nivel: Nivel.pedreiro),
    );
    requisicao(HttpMethod.post, {
      'nome': 'Cimento',
      'unidade': 'saco',
      'sku': 'CIM',
    });
    expect(
      (await protecao.middleware(lista.onRequest)(contexto)).statusCode,
      HttpStatus.forbidden,
    );
    expect(parametros, isEmpty);
  });
}
