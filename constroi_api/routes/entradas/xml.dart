import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/entrada_nfe.dart';
import 'package:constroi_api/nfe.dart';
import 'package:constroi_api/pedidos.dart';
import 'package:constroi_api/upload_nfe.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }
  try {
    final upload = await receberNfe(context.request);
    final obra = validarIdPedido(int.tryParse(upload.campos['obra_id'] ?? ''));
    if (obra == null) {
      throw const FalhaNfe(400, 'Informe obra_id inteiro positivo.');
    }
    final entrada = await importarNfe(
      context.read<Pool<void>>(),
      usuario: context.usuario,
      obraId: obra,
      nota: upload.nota,
    );
    return Response.json(statusCode: 201, body: entrada);
  } on FalhaNfe catch (erro) {
    return erroNfe(erro);
  }
}
