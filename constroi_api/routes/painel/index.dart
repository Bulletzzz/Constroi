import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/painel.dart';
import 'package:constroi_api/pedidos.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final filtros = context.request.uri.queryParameters;
  final obra = filtros.containsKey('obra_id')
      ? validarIdPedido(int.tryParse(filtros['obra_id']!))
      : null;
  final limite = int.tryParse(filtros['limit'] ?? '5');
  final offset = int.tryParse(filtros['offset'] ?? '0');
  if ((filtros.containsKey('obra_id') && obra == null) ||
      limite == null ||
      limite < 1 ||
      limite > 50 ||
      offset == null ||
      offset < 0 ||
      offset > 10000) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {
        'erro':
            'Informe obra_id positivo, limit de 1 a 50 e offset de 0 a 10000.',
      },
    );
  }
  final usuario = context.usuario;
  try {
    final resultado = await context.read<Pool<void>>().execute(
      Sql.named(consultaPainel),
      parameters: {
        'empresa': usuario.empresaId,
        'usuario': usuario.id,
        'gestor': usuario.nivel.alcanca(Nivel.engenheiro),
        'obra': obra,
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
    final movimentos = dados['movimentacoes'] as List;
    if (!usuario.nivel.alcanca(Nivel.engenheiro)) {
      (dados['indicadores'] as Map)
        ..remove('valor_estimado')
        ..remove('itens_sem_preco');
    }
    dados['paginacao'] = {
      'limite': limite,
      'offset': offset,
      'tem_mais': movimentos.length > limite,
    };
    dados['movimentacoes'] = movimentos.take(limite).toList();
    return Response.json(body: dados);
  } catch (erro, pilha) {
    // FormatException de conexao pode conter a DATABASE_URL com a senha.
    // Preserva o diagnostico e a pilha no servidor, omitindo a URL completa.
    final diagnostico = '$erro\n$pilha'.replaceAll(
      RegExp(r'postgres(?:ql)?://[^\r\n]*', caseSensitive: false),
      '[conexao PostgreSQL omitida]',
    );
    // ignore: avoid_print
    print('Falha no painel (${erro.runtimeType}): $diagnostico');
    return Response.json(
      statusCode: HttpStatus.serviceUnavailable,
      body: {
        'erro': 'Nao foi possivel consultar o painel. Tente novamente.',
      },
    );
  }
}
