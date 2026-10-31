import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/logs.dart';
import 'package:constroi_api/nfe.dart';
import 'package:postgres/postgres.dart';

Future<Map<String, Object?>> importarNfe(
  Pool<void> banco, {
  required UsuarioAutenticado usuario,
  required int obraId,
  required NotaFiscal nota,
}) async {
  if (!usuario.nivel.alcanca(Nivel.engenheiro)) {
    throw const FalhaNfe(403, 'Acao restrita a engenheiro ou master.');
  }
  try {
    return await banco.runTx((tx) async {
      final obras = await tx.execute(
        Sql.named(
          'SELECT id FROM obra WHERE id = @obra AND empresa_id = @empresa '
          'FOR KEY SHARE',
        ),
        parameters: {'obra': obraId, 'empresa': usuario.empresaId},
      );
      if (obras.isEmpty) throw const FalhaNfe(404, 'Obra nao encontrada.');
      final catalogo = await tx.execute(
        Sql.named('''
        SELECT id, nome, unidade, sku FROM produto
        WHERE empresa_id = @empresa AND
          (LOWER(sku) = ANY(@codigos::text[]) OR LOWER(nome) = ANY(@nomes::text[]))
        ORDER BY id FOR SHARE
      '''),
        parameters: {
          'empresa': usuario.empresaId,
          'codigos': nota.itens.map((i) => i.codigo.toLowerCase()).toList(),
          'nomes': nota.itens.map((i) => i.nome.toLowerCase()).toList(),
        },
      );
      final produtos = catalogo.map((r) => r.toColumnMap()).toList();
      final pendencias = <Map<String, Object?>>[];
      final itens = <({int produto, String quantidade})>[];
      for (final item in nota.itens) {
        var candidatos = produtos
            .where(
              (p) =>
                  '${p['sku'] ?? ''}'.toLowerCase() ==
                  item.codigo.toLowerCase(),
            )
            .toList();
        if (candidatos.isEmpty) {
          candidatos = produtos
              .where(
                (p) => '${p['nome']}'.toLowerCase() == item.nome.toLowerCase(),
              )
              .toList();
        }
        if (candidatos.length != 1 ||
            '${candidatos.single['unidade']}'.toLowerCase() != item.unidade) {
          pendencias.add({
            'codigo': item.codigo,
            'nome': item.nome,
            'unidade': item.unidade,
            'motivo': candidatos.isEmpty
                ? 'nao_encontrado'
                : candidatos.length > 1
                ? 'ambiguo'
                : 'unidade_diferente',
          });
        } else {
          itens.add((
            produto: candidatos.single['id']! as int,
            quantidade: item.quantidade,
          ));
        }
      }
      if (pendencias.isNotEmpty) {
        throw FalhaNfe(
          422,
          'Confira os materiais antes de importar. '
          'Nenhuma entrada foi gravada.',
          detalhes: {'materiais_pendentes': pendencias},
        );
      }
      final criadas = await tx.execute(
        Sql.named('''
        INSERT INTO entrada_estoque (usuario_id, obra_id, xml_nota_fiscal, empresa_nfe_id, chave_nfe)
        VALUES (@usuario, @obra, @xml, @empresa, @chave)
        ON CONFLICT (empresa_nfe_id, chave_nfe) DO NOTHING
        RETURNING id, data
      '''),
        parameters: {
          'usuario': usuario.id,
          'obra': obraId,
          'xml': nota.xml,
          'empresa': usuario.empresaId,
          'chave': nota.chave,
        },
      );
      if (criadas.isEmpty) {
        throw const FalhaNfe(409, 'Esta NF-e ja foi registrada na empresa.');
      }
      final entrada = criadas.single.toColumnMap();
      // Agrupar e ordenar tambem protege notas com o mesmo produto repetido.
      final quantidades = <int, List<String>>{};
      for (final item in itens) {
        await tx.execute(
          Sql.named(
            'INSERT INTO item_entrada (entrada_id, produto_id, quantidade) '
            'VALUES (@entrada, @produto, @quantidade::numeric)',
          ),
          parameters: {
            'entrada': entrada['id'],
            'produto': item.produto,
            'quantidade': item.quantidade,
          },
        );
        quantidades.putIfAbsent(item.produto, () => []).add(item.quantidade);
      }
      final produtosOrdenados = quantidades.keys.toList()..sort();
      final saldos = <Map<String, Object?>>[];
      for (final produto in produtosOrdenados) {
        final saldo = await tx.execute(
          Sql.named('''
          INSERT INTO estoque (obra_id, produto_id, quantidade)
          SELECT @obra, @produto, SUM(q::numeric) FROM UNNEST(@quantidades::text[]) q
          ON CONFLICT (obra_id, produto_id) DO UPDATE
          SET quantidade = estoque.quantidade + EXCLUDED.quantidade
          RETURNING quantidade::text AS saldo
        '''),
          parameters: {
            'obra': obraId,
            'produto': produto,
            'quantidades': quantidades[produto],
          },
        );
        saldos.add({'produto_id': produto, 'saldo': saldo.single[0]});
      }
      await registrarLog(
        tx,
        usuarioId: usuario.id,
        acao:
            'ENTRADA_NFE entrada=${entrada['id']} obra=$obraId '
            'chave=${nota.chave}',
      );
      return {
        'id': entrada['id'],
        'obra_id': obraId,
        'chave_nfe': nota.chave,
        'data': (entrada['data']! as DateTime).toIso8601String(),
        'itens': itens
            .map((i) => {'produto_id': i.produto, 'quantidade': i.quantidade})
            .toList(),
        'saldos': saldos,
      };
    });
  } on ServerException catch (e) {
    if (e.code == '22003') {
      throw const FalhaNfe(
        409,
        'A entrada excede a quantidade maxima do estoque.',
      );
    }
    rethrow;
  }
}
