import 'package:dart_frog/dart_frog.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

enum Nivel {
  pedreiro(1),
  engenheiro(2),
  master(3);

  const Nivel(this.altura);

  final int altura;

  bool alcanca(Nivel minimo) => altura >= minimo.altura;

  static Nivel? porNome(String? nome) {
    if (nome == null) return null;
    final procurado = nome.trim().toLowerCase();
    for (final nivel in Nivel.values) {
      if (nivel.name == procurado) return nivel;
    }
    return null;
  }
}

class UsuarioAutenticado {
  const UsuarioAutenticado({
    required this.id,
    required this.empresaId,
    required this.nivel,
  });

  final int id;
  final int empresaId;
  final Nivel nivel;
}

UsuarioAutenticado? autenticar(String? autorizacao, String segredo) {
  if (autorizacao == null) return null;

  final partes = autorizacao.split(' ');
  if (partes.length != 2 || partes.first.toLowerCase() != 'bearer') return null;

  try {
    final jwt = JWT.verify(partes[1], SecretKey(segredo));
    final dados = jwt.payload as Map<String, dynamic>;

    final id = int.tryParse(jwt.subject ?? '${dados['sub']}');
    final empresaId = dados['empresa_id'] as int?;
    final nivel = Nivel.porNome(dados['tipo'] as String?);

    if (id == null || empresaId == null || nivel == null) return null;
    return UsuarioAutenticado(id: id, empresaId: empresaId, nivel: nivel);
  } on JWTException {
    return null;
  }
}

extension UsuarioDoContexto on RequestContext {
  UsuarioAutenticado get usuario => read<UsuarioAutenticado?>()!;
}
