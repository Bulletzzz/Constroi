import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/pedidos.dart';
import 'package:constroi_api/permissao.dart';
import 'package:dart_frog/dart_frog.dart';

Handler middleware(Handler handler) => (context) {
  final nivel = context.request.method == HttpMethod.patch
      ? Nivel.engenheiro
      : Nivel.pedreiro;
  return handler
      .use(provider<GeradorProtocolo>((_) => gerarProtocolo))
      .use(exigirNivel(nivel))(context);
};
