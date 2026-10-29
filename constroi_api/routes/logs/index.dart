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
  final inicio = filtros.containsKey('data_inicio')
      ? validarDataLog(filtros['data_inicio']!)
      : null;
  final fim = filtros.containsKey('data_fim')
      ? validarDataLog(filtros['data_fim']!)
      : null;
  final limite = int.tryParse(filtros['limit'] ?? '50');
  final offset = int.tryParse(filtros['offset'] ?? '0');
  if ((filtros.containsKey('usuario_id') && usuarioId == null) ||
      (filtros.containsKey('data_inicio') && inicio == null) ||
      (filtros.containsKey('data_fim') && fim == null) ||
      (inicio != null && fim != null && !inicio.isBefore(fim)) ||
      limite == null ||
      limite < 1 ||
      limite > 200 ||
      offset == null ||
      offset < 0 ||
      offset > 10000) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {
        'erro':
            'Informe usuario_id positivo, datas ISO 8601 com fuso ou '
            'AAAA-MM-DD (UTC), data_inicio anterior a data_fim, '
            'limit de 1 a 200 e offset de 0 a 10000.',
      },
    );
  }
  final linhas = await context.read<Pool<void>>().execute(
    Sql.named('''
      SELECT l.id, l.usuario_id, u.nome AS usuario_nome, l.acao, l.data
      FROM log_sistema l
      JOIN usuario u ON u.id = l.usuario_id
      WHERE u.empresa_id = @empresa
        AND (CAST(@usuario AS integer) IS NULL OR l.usuario_id = @usuario)
        AND (CAST(@inicio AS timestamptz) IS NULL OR l.data >= @inicio)
        AND (CAST(@fim AS timestamptz) IS NULL OR l.data < @fim)
      ORDER BY l.data DESC, l.id DESC
      LIMIT @limite OFFSET @offset
    '''),
    parameters: {
      'empresa': context.usuario.empresaId,
      'usuario': usuarioId,
      'inicio': inicio,
      'fim': fim,
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
