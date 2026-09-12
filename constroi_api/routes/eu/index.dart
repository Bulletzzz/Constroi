import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final usuario = context.usuario;
  final banco = context.read<Pool<void>>();

  final encontrados = await banco.execute(
    Sql.named('''
      SELECT nome, email, tipo, ativo
      FROM usuario
      WHERE id = @id AND empresa_id = @empresa
      LIMIT 1
    '''),
    parameters: {'id': usuario.id, 'empresa': usuario.empresaId},
  );

  if (encontrados.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.unauthorized,
      body: {'erro': 'Usuario do token nao existe mais.'},
    );
  }

  final linha = encontrados.first.toColumnMap();
  return Response.json(
    body: {
      'id': usuario.id,
      'nome': linha['nome'],
      'email': linha['email'],
      'tipo': linha['tipo'],
      'ativo': linha['ativo'],
      'empresa_id': usuario.empresaId,
    },
  );
}
