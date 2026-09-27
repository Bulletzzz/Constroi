typedef OrcamentoLido = ({bool valido, num? valor});

String? validarNomeObra(Object? valor) {
  if (valor is! String) return null;
  final nome = valor.trim();
  if (nome.isEmpty || nome.length > 150) return null;
  return nome;
}

String? validarEnderecoObra(Object? valor) {
  if (valor is! String) return null;
  final endereco = valor.trim();
  if (endereco.isEmpty || endereco.length > 255) return null;
  return endereco;
}

String? validarStatusObra(Object? valor) {
  if (valor is! String) return null;
  final status = valor.trim().toLowerCase();
  const statusValidos = {'planejamento', 'ativa', 'pausada', 'concluida'};
  return statusValidos.contains(status) ? status : null;
}

OrcamentoLido validarOrcamentoObra(Object? valor) {
  if (valor == null) return (valido: true, valor: null);

  if (valor is num) {
    if (valor < 0 || !valor.isFinite) return (valido: false, valor: null);
    return (valido: true, valor: valor);
  }

  if (valor is String) {
    final limpo = valor.trim().replaceAll(',', '.');
    if (limpo.isEmpty) return (valido: true, valor: null);
    final numero = num.tryParse(limpo);
    if (numero == null || numero < 0 || !numero.isFinite) {
      return (valido: false, valor: null);
    }
    return (valido: true, valor: numero);
  }

  return (valido: false, valor: null);
}

Map<String, dynamic> dadosDaObra(Map<String, dynamic> linha) {
  final orcamento = linha['orcamento_total'];
  return {
    'id': linha['id'],
    'nome': linha['nome'],
    'endereco': linha['endereco'],
    'status': linha['status'],
    'orcamento_total': orcamento == null ? null : '$orcamento',
    'empresa_id': linha['empresa_id'],
  };
}
