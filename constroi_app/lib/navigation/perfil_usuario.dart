import 'dart:convert';

import '../core/auth/session.dart';

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

  /// Decodifica o JWT só como fallback quando a sessão não tem usuário.
  /// A assinatura e a autorização real continuam sendo validadas pela API.
  static PerfilUsuario? ler(String? token) {
    if (token == null || token.trim().isEmpty) return null;

    final partes = token.split('.');
    if (partes.length != 3) return null;

    try {
      final corpo = utf8.decode(
        base64Url.decode(base64Url.normalize(partes[1])),
      );
      final dados = jsonDecode(corpo);
      if (dados is! Map<String, dynamic>) return null;
      return PerfilUsuario.porNome(dados['tipo']);
    } on FormatException {
      return null;
    }
  }
}

class PerfilDaSessao {
  const PerfilDaSessao._();

  /// O usuário atualizado por /eu (ou recebido no login) prevalece sobre o JWT.
  /// O token só fornece o perfil quando a sessão não conseguiu ler um usuário.
  static PerfilUsuario? ler(AppSession? sessao) {
    final usuario = sessao?.user;
    if (usuario != null) return PerfilUsuario.porNome(usuario.tipo);
    return PerfilDoToken.ler(sessao?.accessToken);
  }
}
