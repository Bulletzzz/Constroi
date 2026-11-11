import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/despesas.dart';
import 'package:constroi_api/logs.dart';
import 'package:constroi_api/pedidos.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final Map<String, dynamic> corpo;
  try {
    corpo = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return _erro(HttpStatus.badRequest, 'Envie um JSON valido.');
  }

  final dados = corpo['despesa'];
  if (dados is! Map<String, dynamic>) {
    return _erro(
      HttpStatus.badRequest,
      'Envie o objeto dentro da chave "despesa".',
    );
  }

  final obraId = validarIdPedido(dados['obra_id']);
  final categoriaId = validarIdPedido(dados['categoria_custo_id']);
  final descricao = validarDescricaoDespesa(dados['descricao']);
  final valor = validarValorDespesa(dados['valor']);
  if (obraId == null ||
      categoriaId == null ||
      descricao == null ||
      valor == null) {
    return _erro(
      HttpStatus.badRequest,
      'Informe obra_id e categoria_custo_id positivos, descricao de 1 a 255 '
      'caracteres e valor maior que zero com ate duas casas decimais.',
    );
  }

  final banco = context.read<Pool<void>>();
  final usuario = context.usuario;
  final gravada = await executarEscritaComLog(
    banco,
    Sql.named(insercaoDeDespesa),
    parameters: {
      'empresa': usuario.empresaId,
      'obra': obraId,
      'usuario': usuario.id,
      'categoria': categoriaId,
      'descricao': descricao,
      'valor': valor,
    },
    usuarioId: usuario.id,
    evento: 'CRIACAO_DESPESA',
    recurso: 'despesa',
  );

  if (gravada.isEmpty) {
    final categorias = await banco.execute(
      Sql.named('SELECT id FROM categoria_custo WHERE id = @categoria'),
      parameters: {'categoria': categoriaId},
    );
    return categorias.isEmpty
        ? _erro(HttpStatus.badRequest, 'Categoria de custo nao encontrada.')
        : _erro(HttpStatus.notFound, 'Obra nao encontrada para esta empresa.');
  }

  final despesa = gravada.first.toColumnMap();
  return Response.json(
    statusCode: HttpStatus.created,
    body: {
      'id': despesa['id'],
      'obra_id': despesa['obra_id'],
      'categoria_custo_id': despesa['categoria_custo_id'],
      'descricao': despesa['descricao'],
      'valor': despesa['valor'],
      'data_lancamento': (despesa['data_lancamento'] as DateTime)
          .toIso8601String(),
    },
  );
}

Response _erro(int status, String mensagem) =>
    Response.json(statusCode: status, body: {'erro': mensagem});
