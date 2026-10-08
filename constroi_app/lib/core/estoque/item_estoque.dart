class ItemEstoque {
  const ItemEstoque({
    required this.id,
    required this.obraId,
    required this.produtoId,
    required this.produtoNome,
    required this.unidade,
    required this.quantidade,
    this.categoriaId,
    this.categoriaNome,
  });

  final int id;
  final int obraId;
  final int produtoId;
  final String produtoNome;
  final String unidade;
  final String quantidade;
  final int? categoriaId;
  final String? categoriaNome;

  static ItemEstoque? talvezDoJson(Object? dados) {
    if (dados is! Map) return null;
    final id = _inteiro(dados['id']);
    final obra = _inteiro(dados['obra_id']);
    final produto = _inteiro(dados['produto_id']);
    if (id == null || obra == null || produto == null) return null;
    return ItemEstoque(
      id: id,
      obraId: obra,
      produtoId: produto,
      produtoNome: _texto(dados['produto_nome']),
      unidade: _texto(dados['unidade']),
      quantidade: _texto(dados['quantidade']),
      categoriaId: _inteiro(dados['categoria_custo_id']),
      categoriaNome: dados['categoria_nome'] is String
          ? dados['categoria_nome'] as String
          : null,
    );
  }

  static int? _inteiro(Object? valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    if (valor is String) return int.tryParse(valor);
    return null;
  }

  static String _texto(Object? valor) {
    if (valor is String) return valor;
    if (valor is num) return '$valor';
    return '';
  }
}
