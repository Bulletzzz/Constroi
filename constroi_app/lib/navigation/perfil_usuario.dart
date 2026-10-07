import 'dart:convert';

enum PerfilUsuario {
  pedreiro(1),
  engenheiro(2),
  master(3);

  const PerfilUsuario(this.nivel);
  final int nivel;
  bool possuiNivel(PerfilUsuario minimo) => nivel >= minimo.nivel;

  static PerfilUsuario? porNome(Object? valor) {
    if (valor is! String) return null;
    final nome = valor.trim().toLowerCase();
    for (final perfil in values) {
      if (perfil.name == nome) return perfil;
    }
    return null;
  }
}

class PerfilDoToken {
  const PerfilDoToken._();
  // O JWT decide a interface. A API valida a assinatura e autoriza os dados.
  static PerfilUsuario? ler(String? token) {
    if (token == null) return null;
    final partes = token.split('.');
    if (partes.length != 3) return null;
    try {
      final dados = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(partes[1]))),
      );
      return dados is Map<String, dynamic>
          ? PerfilUsuario.porNome(dados['tipo'])
          : null;
    } on FormatException {
      return null;
    }
  }
}
