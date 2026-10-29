import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/logs.dart';
import 'package:constroi_api/pedidos.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final filtros = context.request.uri.queryParameters;
  final usuarioId = filtros.containsKey('usuario_id')
      ? validarIdPedido(int.tryParse(filtros['usuario_id']!))
      : null;
  final inicioTexto = filtros.containsKey('data_inicio')
      ? validarDataLog(filtros['data_inicio']!)
      : null;
  final fimTexto = filtros.containsKey('data_fim')
      ? validarDataLog(filtros['data_fim']!)
      : null;
  final limite = int.tryParse(filtros['limit'] ?? '50');
  final offset = int.tryParse(filtros['offset'] ?? '0');
  if ((filtros.containsKey('usuario_id') && usuarioId == null) ||
      (filtros.containsKey('data_inicio') && inicioTexto == null) ||
      (filtros.containsKey('data_fim') && fimTexto == null) ||
      limite == null ||
      limite < 1 ||
      limite > 200 ||
      offset == null ||
      offset < 0 ||
      offset > 10000) {
    return _filtrosInvalidos();
  }
  final banco = context.read<Pool<void>>();
  DateTime? inicio;
  DateTime? fim;
  if (inicioTexto != null || fimTexto != null) {
    // Usa as regras IANA do banco, incluindo o horario de verao historico.
    final periodo = await banco.execute(
      Sql.named('''
        SELECT CASE WHEN length(@inicio::text) = 10
          THEN @inicio::date::timestamp AT TIME ZONE 'America/Sao_Paulo'
          ELSE @inicio::timestamptz END AS inicio,
        CASE WHEN length(@fim::text) = 10
          THEN @fim::date::timestamp AT TIME ZONE 'America/Sao_Paulo'
          ELSE @fim::timestamptz END AS fim
      '''),
      parameters: {'inicio': inicioTexto, 'fim': fimTexto},
    );
    inicio = periodo.single[0] as DateTime?;
    fim = periodo.single[1] as DateTime?;
    if (inicio != null && fim != null && !inicio.isBefore(fim)) {
      return _filtrosInvalidos();
    }
  }
  final linhas = await banco.execute(
    Sql.named(
      consultaLogs(
        porUsuario: usuarioId != null,
        comInicio: inicio != null,
        comFim: fim != null,
      ),
    ),
    parameters: {
      'empresa': context.usuario.empresaId,
      if (usuarioId != null) 'usuario': usuarioId,
      if (inicio != null) 'inicio': inicio,
      if (fim != null) 'fim': fim,
      'limite': limite + 1,
      'offset': offset,
    },
  );
  return Response.json(
    body: {
      'logs': linhas.take(limite).map((linha) {
        final dados = linha.toColumnMap();
        return {
          ...dados,
          'data': (dados['data']! as DateTime).toUtc().toIso8601String(),
        };
      }).toList(),
      'paginacao': {
        'limit': limite,
        'offset': offset,
        'tem_mais': linhas.length > limite,
      },
    },
  );
}

Response _filtrosInvalidos() => Response.json(
  statusCode: HttpStatus.badRequest,
  body: {
    'erro':
        'Informe usuario_id positivo, datas ISO 8601 com fuso ou '
        'AAAA-MM-DD (America/Sao_Paulo), data_inicio anterior a data_fim, '
        'limit de 1 a 200 e offset de 0 a 10000.',
  },
);
