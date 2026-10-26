import '../../core/api/api_client.dart';

class CategoriaCusto {
  const CategoriaCusto({required this.id, required this.nome});
  final int id;
  final String nome;

  static CategoriaCusto? talvezDoJson(Object? dados) {
    if (dados is! Map) return null;
    final id = dados['id'];
    final nome = '${dados['nome'] ?? ''}'.trim();
    if (id is! int || nome.isEmpty) return null;
    return CategoriaCusto(id: id, nome: nome);
  }
}

class ItemCadastrado {
  const ItemCadastrado({required this.id, required this.nome});
  final int id;
  final String nome;
}

class CadastroService {
  CadastroService({required ApiClient api}) : _api = api;
  final ApiClient _api;

  Future<List<CategoriaCusto>> categorias() async {
    final resposta = await _api
        .get('categorias')
        .timeout(const Duration(seconds: 15));
    final lista = (resposta as Map)['categorias'];
    if (lista is! List) {
      throw const ApiException(502, 'Resposta de categorias inválida.');
    }
    return lista
        .map(CategoriaCusto.talvezDoJson)
        .whereType<CategoriaCusto>()
        .toList();
  }

  Future<ItemCadastrado> criarProduto({
    required String nome,
    required String unidade,
    String? sku,
    String? estoqueMinimo,
    int? categoriaId,
  }) async {
    final produto = <String, Object?>{'nome': nome, 'unidade': unidade};
    if (sku != null && sku.isNotEmpty) produto['sku'] = sku;
    if (estoqueMinimo != null && estoqueMinimo.isNotEmpty) {
      produto['estoque_minimo'] = estoqueMinimo;
    }
    if (categoriaId != null) produto['categoria_custo_id'] = categoriaId;

    final resposta = await _api
        .post('produtos', body: {'produto': produto})
        .timeout(const Duration(seconds: 20));
    return _item(resposta, 'produto');
  }

  Future<ItemCadastrado> criarEquipamento({
    required String nome,
    required String patrimonio,
    required String status,
  }) async {
    final resposta = await _api
        .post(
          'equipamentos',
          body: {
            'equipamento': {
              'nome': nome,
              'patrimonio': patrimonio,
              'status': status,
            },
          },
        )
        .timeout(const Duration(seconds: 20));
    return _item(resposta, 'equipamento');
  }

  ItemCadastrado _item(Object? resposta, String tipo) {
    if (resposta is! Map) {
      throw ApiException(502, 'Resposta inválida ao cadastrar $tipo.');
    }
    final id = resposta['id'];
    final nome = '${resposta['nome'] ?? ''}'.trim();
    if (id is! int || nome.isEmpty) {
      throw ApiException(502, 'Resposta inválida ao cadastrar $tipo.');
    }
    return ItemCadastrado(id: id, nome: nome);
  }
}
