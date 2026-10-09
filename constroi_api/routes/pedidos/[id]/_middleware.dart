import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/permissao.dart';
import 'package:dart_frog/dart_frog.dart';

// Consultar o pedido continua aberto ao pedreiro dono dele; o que muda o
// pedido, como aprovar e dar baixa no estoque, e decisao do engenheiro.
Handler middleware(Handler handler) {
  return (context) {
    final nivel = context.request.method == HttpMethod.get
        ? Nivel.pedreiro
        : Nivel.engenheiro;
    return exigirNivel(nivel)(handler)(context);
  };
}
