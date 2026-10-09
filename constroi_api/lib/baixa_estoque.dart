import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/pedidos.dart';
import 'package:postgres/postgres.dart';

enum MotivoFalhaBaixa {
  perfilNaoPermitido,
  pedidoNaoEncontrado,
  pedidoDecidido,
  itensInvalidos,
  saldoInsuficiente,
}

class FalhaBaixaEstoque implements Exception {
  const FalhaBaixaEstoque(this.motivo, this.mensagem);

  final MotivoFalhaBaixa motivo;
  final String mensagem;
}

/// Aprova, baixa todos os materiais e registra os logs no mesmo commit.
/// Uma falha deve sair do callback para que runTx reverta todas as escritas.
Future<Map<String, dynamic>> aprovarPedidoComBaixa(
  Pool<void> banco, {
  required int pedidoId,
  required UsuarioAutenticado usuario,
}) async {
  if (!usuario.nivel.alcanca(Nivel.engenheiro)) {
    throw const FalhaBaixaEstoque(
      MotivoFalhaBaixa.perfilNaoPermitido,
      'A aprovacao e restrita ao perfil engenheiro ou superior.',
    );
  }

  return banco.runTx(
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
        parameters: {'pedido': pedidoId, 'empresa': usuario.empresaId},
      );
      if (pedidos.isEmpty) {
        throw const FalhaBaixaEstoque(
          MotivoFalhaBaixa.pedidoNaoEncontrado,
          'Pedido nao encontrado.',
        );
      }
      final pedido = pedidos.single.toColumnMap();
      if ('${pedido['status']}'.toLowerCase() != 'pendente') {
        throw const FalhaBaixaEstoque(
          MotivoFalhaBaixa.pedidoDecidido,
          'Este pedido ja foi decidido.',
        );
      }

      // Tambem protege itens legados: produtos repetidos serao somados no SQL.
      final itens = await transacao.execute(
        Sql.named('''
        SELECT i.produto_id, p.empresa_id,
               (i.quantidade > 0 AND i.quantidade <= 9999999999.99) AS valida
        FROM item_pedido i
        JOIN produto p ON p.id = i.produto_id
        WHERE i.pedido_id = @pedido
        ORDER BY i.produto_id, i.id
        FOR UPDATE OF i
      '''),
        parameters: {'pedido': pedidoId},
      );
      if (itens.isEmpty ||
          itens.any((item) {
            final dados = item.toColumnMap();
            return dados['empresa_id'] != usuario.empresaId ||
                dados['valida'] != true;
          })) {
        throw const FalhaBaixaEstoque(
          MotivoFalhaBaixa.itensInvalidos,
          'O pedido deve conter materiais validos da sua empresa.',
        );
      }

      // Bloqueia materiais na mesma ordem para evitar deadlock.
      // A comparacao/subtracao de quantidades fica no PostgreSQL (NUMERIC).
      final saldos = await transacao.execute(
        Sql.named('''
        SELECT e.id, e.produto_id, i.quantidade::text AS solicitada
        FROM estoque e
        JOIN (
          SELECT produto_id, SUM(quantidade) AS quantidade
          FROM item_pedido WHERE pedido_id = @pedido
          GROUP BY produto_id
        ) i ON i.produto_id = e.produto_id
        WHERE e.obra_id = @obra
        ORDER BY e.produto_id
        FOR UPDATE OF e
      '''),
        parameters: {'pedido': pedidoId, 'obra': pedido['obra_id']},
      );
      final produtos = itens
          .map((item) => item.toColumnMap()['produto_id'])
          .toSet();
      if (saldos.length != produtos.length) {
        throw const FalhaBaixaEstoque(
          MotivoFalhaBaixa.saldoInsuficiente,
          'Estoque insuficiente para aprovar todos os itens do pedido.',
        );
      }

      final baixas = <Map<String, dynamic>>[];
      for (final linha in saldos) {
        final saldo = linha.toColumnMap();
        final atualizado = await transacao.execute(
          Sql.named('''
          UPDATE estoque SET quantidade = quantidade - @quantidade::numeric
          WHERE id = @estoque AND quantidade >= @quantidade::numeric
            AND quantidade <= 9999999999.99
          RETURNING quantidade::text AS saldo
        '''),
          parameters: {
            'estoque': saldo['id'],
            'quantidade': saldo['solicitada'],
          },
        );
        if (atualizado.isEmpty) {
          throw const FalhaBaixaEstoque(
            MotivoFalhaBaixa.saldoInsuficiente,
            'Estoque insuficiente para aprovar todos os itens do pedido.',
          );
        }
        final restante = atualizado.single.toColumnMap()['saldo'];
        await transacao.execute(
          Sql.named('''
          INSERT INTO log_sistema (usuario_id, acao)
          VALUES (@usuario, @acao)
        '''),
          parameters: {
            'usuario': usuario.id,
            'acao':
                'BAIXA_ESTOQUE pedido=$pedidoId obra=${pedido['obra_id']} '
                'produto=${saldo['produto_id']} '
                'quantidade=${saldo['solicitada']} '
                'saldo=$restante protocolo=${pedido['protocolo']}',
          },
        );
        baixas.add({
          'produto_id': saldo['produto_id'],
          'quantidade': saldo['solicitada'],
          'saldo': restante,
        });
      }

      final aprovados = await transacao.execute(
        Sql.named('''
        UPDATE pedido SET status = 'aprovado'
        WHERE id = @pedido
        RETURNING id, usuario_id, obra_id, protocolo, status, justificativa, data
      '''),
        parameters: {'pedido': pedidoId},
      );
      return {
        ...dadosDoPedido(aprovados.single.toColumnMap()),
        'baixas': baixas,
      };
    },
    settings: TransactionSettings(
      isolationLevel: IsolationLevel.readCommitted,
    ),
  );
}
