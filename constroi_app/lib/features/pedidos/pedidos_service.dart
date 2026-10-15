import '../../core/api/api_client.dart';
import 'pedido.dart';

class ProdutoDoCatalogo {
  const ProdutoDoCatalogo({
    required this.id,
    required this.nome,
    required this.unidade,
    this.sku,
    this.categoriaId,
    this.categoriaNome,
  });

  final int id;
  final String nome;
  final String unidade;
  final String? sku;
  final int? categoriaId;
  final String? categoriaNome;

  String get identificacao => sku == null ? nome : '$nome · $sku';

  static ProdutoDoCatalogo? talvezDoJson(Object? dados) {
    if (dados is! Map) return null;
    final id = dados['id'];
    if (id is! int) return null;
    final nome = '${dados['nome'] ?? ''}'.trim();
    if (nome.isEmpty) return null;
    return ProdutoDoCatalogo(
      id: id,
      nome: nome,
      unidade: '${dados['unidade'] ?? 'un'}'.trim(),
      sku: _texto(dados['sku']),
      categoriaId: dados['categoria_custo_id'] is int
          ? dados['categoria_custo_id'] as int
          : null,
      categoriaNome: _texto(dados['categoria_nome']),
    );
  }
}

class ObraDisponivel {
  const ObraDisponivel({required this.id, required this.nome});

  final int id;
  final String nome;

  static ObraDisponivel? talvezDoJson(Object? dados) {
    if (dados is! Map) return null;
    final id = dados['id'];
    if (id is! int) return null;
    final nome = '${dados['nome'] ?? ''}'.trim();
    return ObraDisponivel(id: id, nome: nome.isEmpty ? 'Obra $id' : nome);
  }
}

const limiteDaFila = 50;

class PedidosService {
  PedidosService({required ApiClient api}) : _api = api;

  final ApiClient _api;

  Future<List<ObraDisponivel>> obras() async {
    final resposta = await _api.get('obras');
    return _lista(resposta, 'obras')
        .map(ObraDisponivel.talvezDoJson)
        .whereType<ObraDisponivel>()
        .toList();
  }

  Future<List<ProdutoDoCatalogo>> catalogo() async {
    final resposta = await _api.get('produtos');
    final produtos = _lista(resposta, 'produtos')
        .map(ProdutoDoCatalogo.talvezDoJson)
        .whereType<ProdutoDoCatalogo>()
        .toList();
    produtos.sort(
      (a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()),
    );
    return produtos;
  }

  Future<Pedido> criar({
    required int obraId,
    required int produtoId,
    required num quantidade,
    required Urgencia urgencia,
    String? localObra,
    String? justificativa,
  }) async {
    final pedido = <String, Object?>{
      'obra_id': obraId,
      'urgencia': urgencia.valor,
      'itens': [
        {'produto_id': produtoId, 'quantidade': quantidade},
      ],
    };
    final local = localObra?.trim();
    if (local != null && local.isNotEmpty) pedido['local_obra'] = local;
    final motivo = justificativa?.trim();
    if (motivo != null && motivo.isNotEmpty) pedido['justificativa'] = motivo;

    final resposta = await _api.post('pedidos', body: {'pedido': pedido});
    final criado = Pedido.talvezDoJson(resposta);
    if (criado == null) {
      throw const ApiException(502, 'A API não devolveu o pedido criado.');
    }
    return criado;
  }

  Future<List<Pedido>> pendentes({int? obraId}) async {
    final consulta = <String, String>{
      'status': 'pendente',
      'limit': '$limiteDaFila',
    };
    if (obraId != null) consulta['obra_id'] = '$obraId';
    final resposta = await _api.get('pedidos', query: consulta);
    return _lista(resposta, 'pedidos')
        .map(Pedido.talvezDoJson)
        .whereType<Pedido>()
        .toList();
  }

  Future<Pedido> aprovar(int id) => _decidir(id, 'aprovado', null);

  Future<Pedido> recusar(int id, String justificativa) =>
      _decidir(id, 'recusado', justificativa);

  Future<Pedido> _decidir(int id, String status, String? justificativa) async {
    final pedido = <String, Object?>{'status': status};
    if (justificativa != null) pedido['justificativa'] = justificativa.trim();
    final resposta = await _api.patch('pedidos/$id', body: {'pedido': pedido});
    final decidido = Pedido.talvezDoJson(resposta);
    if (decidido == null) {
      throw const ApiException(502, 'A API não devolveu o pedido decidido.');
    }
    return decidido;
  }

  List<Object?> _lista(Object? resposta, String chave) {
    if (resposta is! Map) return const [];
    final valor = resposta[chave];
    return valor is List ? valor : const [];
  }
}

String? _texto(Object? valor) {
  if (valor == null) return null;
  final texto = '$valor'.trim();
  return texto.isEmpty ? null : texto;
}
