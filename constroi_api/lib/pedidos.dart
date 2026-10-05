import 'dart:math';

typedef GeradorProtocolo = String Function();
typedef ItemPedido = ({int produtoId, num quantidade});

String gerarProtocolo() {
  final aleatorio = Random.secure();
  final codigo = List.generate(
    16,
    (_) => aleatorio.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join().toUpperCase();
  return 'PED-$codigo';
}

int? validarIdPedido(Object? valor) =>
    valor is int && valor > 0 && valor <= 2147483647 ? valor : null;

List<ItemPedido>? validarItensPedido(Object? valor) {
  if (valor is! List || valor.isEmpty) return null;

  final itens = <ItemPedido>[];
  final produtos = <int>{};
  for (final item in valor) {
    if (item is! Map<String, dynamic>) return null;
    final produtoId = validarIdPedido(item['produto_id']);
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

Map<String, dynamic> dadosDoPedido(Map<String, dynamic> linha) => {
  ...linha,
  'data': (linha['data'] as DateTime).toIso8601String(),
};

Map<String, dynamic> dadosDoItemPedido(Map<String, dynamic> linha) => {
  ...linha,
  'quantidade': '${linha['quantidade']}',
};
