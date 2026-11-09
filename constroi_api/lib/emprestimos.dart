import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/logs.dart';
import 'package:postgres/postgres.dart';

int? validarIdEmprestimo(Object? valor) =>
    valor is int && valor > 0 && valor <= 2147483647 ? valor : null;

class FalhaEmprestimo implements Exception {
  const FalhaEmprestimo(this.status, this.mensagem);

  final int status;
  final String mensagem;
}

const consultaEmprestimos = '''
  SELECT p.id, p.equipamento_id, e.nome AS equipamento_nome,
         p.usuario_id, u.nome AS responsavel_nome, p.obra_id,
         o.nome AS obra_nome, p.data_emprestimo, p.data_prevista,
         p.data_devolucao, p.status,
         (p.status = 'aberto' AND p.data_prevista < CURRENT_TIMESTAMP) AS atrasado
  FROM emprestimo p
  JOIN equipamento e ON e.id = p.equipamento_id AND e.empresa_id = p.empresa_id
  JOIN usuario u ON u.id = p.usuario_id AND u.empresa_id = p.empresa_id
  JOIN obra o ON o.id = p.obra_id AND o.empresa_id = p.empresa_id
''';

Map<String, dynamic> dadosDoEmprestimo(Map<String, dynamic> linha) => {
  ...linha,
  for (final campo in ['data_emprestimo', 'data_prevista', 'data_devolucao'])
    campo: (linha[campo] as DateTime?)?.toUtc().toIso8601String(),
};

Future<Map<String, dynamic>> buscarEmprestimo(
  Session banco,
  int id,
  int empresaId,
) async {
  final linhas = await banco.execute(
    Sql.named(
      '$consultaEmprestimos WHERE p.id = @id AND p.empresa_id = @empresa',
    ),
    parameters: {'id': id, 'empresa': empresaId},
  );
  if (linhas.isEmpty) {
    throw const FalhaEmprestimo(404, 'Emprestimo nao encontrado.');
  }
  return dadosDoEmprestimo(linhas.single.toColumnMap());
}

Future<Map<String, dynamic>> criarEmprestimo(
  Pool<void> banco, {
  required UsuarioAutenticado autor,
  required int equipamentoId,
  required int usuarioId,
  required int obraId,
  required int dias,
}) async {
  try {
    return await banco.runTx((tx) async {
      final equipamentos = await tx.execute(
        Sql.named('''
          SELECT status FROM equipamento
          WHERE id = @equipamento AND empresa_id = @empresa FOR UPDATE
        '''),
        parameters: {'equipamento': equipamentoId, 'empresa': autor.empresaId},
      );
      if (equipamentos.isEmpty) {
        throw const FalhaEmprestimo(404, 'Equipamento nao encontrado.');
      }
      final referencias = await tx.execute(
        Sql.named('''
          SELECT u.id FROM usuario u CROSS JOIN obra o
          WHERE u.id = @usuario AND u.empresa_id = @empresa AND u.ativo
            AND o.id = @obra AND o.empresa_id = @empresa
          FOR SHARE OF u, o
        '''),
        parameters: {
          'usuario': usuarioId,
          'obra': obraId,
          'empresa': autor.empresaId,
        },
      );
      if (referencias.isEmpty) {
        throw const FalhaEmprestimo(
          404,
          'Responsavel ou obra nao encontrados.',
        );
      }
      if (equipamentos.single.toColumnMap()['status'] != 'disponivel') {
        throw const FalhaEmprestimo(
          409,
          'Equipamento indisponivel para emprestimo.',
        );
      }
      final criados = await tx.execute(
        Sql.named('''
          INSERT INTO emprestimo (
            empresa_id, equipamento_id, usuario_id, obra_id,
            data_emprestimo, data_prevista, status
          )
          SELECT @empresa, @equipamento, @usuario, @obra,
                 CURRENT_TIMESTAMP,
                 CURRENT_TIMESTAMP + @dias::int * INTERVAL '24 hours', 'aberto'
          WHERE @dias::int <= FLOOR(EXTRACT(EPOCH FROM (
            TIMESTAMPTZ '9999-12-31 23:59:59+00' - CURRENT_TIMESTAMP
          )) / 86400)
          RETURNING id
        '''),
        parameters: {
          'empresa': autor.empresaId,
          'equipamento': equipamentoId,
          'usuario': usuarioId,
          'obra': obraId,
          'dias': dias,
        },
      );
      if (criados.isEmpty) {
        throw const FalhaEmprestimo(
          400,
          'Prazo fora do intervalo de datas suportado.',
        );
      }
      final id = criados.single.toColumnMap()['id']! as int;
      await tx.execute(
        Sql.named('''
          UPDATE equipamento SET status = 'em_uso', atualizado_em = CURRENT_TIMESTAMP
          WHERE id = @equipamento AND empresa_id = @empresa
        '''),
        parameters: {'equipamento': equipamentoId, 'empresa': autor.empresaId},
      );
      await registrarLog(
        tx,
        usuarioId: autor.id,
        acao:
            'EMPRESTIMO_EQUIPAMENTO emprestimo=$id equipamento=$equipamentoId '
            'usuario=$usuarioId obra=$obraId dias=$dias',
      );
      return buscarEmprestimo(tx, id, autor.empresaId);
    });
  } on ServerException catch (erro) {
    if (erro.code == '23505' &&
        erro.constraintName == 'ux_emprestimo_equipamento_aberto') {
      throw const FalhaEmprestimo(409, 'Equipamento ja emprestado.');
    }
    if ({'22003', '22008', '22015'}.contains(erro.code)) {
      throw const FalhaEmprestimo(
        400,
        'Prazo fora do intervalo de datas suportado.',
      );
    }
    rethrow;
  }
}

