String? validarValorDespesa(Object? valor) {
  final texto = valor is String ? valor.trim() : '$valor';
  if (!RegExp(r'^\d{1,12}(\.\d{1,2})?$').hasMatch(texto)) return null;
  final partes = texto.split('.');
  final centavos = (partes.length == 1 ? '' : partes[1]).padRight(2, '0');
  if (BigInt.parse(partes.first) == BigInt.zero &&
      BigInt.parse(centavos) == BigInt.zero) {
    return null;
  }
  return '${partes.first}.$centavos';
}

String? validarDescricaoDespesa(Object? valor) {
  if (valor is! String) return null;
  final descricao = valor.trim();
  if (descricao.isEmpty || descricao.length > 255) return null;
  return descricao;
}

const insercaoDeDespesa = '''
  INSERT INTO despesa_obra (empresa_id, obra_id, registrado_por_usuario_id,
    categoria_custo_id, descricao, valor)
  SELECT @empresa, @obra, @usuario, @categoria, @descricao, @valor::numeric
  WHERE EXISTS (
      SELECT 1 FROM obra WHERE id = @obra AND empresa_id = @empresa
    ) AND EXISTS (
      SELECT 1 FROM categoria_custo WHERE id = @categoria
    )
  RETURNING id, obra_id, categoria_custo_id, descricao, valor::text,
    data_lancamento
''';
