import 'package:postgres/postgres.dart';

/// Recebe somente eventos montados pelo servidor, nunca o corpo da requisicao.
/// Use a mesma sessao/transacao da alteracao que esta sendo registrada.
Future<void> registrarLog(
  Session banco, {
  required int usuarioId,
  required String acao,
}) async {
  await banco.execute(
    Sql.named('''
      INSERT INTO log_sistema (usuario_id, acao) VALUES (@usuario, @acao)
    '''),
    parameters: {'usuario': usuarioId, 'acao': acao},
  );
}

/// Escritas com RETURNING id: alteracao e log confirmam ou revertem juntos.
/// Nenhuma linha alterada (404/conflito) significa nenhum log novo.
Future<Result> executarEscritaComLog(
  Pool<void> banco,
  Sql consulta, {
  required Map<String, dynamic> parameters,
  required int usuarioId,
  required String evento,
  required String recurso,
}) => banco.runTx((tx) async {
  final resultado = await tx.execute(consulta, parameters: parameters);
  if (resultado.isNotEmpty) {
    final id = resultado.first.toColumnMap()['id'];
    await registrarLog(tx, usuarioId: usuarioId, acao: '$evento $recurso=$id');
  }
  return resultado;
});

/// Data civil em UTC ou instante ISO 8601 com fuso explicito.
DateTime? validarDataLog(String valor) {
  final partes = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,6})?)?(Z|[+-]\d{2}:\d{2}))?$',
  ).firstMatch(valor);
  if (partes == null) return null;
  final ano = int.parse(partes[1]!);
  final mes = int.parse(partes[2]!);
  final dia = int.parse(partes[3]!);
  final data = DateTime.utc(ano, mes, dia);
  if (ano < 1 || data.year != ano || data.month != mes || data.day != dia) {
    return null;
  }
  if (partes[4] == null) return data;
  if (int.parse(partes[4]!) > 23 ||
      int.parse(partes[5]!) > 59 ||
      int.parse(partes[6] ?? '0') > 59) {
    return null;
  }
  final fuso = partes[7]!;
  if (fuso != 'Z' &&
      (int.parse(fuso.substring(1, 3)) > 23 ||
          int.parse(fuso.substring(4, 6)) > 59)) {
    return null;
  }
  final instante = DateTime.tryParse(valor)?.toUtc();
  if (instante == null || instante.year < 1 || instante.year > 9999) {
    return null;
  }
  return instante;
}
