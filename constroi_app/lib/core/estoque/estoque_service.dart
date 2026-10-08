import '../api/api_client.dart';
import 'item_estoque.dart';

const limiteMinimo = 1;
const limiteMaximo = 200;
const limitePadrao = 50;

class PaginaDeEstoque {
  const PaginaDeEstoque({required this.itens, required this.temMais});

  final List<ItemEstoque> itens;
  final bool temMais;
}

class EstoqueService {
  EstoqueService({required ApiClient api}) : _api = api;

  final ApiClient _api;

  Future<PaginaDeEstoque> listar({
    int? obraId,
    String busca = '',
    int? categoriaId,
    bool somenteBaixo = false,
    int limite = limitePadrao,
    int deslocamento = 0,
  }) async {
    if (limite < limiteMinimo || limite > limiteMaximo) {
      throw ArgumentError.value(limite, 'limite');
    }
    if (deslocamento < 0) {
      throw ArgumentError.value(deslocamento, 'deslocamento');
    }

    final consulta = <String, String>{
      'limit': '$limite',
      'offset': '$deslocamento',
    };
    if (obraId != null) consulta['obra_id'] = '$obraId';
    if (categoriaId != null) consulta['categoria_id'] = '$categoriaId';
    if (somenteBaixo) consulta['baixo'] = 'true';
    final termo = busca.trim();
    if (termo.isNotEmpty) consulta['busca'] = termo;

    final resposta = await _api.get('estoque', query: consulta);
    if (resposta is! Map || resposta['estoque'] is! List) {
      throw const ApiException(500, 'Resposta inesperada do servidor.');
    }

    final itens = (resposta['estoque'] as List)
        .map(ItemEstoque.talvezDoJson)
        .whereType<ItemEstoque>()
        .toList();

    return PaginaDeEstoque(
      itens: itens,
      temMais: (resposta['estoque'] as List).length >= limite,
    );
  }
}
