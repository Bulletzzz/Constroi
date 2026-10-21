import 'package:constroi_api/anexo_nfe.dart';
import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/nfe.dart';
import 'package:constroi_api/pedidos.dart';
import 'package:constroi_api/upload_nfe.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.patch) {
    return Response(statusCode: 405);
  }
  try {
    final entradaId = validarIdPedido(int.tryParse(id));
    if (entradaId == null) throw const FalhaNfe(400, 'Id da entrada invalido.');
    final upload = await receberNfe(context.request);
    final entrada = await anexarNfe(
      context.read<Pool<void>>(),
      usuario: context.usuario,
      entradaId: entradaId,
      nota: upload.nota,
    );
    return Response.json(body: entrada);
  } on FalhaNfe catch (erro) {
    return erroNfe(erro);
  }
}
