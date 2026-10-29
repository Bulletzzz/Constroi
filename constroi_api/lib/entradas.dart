typedef ItemEntrada = ({int produtoId, num quantidade});

int? validarIdEntrada(Object? valor) =>
    valor is int && valor > 0 && valor <= 2147483647 ? valor : null;

List<ItemEntrada>? validarItensEntrada(Object? valor) {
  if (valor is! List || valor.isEmpty) return null;

  final itens = <ItemEntrada>[];
  final produtos = <int>{};
  for (final item in valor) {
    if (item is! Map<String, dynamic>) return null;
    final produtoId = validarIdEntrada(item['produto_id']);
    final quantidade = item['quantidade'];
    if (produtoId == null ||
        !produtos.add(produtoId) ||
        quantidade is! num ||
        !quantidade.isFinite ||
        quantidade <= 0 ||
        quantidade > 9999999999.99 ||
        num.parse(quantidade.toStringAsFixed(2)) != quantidade) {
      return null;
    }
    itens.add((produtoId: produtoId, quantidade: quantidade));
  }
  return itens;
}
