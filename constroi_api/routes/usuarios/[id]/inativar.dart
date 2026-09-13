import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.patch) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final segmentos = context.request.uri.pathSegments;
  if (segmentos.length < 2) {
    return Response(
      statusCode: HttpStatus.badRequest,
      body: 'Id do usuario ausente.',
    );
  }

  final id = int.tryParse(segmentos[segmentos.length - 2]);
  if (id == null) {
    return Response(
      statusCode: HttpStatus.badRequest,
      body: 'Id do usuario invalido.',
    );
  }

  final usuarioAtual = context.usuario;
  if (usuarioAtual.id == id) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'erro': 'Nao e possivel inativar seu proprio usuario.'},
    );
  }

  final banco = context.read<Pool<void>>();
  final empresaId = usuarioAtual.empresaId;

  final atualizado = await banco.execute(
    Sql.named('''
      UPDATE usuario
      SET ativo = FALSE,
          atualizado_em = CURRENT_TIMESTAMP
      WHERE id = @id AND empresa_id = @empresa
      RETURNING id, nome, email, tipo, ativo, empresa_id
    '''),
    parameters: {'id': id, 'empresa': empresaId},
  );

  if (atualizado.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'erro': 'Usuario nao encontrado.'},
    );
  }

  final usuario = atualizado.first.toColumnMap();
  return Response.json(
    body: {
      'id': usuario['id'],
      'nome': usuario['nome'],
      'email': usuario['email'],
      'tipo': usuario['tipo'],
      'ativo': usuario['ativo'],
      'empresa_id': usuario['empresa_id'],
      'inativado': true,
    },
  );
}
