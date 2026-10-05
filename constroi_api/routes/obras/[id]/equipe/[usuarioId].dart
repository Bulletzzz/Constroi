import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(
  RequestContext context,
  String idDaRota,
  String usuarioIdDaRota,
) async {
  if (context.request.method != HttpMethod.delete) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final obraId = int.tryParse(idDaRota);
  final usuarioId = int.tryParse(usuarioIdDaRota);
  if (obraId == null || obraId < 1) {
    return _erro(HttpStatus.badRequest, 'Id da obra invalido.');
  }
  if (usuarioId == null || usuarioId < 1) {
    return _erro(HttpStatus.badRequest, 'Id do usuario invalido.');
  }

  final encerrado = await context.read<Pool<void>>().execute(
    Sql.named('''
      UPDATE usuario_obra
      SET data_fim = CURRENT_TIMESTAMP
      WHERE obra_id = @obra
        AND usuario_id = @usuario
        AND empresa_id = @empresa
        AND data_fim IS NULL
      RETURNING id, empresa_id, usuario_id, obra_id, data_inicio, data_fim
    '''),
    parameters: {
      'obra': obraId,
      'usuario': usuarioId,
      'empresa': context.usuario.empresaId,
    },
  );

  if (encerrado.isEmpty) {
    return _erro(HttpStatus.notFound, 'Vinculo ativo nao encontrado.');
  }

  final vinculo = encerrado.first.toColumnMap();
  final dataInicio = vinculo['data_inicio'] as DateTime?;
  final dataFim = vinculo['data_fim'] as DateTime?;
  return Response.json(
    body: {
      'id': vinculo['id'],
      'empresa_id': vinculo['empresa_id'],
      'usuario_id': vinculo['usuario_id'],
      'obra_id': vinculo['obra_id'],
      'data_inicio': dataInicio?.toIso8601String(),
      'data_fim': dataFim?.toIso8601String(),
    },
  );
}

Response _erro(int status, String mensagem) =>
    Response.json(statusCode: status, body: {'erro': mensagem});
