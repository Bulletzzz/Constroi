import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/emprestimos.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context, String idDaRota) async {
  if (context.request.method != HttpMethod.patch) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final id = validarIdEmprestimo(int.tryParse(idDaRota));
  if (id == null) return _erro(400, 'Id do emprestimo invalido.');
  final Map<String, dynamic> corpo;
  try {
    corpo = await context.request.json() as Map<String, dynamic>;
  } on Object {
    return _erro(400, 'Envie um JSON valido.');
  }
  final dados = corpo['emprestimo'];
  if (dados is! Map<String, dynamic> || dados['status'] != 'devolvido') {
    return _erro(400, 'Informe emprestimo com status devolvido.');
  }
  try {
    final resultado = await devolverEmprestimo(
      context.read<Pool<void>>(),
      autor: context.usuario,
      id: id,
    );
    return Response.json(body: resultado);
  } on FalhaEmprestimo catch (erro) {
    return _erro(erro.status, erro.mensagem);
  }
}

Response _erro(int status, String mensagem) =>
    Response.json(statusCode: status, body: {'erro': mensagem});
