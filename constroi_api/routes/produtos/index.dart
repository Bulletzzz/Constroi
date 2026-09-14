import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/produtos.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  final metodo = context.request.method;
  if (metodo == HttpMethod.get) {
    return _listar(context);
  }
  if (metodo == HttpMethod.post) {
    return _criar(context);
  }
  return Response(statusCode: HttpStatus.methodNotAllowed);
}

Future<Response> _listar(RequestContext context) async {
  final banco = context.read<Pool<void>>();
  final empresaId = context.usuario.empresaId;

  final linhas = await banco.execute(
    Sql.named('''
      SELECT id, nome, unidade, empresa_id, criado_em, atualizado_em
      FROM produto
      WHERE empresa_id = @empresa
      ORDER BY nome, id
    '''),
    parameters: {'empresa': empresaId},
  );

  final produtos = linhas.map((linha) => linha.toColumnMap()).map((produto) {
    final id = produto['id'] as int?;
    final nome = produto['nome'] as String?;
    final unidade = produto['unidade'] as String?;
    final empresaId = produto['empresa_id'] as int?;
    final criadoEm = produto['criado_em'] as DateTime?;
    final atualizadoEm = produto['atualizado_em'] as DateTime?;

    return {
      'id': id,
      'nome': nome,
      'unidade': unidade,
      'empresa_id': empresaId,
      'criado_em': criadoEm?.toIso8601String(),
      'atualizado_em': atualizadoEm?.toIso8601String(),
    };
  }).toList();

  return Response.json(body: {'produtos': produtos});
}

Future<Response> _criar(RequestContext context) async {
  final banco = context.read<Pool<void>>();

  final Map<String, dynamic> corpo;
  try {
    corpo = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return _erro(HttpStatus.badRequest, 'Envie um JSON valido.');
  }

  final dados = corpo['produto'];
  if (dados is! Map<String, dynamic>) {
    return _erro(HttpStatus.badRequest, 'Envie um JSON valido.');
  }

  final nome = validarNomeProduto(dados['nome'] as String?);
  final unidade = validarUnidadeProduto(dados['unidade'] as String?);

  if (nome == null || unidade == null) {
    return _erro(
      HttpStatus.badRequest,
      'Informe nome e unidade validos do produto.',
    );
  }

  final empresaId = context.usuario.empresaId;
  final jaExiste = await banco.execute(
    Sql.named('''
      SELECT id
      FROM produto
      WHERE empresa_id = @empresa AND LOWER(nome) = LOWER(@nome)
      LIMIT 1
    '''),
    parameters: {'empresa': empresaId, 'nome': nome},
  );

  if (jaExiste.isNotEmpty) {
    return _erro(
      HttpStatus.conflict,
      'Produto ja cadastrado para esta empresa.',
    );
  }

  final resultado = await banco.execute(
    Sql.named('''
      INSERT INTO produto (empresa_id, nome, unidade)
      VALUES (@empresa, @nome, @unidade)
      RETURNING id, nome, unidade, empresa_id
    '''),
    parameters: {
      'empresa': empresaId,
      'nome': nome,
      'unidade': unidade,
    },
  );

  final linha = resultado.first.toColumnMap();
  return Response.json(
    statusCode: HttpStatus.created,
    body: {
      'id': linha['id'],
      'nome': linha['nome'],
      'unidade': linha['unidade'],
      'empresa_id': linha['empresa_id'],
    },
  );
}

Response _erro(int status, String mensagem) =>
    Response.json(statusCode: status, body: {'erro': mensagem});
