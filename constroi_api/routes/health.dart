import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  try {
    final banco = context.read<Pool<void>>();
    final resultado = await banco.execute('SELECT 1');
    return Response.json(
      body: {'status': 'ok', 'banco': resultado.first.first},
    );
  } catch (erro) {
    return Response.json(
      statusCode: HttpStatus.serviceUnavailable,
      body: {'status': 'erro', 'detalhe': '$erro'},
    );
  }
}
