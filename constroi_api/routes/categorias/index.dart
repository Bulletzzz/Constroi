import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final linhas = await context.read<Pool<void>>().execute(
    'SELECT id, nome FROM categoria_custo ORDER BY nome, id',
  );

  return Response.json(
    body: {
      'categorias': linhas
          .map((linha) => {'id': linha[0], 'nome': linha[1]})
          .toList(),
    },
  );
}
