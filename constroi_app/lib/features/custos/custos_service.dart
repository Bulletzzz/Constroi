import '../../core/api/api_client.dart';
import 'custos_model.dart';

class CustosService {
  CustosService({required ApiClient api}) : _api = api;
  final ApiClient _api;

  Future<List<CategoriaDeCusto>> categorias() async {
    final resposta = await _api
        .get('categorias')
        .timeout(const Duration(seconds: 15));
    final lista = (resposta as Map)['categorias'];
    if (lista is! List) {
      throw const ApiException(502, 'Resposta de categorias inválida.');
    }
    return lista
        .map(CategoriaDeCusto.talvezDoJson)
        .whereType<CategoriaDeCusto>()
        .toList();
  }

  Future<void> lancarDespesa({
    required int obraId,
    required int categoriaId,
    required String descricao,
    required String valor,
  }) => _api
      .post(
        'custos/despesas',
        body: {
          'despesa': {
            'obra_id': obraId,
            'categoria_custo_id': categoriaId,
            'descricao': descricao,
            'valor': valor,
          },
        },
      )
      .timeout(const Duration(seconds: 20));

  Future<DadosCustos> carregar({
    int? obraId,
    String periodo = 'total',
    int offset = 0,
  }) async {
    final resposta = await _api
        .get(
          'custos',
          query: {
            if (obraId != null) 'obra_id': '$obraId',
            'periodo': periodo,
            'limit': '20',
            'offset': '$offset',
          },
        )
        .timeout(const Duration(seconds: 15));
    try {
      return DadosCustos.fromJson(resposta as Map);
    } catch (_) {
      throw const ApiException(
        502,
        'Resposta de custos inválida. Tente novamente.',
      );
    }
  }
}
