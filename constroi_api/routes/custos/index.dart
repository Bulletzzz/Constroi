import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/custos.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final filtros = context.request.uri.queryParameters;
  final obra = int.tryParse(filtros['obra_id'] ?? '');
  final limite = int.tryParse(filtros['limit'] ?? '20');
  final offset = int.tryParse(filtros['offset'] ?? '0');
  final periodo = filtros['periodo'] ?? 'total';
  if ((filtros.containsKey('obra_id') &&
          (obra == null || obra < 1 || obra > 2147483647)) ||
      limite == null ||
      limite < 1 ||
      limite > 100 ||
      offset == null ||
      offset < 0 ||
      offset > 2147483647 ||
      !{'total', 'mes', 'semana'}.contains(periodo)) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {
        'erro':
            'Informe obra_id positivo, periodo total/mes/semana, '
            'limit de 1 a 100 e offset maior ou igual a zero.',
      },
    );
  }
  try {
    final resultado = await context.read<Pool<void>>().execute(
      Sql.named(consultaCustos),
      parameters: {
        'empresa': context.usuario.empresaId,
        'obra': obra,
        'periodo': periodo,
        'limite': limite + 1,
        'offset': offset,
      },
    );
    final dados = Map<String, dynamic>.from(
      resultado.single.toColumnMap()['dados'] as Map,
    );
    if (dados.remove('obra_permitida') != true) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {
          'erro': 'Obra nao encontrada.',
        },
      );
    }
    final lancamentos = dados['lancamentos'] as List;
    dados['paginacao'] = {
      'limite': limite,
      'offset': offset,
      'tem_mais': lancamentos.length > limite,
    };
    dados['lancamentos'] = lancamentos.take(limite).toList();
    return Response.json(body: dados);
  } catch (erro) {
    // Nao registra a mensagem de conexao, que pode conter credenciais.
    // ignore: avoid_print
    print('Falha na consulta de custos (${erro.runtimeType}).');
    return Response.json(
      statusCode: HttpStatus.serviceUnavailable,
      body: {
        'erro': 'Nao foi possivel consultar os custos. Tente novamente.',
      },
    );
  }
}
