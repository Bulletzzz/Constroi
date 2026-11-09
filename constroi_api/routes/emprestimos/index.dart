import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/emprestimos.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method == HttpMethod.get) return _listar(context);
  if (context.request.method == HttpMethod.post) return _criar(context);
  return Response(statusCode: HttpStatus.methodNotAllowed);
}

Future<Response> _listar(RequestContext context) async {
  final filtros = context.request.uri.queryParameters;
  final equipamento = filtros.containsKey('equipamento_id')
      ? validarIdEmprestimo(int.tryParse(filtros['equipamento_id']!))
      : null;
  final status = filtros['status'];
  final limite = int.tryParse(filtros['limit'] ?? '50');
  final offset = int.tryParse(filtros['offset'] ?? '0');
  if ((filtros.containsKey('equipamento_id') && equipamento == null) ||
      (status != null && !{'aberto', 'devolvido'}.contains(status)) ||
      limite == null ||
      limite < 1 ||
      limite > 200 ||
      offset == null ||
      offset < 0 ||
      offset > 2147483647) {
    return _erro(400, 'Filtros ou paginacao invalidos.');
  }
  final banco = context.read<Pool<void>>();
  final linhas = await banco.execute(
    Sql.named('''
      $consultaEmprestimos
      WHERE p.empresa_id = @empresa
        ${equipamento == null ? '' : 'AND p.equipamento_id = @equipamento'}
        ${status == null ? '' : 'AND p.status = @status'}
      ORDER BY p.data_emprestimo DESC, p.id DESC
      LIMIT @limite OFFSET @offset
    '''),
    parameters: {
      'empresa': context.usuario.empresaId,
      if (equipamento != null) 'equipamento': equipamento,
      if (status != null) 'status': status,
      'limite': limite,
      'offset': offset,
    },
  );
  return Response.json(
    body: {
      'emprestimos': linhas
          .map((r) => dadosDoEmprestimo(r.toColumnMap()))
          .toList(),
    },
  );
}

Future<Response> _criar(RequestContext context) async {
  final Map<String, dynamic> corpo;
  try {
    corpo = await context.request.json() as Map<String, dynamic>;
  } on Object {
    return _erro(400, 'Envie um JSON valido.');
  }
  final dados = corpo['emprestimo'];
  if (dados is! Map<String, dynamic>) {
    return _erro(400, 'Envie o objeto dentro da chave "emprestimo".');
  }
  final equipamentoId = validarIdEmprestimo(dados['equipamento_id']);
  final usuarioId = validarIdEmprestimo(dados['usuario_id']);
  final obraId = validarIdEmprestimo(dados['obra_id']);
  final dias = validarIdEmprestimo(dados['dias']);
  if (equipamentoId == null ||
      usuarioId == null ||
      obraId == null ||
      dias == null) {
    return _erro(
      400,
      'Informe equipamento_id, usuario_id, obra_id e dias inteiros positivos.',
    );
  }
  try {
    final resultado = await criarEmprestimo(
      context.read<Pool<void>>(),
      autor: context.usuario,
      equipamentoId: equipamentoId,
      usuarioId: usuarioId,
      obraId: obraId,
      dias: dias,
    );
    return Response.json(statusCode: HttpStatus.created, body: resultado);
  } on FalhaEmprestimo catch (erro) {
    return _erro(erro.status, erro.mensagem);
  }
}

Response _erro(int status, String mensagem) =>
    Response.json(statusCode: status, body: {'erro': mensagem});