Future<Map<String, dynamic>> devolverEmprestimo(
  Pool<void> banco, {
  required UsuarioAutenticado autor,
  required int id,
}) => banco.runTx((tx) async {
  final encontrados = await tx.execute(
    Sql.named('''
      SELECT equipamento_id FROM emprestimo
      WHERE id = @id AND empresa_id = @empresa
    '''),
    parameters: {'id': id, 'empresa': autor.empresaId},
  );
  if (encontrados.isEmpty) {
    throw const FalhaEmprestimo(404, 'Emprestimo nao encontrado.');
  }
  final equipamentoId = encontrados.single.toColumnMap()['equipamento_id'];
  await tx.execute(
    Sql.named('''
      SELECT id FROM equipamento
      WHERE id = @equipamento AND empresa_id = @empresa FOR UPDATE
    '''),
    parameters: {'equipamento': equipamentoId, 'empresa': autor.empresaId},
  );
  final bloqueados = await tx.execute(
    Sql.named('''
      SELECT status, usuario_id, obra_id FROM emprestimo
      WHERE id = @id AND empresa_id = @empresa AND equipamento_id = @equipamento
      FOR UPDATE
    '''),
    parameters: {
      'id': id,
      'empresa': autor.empresaId,
      'equipamento': equipamentoId,
    },
  );
  if (bloqueados.isEmpty) {
    throw const FalhaEmprestimo(404, 'Emprestimo nao encontrado.');
  }
  final emprestimo = bloqueados.single.toColumnMap();
  if (emprestimo['status'] != 'aberto') {
    throw const FalhaEmprestimo(409, 'Emprestimo ja devolvido.');
  }
  await tx.execute(
    Sql.named('''
      UPDATE emprestimo SET status = 'devolvido', data_devolucao = clock_timestamp()
      WHERE id = @id AND empresa_id = @empresa
    '''),
    parameters: {'id': id, 'empresa': autor.empresaId},
  );
  await tx.execute(
    Sql.named('''
      UPDATE equipamento SET status = 'disponivel', atualizado_em = CURRENT_TIMESTAMP
      WHERE id = @equipamento AND empresa_id = @empresa
    '''),
    parameters: {'equipamento': equipamentoId, 'empresa': autor.empresaId},
  );
  await registrarLog(
    tx,
    usuarioId: autor.id,
    acao:
        'DEVOLUCAO_EQUIPAMENTO emprestimo=$id equipamento=$equipamentoId '
        'usuario=${emprestimo['usuario_id']} obra=${emprestimo['obra_id']}',
  );
  return buscarEmprestimo(tx, id, autor.empresaId);
});
