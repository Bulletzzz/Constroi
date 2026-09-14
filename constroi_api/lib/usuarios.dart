const Set<String> _tiposUsuario = {'pedreiro', 'engenheiro', 'master'};

String? validarTipoUsuario(String? valor) {
  final tipo = valor?.trim().toLowerCase();
  if (tipo == null || tipo.isEmpty || !_tiposUsuario.contains(tipo)) {
    return null;
  }
  return tipo;
}

bool exclusaoFisicaPermitida(String metodo) =>
    metodo.trim().toUpperCase() != 'DELETE';
