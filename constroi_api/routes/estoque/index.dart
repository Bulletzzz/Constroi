import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/pedidos.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final filtros = context.request.uri.queryParameters;
  final obraId = validarIdPedido(int.tryParse(filtros['obra_id'] ?? ''));
  final busca = (filtros['busca'] ?? '').trim();
  final baixo = filtros['baixo'] ?? 'false';
  final limite = int.tryParse(filtros['limit'] ?? '50');
  final offset = int.tryParse(filtros['offset'] ?? '0');
  if (obraId == null ||
      busca.length > 150 ||
      (baixo != 'true' && baixo != 'false') ||
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
            'Informe obra_id positivo, busca de ate 150 caracteres, '
            'baixo true/false, limit de 1 a 200 e offset de 0 a 10000.',
      },
    );
  }

  final banco = context.read<Pool<void>>();
  final usuario = context.usuario;
  final obra = await banco.execute(
    Sql.named('''
      SELECT o.id FROM obra o
      WHERE o.id = @obra AND o.empresa_id = @empresa
        AND (
          @todas OR EXISTS (
            SELECT 1 FROM usuario_obra uo
            WHERE uo.obra_id = o.id AND uo.usuario_id = @usuario
              AND uo.data_fim IS NULL
          )
        )
      LIMIT 1
    '''),
    parameters: {
      'obra': obraId,
      'empresa': usuario.empresaId,
      'usuario': usuario.id,
      'todas': usuario.nivel.alcanca(Nivel.engenheiro),
    },
  );
  if (obra.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'erro': 'Obra nao encontrada.'},
    );
  }

  final linhas = await banco.execute(
    Sql.named('''
      SELECT e.id, e.obra_id, e.produto_id, p.nome, p.unidade, p.sku,
             e.quantidade::text, p.estoque_minimo::text,
             (e.quantidade <= p.estoque_minimo) AS baixo
      FROM estoque e
      JOIN obra o ON o.id = e.obra_id AND o.empresa_id = @empresa
      JOIN produto p ON p.id = e.produto_id AND p.empresa_id = @empresa
      WHERE e.obra_id = @obra
        AND (STRPOS(LOWER(p.nome), LOWER(@busca)) > 0
             OR STRPOS(LOWER(COALESCE(p.sku, '')), LOWER(@busca)) > 0)
        AND (NOT @baixo OR e.quantidade <= p.estoque_minimo)
      ORDER BY p.nome, p.id
      LIMIT @limite OFFSET @offset
    '''),
    parameters: {
      'empresa': usuario.empresaId,
      'obra': obraId,
      'busca': busca,
      'baixo': baixo == 'true',
      'limite': limite,
      'offset': offset,
    },
  );

  return Response.json(
    body: {'estoque': linhas.map((linha) => linha.toColumnMap()).toList()},
  );
}
