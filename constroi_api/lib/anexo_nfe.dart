import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/nfe.dart';
import 'package:postgres/postgres.dart';

/// Anexa somente o documento: nunca insere itens ou altera estoque.
Future<Map<String, Object?>> anexarNfe(
  Pool<void> banco, {
  required UsuarioAutenticado usuario,
  required int entradaId,
  required NotaFiscal nota,
}) async {
  if (!usuario.nivel.alcanca(Nivel.engenheiro)) {
    throw const FalhaNfe(403, 'Acao restrita a engenheiro ou master.');
  }
  try {
    return await banco.runTx((tx) async {
      final entradas = await tx.execute(
        Sql.named('''
        SELECT e.id, e.obra_id, e.xml_nota_fiscal
        FROM entrada_estoque e
        JOIN obra o ON o.id = e.obra_id
        JOIN usuario u ON u.id = e.usuario_id
        WHERE e.id = @entrada AND o.empresa_id = @empresa
          AND u.empresa_id = @empresa
        FOR UPDATE OF e
      '''),
        parameters: {'entrada': entradaId, 'empresa': usuario.empresaId},
      );
      if (entradas.isEmpty) {
        throw const FalhaNfe(404, 'Entrada nao encontrada.');
      }
      final entrada = entradas.single.toColumnMap();
      if (entrada['xml_nota_fiscal'] != null) {
        throw const FalhaNfe(409, 'Esta entrada ja possui XML.');
      }
      await tx.execute(
        Sql.named('''
        UPDATE entrada_estoque
        SET xml_nota_fiscal = @xml, empresa_nfe_id = @empresa, chave_nfe = @chave
        WHERE id = @entrada
      '''),
        parameters: {
          'entrada': entradaId,
          'empresa': usuario.empresaId,
          'chave': nota.chave,
          'xml': nota.xml,
        },
      );
      await tx.execute(
        Sql.named('''
        INSERT INTO log_sistema (usuario_id, acao) VALUES (@usuario, @acao)
      '''),
        parameters: {
          'usuario': usuario.id,
          'acao': 'ANEXO_NFE entrada=$entradaId chave=${nota.chave}',
        },
      );
      return {
        'id': entradaId,
        'obra_id': entrada['obra_id'],
        'chave_nfe': nota.chave,
        'xml_anexado': true,
      };
    });
  } on ServerException catch (erro) {
    if (erro.code == '23505' &&
        erro.constraintName == 'ux_entrada_nfe_empresa') {
      throw const FalhaNfe(409, 'Esta NF-e ja foi registrada na empresa.');
    }
    rethrow;
  }
}
