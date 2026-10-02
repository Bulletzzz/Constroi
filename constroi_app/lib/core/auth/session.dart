class AppUser {
  const AppUser({
    required this.id,
    required this.empresaId,
    required this.nome,
    required this.email,
    required this.tipo,
  });

  final int id;
  final int empresaId;
  final String nome;
  final String email;
  final String tipo;

  static AppUser? talvezDoJson(Object? dados) {
    if (dados is! Map) return null;
    final id = _inteiro(dados['id']);
    final empresa = _inteiro(dados['empresa_id']);
    if (id == null || empresa == null) return null;
    return AppUser(
      id: id,
      empresaId: empresa,
      nome: _texto(dados['nome']),
      email: _texto(dados['email']),
      tipo: _texto(dados['tipo']),
    );
  }

  static int? _inteiro(Object? valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    if (valor is String) return int.tryParse(valor);
    return null;
  }

  static String _texto(Object? valor) => valor is String ? valor : '';
}

class AppSession {
  const AppSession({required this.accessToken, this.user});

  final String accessToken;
  final AppUser? user;
}
