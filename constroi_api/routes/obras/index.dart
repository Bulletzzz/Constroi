import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/obras.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  final metodo = context.request.method;
  if (metodo == HttpMethod.get) return _listar(context);
  if (metodo == HttpMethod.post) return _criar(context);
  return Response(statusCode: HttpStatus.methodNotAllowed);
}

Future<Response> _listar(RequestContext context) async {
  final banco = context.read<Pool<void>>();
  final empresaId = context.usuario.empresaId;
  final linhas = await banco.execute(
    Sql.named('''
      SELECT id, nome, endereco, status, empresa_id
      FROM obra
      WHERE empresa_id = @empresa
      ORDER BY nome, id
    '''),
    parameters: {'empresa': empresaId},
  );

  final obras = linhas.map((linha) => linha.toColumnMap()).map((obra) {
    return {
      'id': obra['id'],
      'nome': obra['nome'],
      'endereco': obra['endereco'],
      'status': obra['status'],
      'empresa_id': obra['empresa_id'],
    };
  }).toList();

  return Response.json(body: {'obras': obras});
}

Future<Response> _criar(RequestContext context) async {
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

  final nome = validarNomeObra(dados['nome']);
  final endereco = validarEnderecoObra(dados['endereco']);
  final status = validarStatusObra(dados['status']);
  if (nome == null || endereco == null || status == null) {
    return _erro(
      HttpStatus.badRequest,
      'Informe nome, endereco e status validos da obra.',
    );
  }

  final empresaId = context.usuario.empresaId;
  final banco = context.read<Pool<void>>();
  final resultado = await banco.execute(
    Sql.named('''
      INSERT INTO obra (empresa_id, nome, endereco, status)
      VALUES (@empresa, @nome, @endereco, @status)
      RETURNING id, nome, endereco, status, empresa_id
    '''),
    parameters: {
      'empresa': empresaId,
      'nome': nome,
      'endereco': endereco,
      'status': status,
    },
  );

  final obra = resultado.first.toColumnMap();
  return Response.json(
    statusCode: HttpStatus.created,
    body: {
      'id': obra['id'],
      'nome': obra['nome'],
      'endereco': obra['endereco'],
      'status': obra['status'],
      'empresa_id': obra['empresa_id'],
    },
  );
}

Response _erro(int status, String mensagem) =>
    Response.json(statusCode: status, body: {'erro': mensagem});
