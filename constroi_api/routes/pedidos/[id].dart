import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/baixa_estoque.dart';
import 'package:constroi_api/logs.dart';
import 'package:constroi_api/pedidos.dart';
import 'package:constroi_api/permissao.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context, String idDaRota) async {
  if (context.request.method == HttpMethod.patch) {
    return exigirNivel(Nivel.engenheiro)(
      (context) => _decidir(context, idDaRota),
    )(context);
  }
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final id = validarIdPedido(int.tryParse(idDaRota));
  if (id == null) {
    return _erro(HttpStatus.badRequest, 'Id do pedido invalido.');
  }

  final usuario = context.usuario;
  final banco = context.read<Pool<void>>();
  final pedidos = await banco.execute(
    Sql.named('''
      SELECT p.id, p.usuario_id, p.obra_id, p.protocolo,
             p.status, p.justificativa, p.justificativa_recusa,
             p.local_obra, p.urgencia, p.data
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

Future<Response> _decidir(RequestContext context, String idDaRota) async {
  final id = validarIdPedido(int.tryParse(idDaRota));
  if (id == null) {
    return _erro(HttpStatus.badRequest, 'Id do pedido invalido.');
  }
  final Object? corpo;
  try {
    corpo = await context.request.json();
  } catch (_) {
    return _erro(HttpStatus.badRequest, 'Envie um JSON valido.');
  }
  if (corpo is! Map<String, dynamic> ||
      corpo['pedido'] is! Map<String, dynamic>) {
    return _erro(
      HttpStatus.badRequest,
      'Envie o objeto dentro da chave "pedido".',
    );
  }

  final dados = corpo['pedido'] as Map<String, dynamic>;
  final status = dados['status'];
  if (status != 'aprovado' && status != 'recusado') {
    return _erro(HttpStatus.badRequest, 'Informe status aprovado ou recusado.');
  }

  if (status == 'recusado') {
    final justificativa = dados['justificativa'];
    if (justificativa is! String ||
        justificativa.trim().isEmpty ||
        justificativa.trim().length > 255) {
      return _erro(
        HttpStatus.badRequest,
        'A recusa exige justificativa com ate 255 caracteres.',
      );
    }
    return _recusar(context, id, justificativa.trim());
  }

  try {
    final pedido = await aprovarPedidoComBaixa(
      context.read<Pool<void>>(),
      pedidoId: id,
      usuario: context.usuario,
    );
    return Response.json(body: pedido);
  } on FalhaBaixaEstoque catch (erro) {
    final status = switch (erro.motivo) {
      MotivoFalhaBaixa.perfilNaoPermitido => HttpStatus.forbidden,
      MotivoFalhaBaixa.pedidoNaoEncontrado => HttpStatus.notFound,
      MotivoFalhaBaixa.itensInvalidos => HttpStatus.badRequest,
      MotivoFalhaBaixa.pedidoDecidido ||
      MotivoFalhaBaixa.saldoInsuficiente => HttpStatus.conflict,
    };
    return _erro(status, erro.mensagem);
  }
}

Future<Response> _recusar(
  RequestContext context,
  int id,
  String justificativa,
) async {
  final usuario = context.usuario;
  return context.read<Pool<void>>().runTx(
    (transacao) async {
      final pedidos = await transacao.execute(
        Sql.named('''
          SELECT p.id, p.obra_id, p.protocolo, p.status
          FROM pedido p
          JOIN obra o ON o.id = p.obra_id
          JOIN usuario u ON u.id = p.usuario_id
          WHERE p.id = @pedido AND o.empresa_id = @empresa
            AND u.empresa_id = @empresa
          FOR UPDATE OF p
        '''),
        parameters: {'pedido': id, 'empresa': usuario.empresaId},
      );
      if (pedidos.isEmpty) {
        return _erro(HttpStatus.notFound, 'Pedido nao encontrado.');
      }

      final pedido = pedidos.single.toColumnMap();
      if ('${pedido['status']}'.toLowerCase() != 'pendente') {
        return _erro(HttpStatus.conflict, 'Este pedido ja foi decidido.');
      }

      final recusados = await transacao.execute(
        Sql.named('''
          UPDATE pedido
          SET status = 'recusado', justificativa_recusa = @justificativa
          WHERE id = @pedido
          RETURNING id, usuario_id, obra_id, protocolo, status, justificativa,
                    justificativa_recusa, local_obra, urgencia, data
        '''),
        parameters: {'pedido': id, 'justificativa': justificativa},
      );
      await registrarLog(
        transacao,
        usuarioId: usuario.id,
        acao:
            'RECUSA_PEDIDO pedido=$id obra=${pedido['obra_id']} '
            'protocolo=${pedido['protocolo']}',
      );

      return Response.json(
        body: dadosDoPedido(recusados.single.toColumnMap()),
      );
    },
    settings: TransactionSettings(
      isolationLevel: IsolationLevel.readCommitted,
    ),
  );
}

Response _erro(int status, String mensagem) =>
    Response.json(statusCode: status, body: {'erro': mensagem});
