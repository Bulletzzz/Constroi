import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/permissao.dart';
import 'package:dart_frog/dart_frog.dart';

Handler middleware(Handler handler) => (context) {
  final somenteLeitura = context.request.method == HttpMethod.get;
  final nivel = somenteLeitura ? Nivel.pedreiro : Nivel.engenheiro;
  return handler.use(exigirNivel(nivel))(context);
};
