import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
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
  } catch (erro, pilha) {
    // FormatException de conexao pode conter a DATABASE_URL com a senha.
    // Preserva o diagnostico e a pilha no servidor, omitindo a URL completa.
    final diagnostico = '$erro\n$pilha'.replaceAll(
      RegExp(r'postgres(?:ql)?://[^\r\n]*', caseSensitive: false),
      '[conexao PostgreSQL omitida]',
    );
    // ignore: avoid_print
    print('Falha nas categorias (${erro.runtimeType}): $diagnostico');
    return Response.json(
      statusCode: HttpStatus.serviceUnavailable,
      body: {
        'erro': 'Nao foi possivel consultar as categorias. Tente novamente.',
      },
    );
  }
}
