import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/obras.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context, String idDaRota) async {
  final id = int.tryParse(idDaRota);
  if (id == null) return _erro(HttpStatus.badRequest, 'Id da obra invalido.');

  final metodo = context.request.method;
  if (metodo == HttpMethod.get) return _buscar(context, id);
  if (metodo == HttpMethod.patch) return _editar(context, id);
  return Response(statusCode: HttpStatus.methodNotAllowed);
}

Future<Response> _buscar(RequestContext context, int id) async {
  final banco = context.read<Pool<void>>();
  final encontrados = await banco.execute(
    Sql.named('''
      SELECT id, nome, endereco, status, empresa_id
      FROM obra
      WHERE id = @id AND empresa_id = @empresa
      LIMIT 1
    '''),
    parameters: {'id': id, 'empresa': context.usuario.empresaId},
  );

  if (encontrados.isEmpty) {
    return _erro(HttpStatus.notFound, 'Obra nao encontrada.');
  }

  return Response.json(body: _obra(encontrados.first.toColumnMap()));
}

Future<Response> _editar(RequestContext context, int id) async {
  final Map<String, dynamic> corpo;
  try {
    corpo = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return _erro(HttpStatus.badRequest, 'Envie um JSON valido.');
  }

  final dados = corpo['obra'];
  if (dados is! Map<String, dynamic>) {
    return _erro(
      HttpStatus.badRequest,
      'Envie o objeto dentro da chave "obra".',
    );
  }

  final campos = <String, dynamic>{};
  final partes = <String>[];

  if (dados.containsKey('nome')) {
    final nome = validarNomeObra(dados['nome']);
    if (nome == null) {
      return _erro(HttpStatus.badRequest, 'Nome da obra invalido.');
    }
    campos['nome'] = nome;
    partes.add('nome = @nome');
  }

  if (dados.containsKey('endereco')) {
    final endereco = validarEnderecoObra(dados['endereco']);
    if (endereco == null) {
      return _erro(HttpStatus.badRequest, 'Endereco da obra invalido.');
    }
    campos['endereco'] = endereco;
    partes.add('endereco = @endereco');
  }

  if (dados.containsKey('status')) {
    final status = validarStatusObra(dados['status']);
    if (status == null) {
      return _erro(
        HttpStatus.badRequest,
        'Status invalido. Use planejamento, ativa, pausada ou concluida.',
      );
    }
    campos['status'] = status;
    partes.add('status = @status');
  }

  if (partes.isEmpty) {
    return _erro(
      HttpStatus.badRequest,
      'Informe campos validos para atualizar.',
    );
  }

  campos['id'] = id;
  campos['empresa'] = context.usuario.empresaId;
  final atualizado = await context.read<Pool<void>>().execute(
    Sql.named('''
      UPDATE obra
      SET ${partes.join(', ')}
      WHERE id = @id AND empresa_id = @empresa
      RETURNING id, nome, endereco, status, empresa_id
    '''),
    parameters: campos,
  );

  if (atualizado.isEmpty) {
    return _erro(HttpStatus.notFound, 'Obra nao encontrada.');
  }

  return Response.json(body: _obra(atualizado.first.toColumnMap()));
}

Map<String, dynamic> _obra(Map<String, dynamic> obra) => {
  'id': obra['id'],
  'nome': obra['nome'],
  'endereco': obra['endereco'],
  'status': obra['status'],
  'empresa_id': obra['empresa_id'],
};

Response _erro(int status, String mensagem) =>
    Response.json(statusCode: status, body: {'erro': mensagem});
