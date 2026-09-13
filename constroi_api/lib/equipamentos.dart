const Set<String> _statusEquipamento = {
  'disponivel',
  'em_uso',
  'manutencao',
  'quebrado',
  'inativo',
};

String? validarNomeEquipamento(String? valor) {
  final nome = valor?.trim();
  if (nome == null || nome.isEmpty || nome.length > 150) {
    return null;
  }
  return nome;
}

String? validarPatrimonio(String? valor) {
  final patrimonio = valor?.trim();
  if (patrimonio == null || patrimonio.isEmpty || patrimonio.length > 50) {
    return null;
  }
  return patrimonio;
}

String? validarStatusEquipamento(String? valor) {
  final status = valor?.trim().toLowerCase();
  if (status == null || !_statusEquipamento.contains(status)) {
    return null;
  }
  return status;
}
