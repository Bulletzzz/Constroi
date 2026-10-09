import 'dart:convert';

import 'package:constroi_app/core/api/api_client.dart';
import 'package:constroi_app/core/api/api_config.dart';
import 'package:constroi_app/core/auth/session_manager.dart';
import 'package:constroi_app/features/estoque/estoque_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'login_screen_test.dart' show MemoryTokenStorage;

const _umItem = {
  'id': 1,
  'obra_id': 3,
  'produto_id': 7,
  'produto_nome': 'Cimento CP-II',
  'unidade': 'SC',
  'categoria_custo_id': 2,
  'categoria_nome': 'Material',
  'quantidade': '12.50',
};

({EstoqueService estoque, List<Uri> chamadas}) montar(
  http.Response Function(http.Request) responder,
) {
  final chamadas = <Uri>[];
  final api = ApiClient(
    config: ApiConfig('https://api.constroi.test'),
    sessions: SessionManager(MemoryTokenStorage()),
    httpClient: MockClient((requisicao) async {
      chamadas.add(requisicao.url);
      return responder(requisicao);
    }),
  );
  return (estoque: EstoqueService(api: api), chamadas: chamadas);
}

http.Response _comItens(List<Object> itens) =>
    http.Response(jsonEncode({'estoque': itens}), 200);

void main() {
  test('monta a consulta com todos os filtros', () async {
    final tudo = montar((_) => _comItens([_umItem]));

    await tudo.estoque.listar(
      obraId: 3,
      busca: '  cimento  ',
      categoriaId: 2,
      somenteBaixo: true,
      limite: 20,
      deslocamento: 40,
    );

    expect(tudo.chamadas.single.queryParameters, {
      'limit': '20',
      'offset': '40',
      'obra_id': '3',
      'categoria_id': '2',
      'baixo': 'true',
      'busca': 'cimento',
    });
  });

  test('omite filtros vazios e o baixo quando nao marcado', () async {
    final tudo = montar((_) => _comItens([]));

    await tudo.estoque.listar(busca: '   ');

    expect(tudo.chamadas.single.queryParameters, {
      'limit': '50',
      'offset': '0',
    });
  });

  test('converte os campos do item', () async {
    final tudo = montar((_) => _comItens([_umItem]));

    final pagina = await tudo.estoque.listar();
    final item = pagina.itens.single;

    expect(item.id, 1);
    expect(item.produtoNome, 'Cimento CP-II');
    expect(item.unidade, 'SC');
    expect(item.categoriaNome, 'Material');
    expect(item.quantidade, '12.50');
  });

  test('quantidade continua texto para nao perder centavo', () async {
    final tudo = montar((_) => _comItens([
      {..._umItem, 'quantidade': '1234567.89'},
    ]));

    final pagina = await tudo.estoque.listar();

    expect(pagina.itens.single.quantidade, '1234567.89');
  });

  test('item malformado e ignorado sem derrubar a lista', () async {
    final tudo = montar((_) => _comItens([
      _umItem,
      {'id': null, 'obra_id': 'x'},
      {..._umItem, 'id': 2},
    ]));

    final pagina = await tudo.estoque.listar();

    expect(pagina.itens.map((i) => i.id), [1, 2]);
  });

  test('pagina cheia indica que pode ter mais', () async {
    final tudo = montar(
      (_) => _comItens(List.generate(5, (i) => {..._umItem, 'id': i + 1})),
    );

    final pagina = await tudo.estoque.listar(limite: 5);

    expect(pagina.temMais, isTrue);
  });

  test('pagina incompleta indica fim da lista', () async {
    final tudo = montar(
      (_) => _comItens(List.generate(3, (i) => {..._umItem, 'id': i + 1})),
    );

    final pagina = await tudo.estoque.listar(limite: 5);

    expect(pagina.temMais, isFalse);
  });

  test('recusa limite e deslocamento fora da faixa', () {
    final tudo = montar((_) => _comItens([]));

    expect(() => tudo.estoque.listar(limite: 0), throwsArgumentError);
    expect(() => tudo.estoque.listar(limite: 201), throwsArgumentError);
    expect(() => tudo.estoque.listar(deslocamento: -1), throwsArgumentError);
  });

  test('resposta fora do formato vira ApiException', () async {
    final tudo = montar((_) => http.Response(jsonEncode({'itens': []}), 200));

    await expectLater(
      tudo.estoque.listar(),
      throwsA(isA<ApiException>()),
    );
  });

  test('erro da API sobe para a tela tratar', () async {
    final tudo = montar(
      (_) => http.Response(jsonEncode({'erro': 'Obra invalida.'}), 400),
    );

    await expectLater(
      tudo.estoque.listar(),
      throwsA(
        isA<ApiException>().having((e) => e.message, 'mensagem', 'Obra invalida.'),
      ),
    );
  });
}
