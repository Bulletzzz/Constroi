String? validarNomeProduto(String? valor) {
  final nome = valor?.trim();
  if (nome == null || nome.isEmpty || nome.length > 150) {
    return null;
  }
  return nome;
}

String? validarUnidadeProduto(String? valor) {
  final unidade = valor?.trim().toLowerCase();
  if (unidade == null || unidade.isEmpty) {
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
