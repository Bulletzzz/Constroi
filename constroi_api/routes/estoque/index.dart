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
  final obraId = filtros.containsKey('obra_id')
      ? validarIdPedido(int.tryParse(filtros['obra_id']!))
      : null;
  final categoriaId = filtros.containsKey('categoria_id')
      ? validarIdPedido(int.tryParse(filtros['categoria_id']!))
      : null;
  final busca = (filtros['busca'] ?? '').trim();
  final baixo = filtros['baixo'] ?? 'false';
  final limite = int.tryParse(filtros['limit'] ?? '50');
  final offset = int.tryParse(filtros['offset'] ?? '0');
  if ((filtros.containsKey('obra_id') && obraId == null) ||
      (filtros.containsKey('categoria_id') && categoriaId == null) ||
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
            'Informe obra_id e categoria_id positivos quando enviados, '
            'busca de ate 150 caracteres, '
            'baixo true/false, limit de 1 a 200 e offset de 0 a 10000.',
      },
    );
  }

  final banco = context.read<Pool<void>>();
  final usuario = context.usuario;
  if (obraId != null) {
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
  }

  final linhas = await banco.execute(
    Sql.named('''
      SELECT e.id, e.obra_id, e.produto_id, p.nome AS produto_nome,
             p.unidade, p.sku, p.categoria_custo_id, c.nome AS categoria_nome,
             e.quantidade::text, p.estoque_minimo::text,
             (e.quantidade <= p.estoque_minimo) AS baixo
      FROM estoque e
      JOIN obra o ON o.id = e.obra_id AND o.empresa_id = @empresa
      JOIN produto p ON p.id = e.produto_id AND p.empresa_id = @empresa
      LEFT JOIN categoria_custo c ON c.id = p.categoria_custo_id
      WHERE (CAST(@obra AS INTEGER) IS NULL OR e.obra_id = @obra)
        AND (CAST(@categoria AS INTEGER) IS NULL OR p.categoria_custo_id = @categoria)
        AND (
          @todas OR EXISTS (
            SELECT 1 FROM usuario_obra uo
            WHERE uo.obra_id = o.id AND uo.usuario_id = @usuario
              AND uo.data_fim IS NULL
          )
        )
        AND (STRPOS(LOWER(p.nome), LOWER(@busca)) > 0
             OR STRPOS(LOWER(COALESCE(p.sku, '')), LOWER(@busca)) > 0)
        AND (NOT @baixo OR e.quantidade <= p.estoque_minimo)
      ORDER BY p.nome, p.id, e.obra_id, e.id
      LIMIT @limite OFFSET @offset
    '''),
    parameters: {
      'empresa': usuario.empresaId,
      'obra': obraId,
      'categoria': categoriaId,
      'usuario': usuario.id,
      'todas': usuario.nivel.alcanca(Nivel.engenheiro),
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
