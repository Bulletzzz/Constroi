import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/pedidos.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

/// Aprova o pedido e da baixa no estoque da obra no mesmo commit (RNF20).
///
/// E o endpoint mais perigoso do sistema: dois pedidos disputando o ultimo
/// saco de cimento nao podem sair os dois. Ler o saldo, conferir e subtrair
/// em passos separados sem trava deixa as duas transacoes lerem "1 saco",
/// as duas aprovarem e o estoque fechar em -1. Por isso o saldo e lido com
/// SELECT ... FOR UPDATE: a segunda aprovacao espera a primeira terminar e
/// le o saldo ja descontado.
Future<Response> onRequest(RequestContext context, String idDaRota) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final id = validarIdPedido(int.tryParse(idDaRota));
  if (id == null) {
    return _erro(HttpStatus.badRequest, 'Id do pedido invalido.');
  }

  final usuario = context.usuario;
  try {
    return await context.read<Pool<void>>().runTx(
      (transacao) => _aprovar(transacao, id, usuario),
    );
  } on ServerException catch (erro) {
    // Ultima barreira: se alguma baixa escapar da conferencia acima, o
    // CHECK (quantidade >= 0) da migration 008 derruba o UPDATE e a
    // transacao inteira volta, inclusive o status e o log.
    if (erro.code == '23514') {
      return _erro(
        HttpStatus.conflict,
        'Saldo insuficiente no estoque da obra. Nada foi baixado.',
      );
    }
    rethrow;
  }
}

Future<Response> _aprovar(
  TxSession transacao,
  int id,
  UsuarioAutenticado usuario,
) async {
  // Trava o pedido primeiro: duas aprovacoes do mesmo pedido em paralelo
  // dariam baixa em dobro, mesmo com saldo sobrando.
  final pedidos = await transacao.execute(
    Sql.named('''
      SELECT p.id, p.obra_id, p.protocolo, p.status
      FROM pedido p
      JOIN obra o ON o.id = p.obra_id
      WHERE p.id = @id AND o.empresa_id = @empresa
      FOR UPDATE OF p
    '''),
    parameters: {'id': id, 'empresa': usuario.empresaId},
  );
  if (pedidos.isEmpty) {
    return _erro(HttpStatus.notFound, 'Pedido nao encontrado.');
  }

  final pedido = pedidos.first.toColumnMap();
  final status = '${pedido['status']}'.toLowerCase();
  if (status != 'pendente') {
    return _erro(
      HttpStatus.conflict,
      'Pedido ja analisado. Status atual: $status.',
    );
  }

  // Trava as linhas de estoque sempre na ordem de produto_id. Sem ordem
  // fixa, dois pedidos com os mesmos produtos em ordem trocada travariam
  // um esperando o outro (deadlock). O FOR UPDATE nao pode ir na mesma
  // consulta do LEFT JOIN abaixo: o Postgres recusa travar o lado que pode
  // vir nulo.
  await transacao.execute(
    Sql.named('''
      SELECT e.id
      FROM estoque e
      JOIN item_pedido i ON i.produto_id = e.produto_id
      WHERE i.pedido_id = @pedido AND e.obra_id = @obra
      ORDER BY e.produto_id
      FOR UPDATE OF e
    '''),
    parameters: {'pedido': id, 'obra': pedido['obra_id']},
  );

  // Com as linhas travadas, esta leitura ja enxerga o saldo final de quem
  // aprovou antes. A comparacao fica no SQL para nao passar NUMERIC por
  // double. Produto sem linha de estoque na obra conta como saldo zero.
  final saldos = await transacao.execute(
    Sql.named('''
      SELECT i.produto_id, pr.nome AS produto_nome,
             i.quantidade AS solicitada,
             COALESCE(e.quantidade, 0) AS saldo,
             COALESCE(e.quantidade, 0) >= i.quantidade AS suficiente
      FROM item_pedido i
      JOIN produto pr ON pr.id = i.produto_id
      LEFT JOIN estoque e
        ON e.produto_id = i.produto_id AND e.obra_id = @obra
      WHERE i.pedido_id = @pedido
      ORDER BY i.produto_id
    '''),
    parameters: {'pedido': id, 'obra': pedido['obra_id']},
  );

  final faltando = saldos
      .map((linha) => linha.toColumnMap())
      .where((linha) => linha['suficiente'] != true)
      .map(
        (linha) => {
          'produto_id': linha['produto_id'],
          'produto_nome': linha['produto_nome'],
          'solicitada': '${linha['solicitada']}',
          'saldo': '${linha['saldo']}',
        },
      )
      .toList();
  // Recusa a aprovacao e deixa o pedido pendente: o engenheiro ainda pode
  // decidir comprar ou alugar em vez de baixar do estoque.
  if (faltando.isNotEmpty) {
    return Response.json(
      statusCode: HttpStatus.conflict,
      body: {
        'erro': 'Saldo insuficiente no estoque da obra. Nada foi baixado.',
        'faltando': faltando,
      },
    );
  }

  final baixas = await transacao.execute(
    Sql.named('''
      UPDATE estoque e
      SET quantidade = e.quantidade - i.quantidade
      FROM item_pedido i
      WHERE i.pedido_id = @pedido
        AND e.obra_id = @obra
        AND e.produto_id = i.produto_id
      RETURNING e.produto_id, e.quantidade AS saldo
    '''),
    parameters: {'pedido': id, 'obra': pedido['obra_id']},
  );

  final aprovados = await transacao.execute(
    Sql.named('''
      UPDATE pedido SET status = 'aprovado'
      WHERE id = @pedido
      RETURNING id, usuario_id, obra_id, protocolo, status, justificativa, data
    '''),
    parameters: {'pedido': id},
  );

  // Uma linha de log por movimentacao, dentro da mesma transacao: se o log
  // falhar, a baixa tambem volta, e nunca existe estoque mexido sem rastro.
  await transacao.execute(
    Sql.named('''
      INSERT INTO log_sistema (usuario_id, acao)
      SELECT @usuario,
             format('Pedido %s aprovado: baixa de %s do produto %s na obra %s',
                    @protocolo::text, i.quantidade, i.produto_id, @obra::int)
      FROM item_pedido i
      WHERE i.pedido_id = @pedido
      ORDER BY i.produto_id
    '''),
    parameters: {
      'usuario': usuario.id,
      'protocolo': pedido['protocolo'],
      'obra': pedido['obra_id'],
      'pedido': id,
    },
  );

  return Response.json(
    body: {
      ...dadosDoPedido(aprovados.first.toColumnMap()),
      'baixas': baixas.map((linha) {
        final dados = linha.toColumnMap();
        return {
          'produto_id': dados['produto_id'],
          'saldo': '${dados['saldo']}',
        };
      }).toList(),
    },
  );
}

Response _erro(int status, String mensagem) =>
    Response.json(statusCode: status, body: {'erro': mensagem});
