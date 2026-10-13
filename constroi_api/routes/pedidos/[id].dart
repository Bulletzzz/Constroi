import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/pedidos.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context, String idDaRota) async {
  final metodo = context.request.method;
  if (metodo != HttpMethod.get && metodo != HttpMethod.patch) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final id = validarIdPedido(int.tryParse(idDaRota));
  if (id == null) {
    return _erro(HttpStatus.badRequest, 'Id do pedido invalido.');
  }

  if (metodo == HttpMethod.patch) return _decidir(context, id);
  return _buscar(context, id);
}

Future<Response> _buscar(RequestContext context, int id) async {
  final usuario = context.usuario;
  final banco = context.read<Pool<void>>();
  final pedidos = await banco.execute(
    Sql.named('''
      SELECT p.id, p.usuario_id, p.obra_id, p.protocolo,
             p.status, p.justificativa, p.data
      FROM pedido p
      JOIN obra o ON o.id = p.obra_id
      JOIN usuario u ON u.id = p.usuario_id
      WHERE p.id = @id AND o.empresa_id = @empresa
        AND u.empresa_id = @empresa
        AND (@todos OR p.usuario_id = @usuario)
      LIMIT 1
    '''),
    parameters: {
      'id': id,
      'empresa': usuario.empresaId,
      'usuario': usuario.id,
      'todos': usuario.nivel.alcanca(Nivel.engenheiro),
    },
  );

  if (pedidos.isEmpty) {
    return _erro(HttpStatus.notFound, 'Pedido nao encontrado.');
  }

  final itens = await banco.execute(
    Sql.named('''
      SELECT i.id, i.produto_id, p.nome AS produto_nome, p.unidade, i.quantidade
      FROM item_pedido i
      JOIN produto p ON p.id = i.produto_id
      WHERE i.pedido_id = @pedido AND p.empresa_id = @empresa
      ORDER BY i.id
    '''),
    parameters: {'pedido': id, 'empresa': usuario.empresaId},
  );

  return Response.json(
    body: {
      ...dadosDoPedido(pedidos.first.toColumnMap()),
      'itens': itens
          .map((linha) => dadosDoItemPedido(linha.toColumnMap()))
          .toList(),
    },
  );
}

Future<Response> _decidir(RequestContext context, int id) async {
  final Map<String, dynamic> corpo;
  try {
    corpo = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return _erro(HttpStatus.badRequest, 'Envie um JSON valido.');
  }

  final dados = corpo['pedido'];
  if (dados is! Map<String, dynamic>) {
    return _erro(
      HttpStatus.badRequest,
      'Envie o objeto dentro da chave "pedido".',
    );
  }

  final valorStatus = dados['status'];
  final status = valorStatus is String
      ? valorStatus.trim().toLowerCase()
      : null;
  if (status != 'aprovado' && status != 'recusado') {
    return _erro(HttpStatus.badRequest, 'Informe status aprovado ou recusado.');
  }

  final valorJustificativa = dados['justificativa'];
  if (valorJustificativa != null &&
      (valorJustificativa is! String ||
          valorJustificativa.trim().length > 255)) {
    return _erro(
      HttpStatus.badRequest,
      'A justificativa deve ser um texto com ate 255 caracteres.',
    );
  }

  final justificativa = (valorJustificativa as String?)?.trim();
  if (status == 'recusado' &&
      (justificativa == null || justificativa.isEmpty)) {
    return _erro(HttpStatus.badRequest, 'Informe a justificativa da recusa.');
  }

  final usuario = context.usuario;
  return context.read<Pool<void>>().runTx((transacao) async {
    final pedidos = await transacao.execute(
      Sql.named('''
        SELECT p.status
        FROM pedido p
        JOIN obra o ON o.id = p.obra_id
        JOIN usuario u ON u.id = p.usuario_id
        WHERE p.id = @id AND o.empresa_id = @empresa
          AND u.empresa_id = @empresa
        FOR UPDATE OF p
      '''),
      parameters: {'id': id, 'empresa': usuario.empresaId},
    );

    if (pedidos.isEmpty) {
      return _erro(HttpStatus.notFound, 'Pedido nao encontrado.');
    }
    if (pedidos.first.toColumnMap()['status'] != 'pendente') {
      return _erro(HttpStatus.conflict, 'Este pedido ja foi decidido.');
    }

    final atualizado = await transacao.execute(
      Sql.named('''
        UPDATE pedido
        SET status = @status,
            justificativa = COALESCE(@justificativa, justificativa)
        WHERE id = @id
        RETURNING id, usuario_id, obra_id, protocolo, status, justificativa, data
      '''),
      parameters: {
        'id': id,
        'status': status,
        'justificativa': justificativa,
      },
    );

    await transacao.execute(
      Sql.named('''
        INSERT INTO log_sistema (usuario_id, acao)
        VALUES (@usuario, @acao)
      '''),
      parameters: {'usuario': usuario.id, 'acao': 'Pedido $id $status.'},
    );

    return Response.json(body: dadosDoPedido(atualizado.first.toColumnMap()));
  });
}

Response _erro(int status, String mensagem) =>
    Response.json(statusCode: status, body: {'erro': mensagem});
