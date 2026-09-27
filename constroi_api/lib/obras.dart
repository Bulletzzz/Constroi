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
