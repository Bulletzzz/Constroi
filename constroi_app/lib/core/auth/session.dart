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

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as int,
    empresaId: json['empresa_id'] as int,
    nome: json['nome'] as String,
    email: json['email'] as String,
    tipo: json['tipo'] as String,
  );
}

class AppSession {
  const AppSession({required this.accessToken, this.user});

  final String accessToken;
  final AppUser? user;
}
