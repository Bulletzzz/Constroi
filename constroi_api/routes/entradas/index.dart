import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/entradas.dart';
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

  final dados = corpo['entrada'];
  if (dados is! Map<String, dynamic>) {
    return _erro(
      HttpStatus.badRequest,
      'Envie o objeto dentro da chave "entrada".',
    );
  }

  final obraId = validarIdEntrada(dados['obra_id']);
  final itens = validarItensEntrada(dados['itens']);
  if (obraId == null || itens == null) {
    return _erro(
      HttpStatus.badRequest,
      'Informe obra_id e itens com produto_id valido, sem repeticao, '
      'e quantidade positiva com ate duas casas decimais.',
    );
  }

  final justificativa = dados['justificativa'];
  if (justificativa is! String ||
      justificativa.trim().isEmpty ||
      justificativa.trim().length > 255) {
    return _erro(
      HttpStatus.badRequest,
      'Informe uma justificativa com ate 255 caracteres.',
    );
  }

  final usuario = context.usuario;
  final banco = context.read<Pool<void>>();

  try {
    return await banco.runTx((transacao) async {
      final obras = await transacao.execute(
        Sql.named('''
          SELECT id FROM obra
          WHERE id = @obra AND empresa_id = @empresa
        '''),
        parameters: {'obra': obraId, 'empresa': usuario.empresaId},
      );
      if (obras.isEmpty) {
        return _erro(
          HttpStatus.notFound,
          'Obra nao encontrada para esta empresa.',
        );
      }

      final produtos = await transacao.execute(
        Sql.named('''
          SELECT id FROM produto
          WHERE empresa_id = @empresa AND id = ANY(@produtos::int[])
        '''),
        parameters: {
          'empresa': usuario.empresaId,
          'produtos': itens.map((item) => item.produtoId).toList(),
        },
      );
      if (produtos.length != itens.length) {
        return _erro(
          HttpStatus.badRequest,
          'Todos os produtos devem existir e pertencer a sua empresa.',
        );
      }

      final entradas = await transacao.execute(
        Sql.named('''
          INSERT INTO entrada_estoque (usuario_id, obra_id, justificativa)
          VALUES (@usuario, @obra, @justificativa)
          RETURNING id, usuario_id, obra_id, xml_nota_fiscal, justificativa, data
        '''),
        parameters: {
          'usuario': usuario.id,
          'obra': obraId,
          'justificativa': justificativa.trim(),
        },
      );
      final entrada = entradas.first.toColumnMap();
      final itensCriados = <Map<String, dynamic>>[];

      for (final item in itens) {
        final resultado = await transacao.execute(
          Sql.named('''
            INSERT INTO item_entrada (entrada_id, produto_id, quantidade)
            VALUES (@entrada, @produto, @quantidade)
            RETURNING id, produto_id, quantidade
          '''),
          parameters: {
            'entrada': entrada['id'],
            'produto': item.produtoId,
            'quantidade': item.quantidade.toStringAsFixed(2),
          },
        );
        final linha = resultado.first.toColumnMap();
        itensCriados.add({
          ...linha,
          'quantidade': '${linha['quantidade']}',
        });

        await transacao.execute(
          Sql.named('''
            INSERT INTO estoque (obra_id, produto_id, quantidade)
            VALUES (@obra, @produto, @quantidade)
            ON CONFLICT (obra_id, produto_id)
            DO UPDATE SET quantidade = estoque.quantidade + EXCLUDED.quantidade
          '''),
          parameters: {
            'obra': obraId,
            'produto': item.produtoId,
            'quantidade': item.quantidade.toStringAsFixed(2),
          },
        );
      }

      await transacao.execute(
        Sql.named('''
          INSERT INTO log_sistema (usuario_id, acao)
          VALUES (@usuario, @acao)
        '''),
        parameters: {
          'usuario': usuario.id,
          'acao': 'Entrada manual de estoque ${entrada['id']} na obra $obraId.',
        },
      );

      return Response.json(
        statusCode: HttpStatus.created,
        body: {
          ...entrada,
          'data': (entrada['data'] as DateTime).toIso8601String(),
          'itens': itensCriados,
        },
      );
    });
  } on ServerException catch (erro) {
    if (erro.code != '22003') rethrow;
    return _erro(
      HttpStatus.conflict,
      'A entrada excede a quantidade maxima permitida no estoque.',
    );
  }
}

Response _erro(int status, String mensagem) =>
    Response.json(statusCode: status, body: {'erro': mensagem});
