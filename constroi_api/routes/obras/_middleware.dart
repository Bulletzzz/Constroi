import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/permissao.dart';
import 'package:dart_frog/dart_frog.dart';

Handler middleware(Handler handler) {
  return (context) {
    final nivel = context.request.method == HttpMethod.get
        ? Nivel.pedreiro
        : Nivel.engenheiro;
    return exigirNivel(nivel)(handler)(context);
  };
}
