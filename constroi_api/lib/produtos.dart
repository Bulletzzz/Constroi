String? validarNomeProduto(Object? valor) {
  if (valor is! String) return null;
  final nome = valor.trim();
  if (nome.isEmpty || nome.length > 150) {
    return null;
  }
  return nome;
}

String? validarUnidadeProduto(Object? valor) {
  if (valor is! String) return null;
  final unidade = valor.trim().toLowerCase();
  if (unidade.isEmpty) {
    return null;
  }

  final unidadesValidas = {
    'un',
    'kg',
    'g',
    'l',
    'ml',
    'm',
    'm2',
    'm3',
    'cx',
    'pct',
    'pc',
    'lt',
    'ton',
    't',
    'saco',
    'sacos',
    'rolo',
    'rolos',
    'barra',
    'barras',
  };

  return unidadesValidas.contains(unidade) ? unidade : null;
}

({bool valido, String? valor}) validarSkuProduto(Object? valor) {
  if (valor == null) return (valido: true, valor: null);
  if (valor is! String) return (valido: false, valor: null);
  final sku = valor.trim();
  if (sku.length > 50) return (valido: false, valor: null);
  return (valido: true, valor: sku.isEmpty ? null : sku);
}

String? validarEstoqueMinimo(Object? valor) {
  if (valor is! num && valor is! String) return null;
  final texto = '$valor'.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(texto)) return null;
  final numero = num.tryParse(texto);
  if (numero == null || !numero.isFinite || numero > 9999999999.99) return null;
  return texto;
}

Map<String, dynamic> dadosDoProduto(Map<String, dynamic> produto) => {
  ...produto,
  'estoque_minimo': '${produto['estoque_minimo']}',
  if (produto.containsKey('criado_em'))
    'criado_em': (produto['criado_em'] as DateTime?)?.toIso8601String(),
  if (produto.containsKey('atualizado_em'))
    'atualizado_em': (produto['atualizado_em'] as DateTime?)?.toIso8601String(),
};
