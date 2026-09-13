import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/produtos.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  final id = _idDaRota(context);
  if (id == null) {
    return Response(
      statusCode: HttpStatus.badRequest,
      body: 'Id do produto ausente.',
    );
  }

  switch (context.request.method) {
    case HttpMethod.get:
      return _buscar(context, id);
    case HttpMethod.patch:
      return _editar(context, id);
    default:
      return Response(statusCode: HttpStatus.methodNotAllowed);
  }
}

Future<Response> _buscar(RequestContext context, int id) async {
  final banco = context.read<Pool<void>>();
  final empresaId = context.usuario.empresaId;

  final encontrados = await banco.execute(
    Sql.named('''
      SELECT id, nome, unidade, empresa_id, criado_em, atualizado_em
      FROM produto
      WHERE id = @id AND empresa_id = @empresa
      LIMIT 1
    '''),
    parameters: {'id': id, 'empresa': empresaId},
  );

  if (encontrados.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'erro': 'Produto nao encontrado.'},
    );
  }

  final produto = encontrados.first.toColumnMap();
  return Response.json(
    body: {
      'id': produto['id'],
      'nome': produto['nome'],
      'unidade': produto['unidade'],
      'empresa_id': produto['empresa_id'],
      'criado_em': produto['criado_em']?.toIso8601String(),
      'atualizado_em': produto['atualizado_em']?.toIso8601String(),
    },
  );
}

Future<Response> _editar(RequestContext context, int id) async {
  final banco = context.read<Pool<void>>();
  final empresaId = context.usuario.empresaId;

  final Map<String, dynamic> corpo;
  try {
    corpo = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return _erro(HttpStatus.badRequest, 'Envie um JSON valido.');
  }

  final dados = corpo['produto'] is Map<String, dynamic>
      ? corpo['produto'] as Map<String, dynamic>
      : corpo;

  final nome = validarNomeProduto(dados['nome'] as String?);
  final unidade = validarUnidadeProduto(dados['unidade'] as String?);

  if (nome == null && unidade == null) {
    return _erro(
      HttpStatus.badRequest,
      'Informe nome ou unidade para atualizar.',
    );
  }

  final campos = <String, dynamic>{};
  final partes = <String>[];

  if (nome != null) {
    final jaExiste = await banco.execute(
      Sql.named('''
        SELECT id
        FROM produto
        WHERE empresa_id = @empresa
          AND LOWER(nome) = LOWER(@nome)
          AND id != @id
        LIMIT 1
      '''),
      parameters: {'empresa': empresaId, 'nome': nome, 'id': id},
    );

    if (jaExiste.isNotEmpty) {
      return _erro(
        HttpStatus.conflict,
        'Ja existe um produto com esse nome nesta empresa.',
      );
    }

    campos['nome'] = nome;
    partes.add('nome = @nome');
  }

  if (unidade != null) {
    campos['unidade'] = unidade;
    partes.add('unidade = @unidade');
  }

  partes.add('atualizado_em = CURRENT_TIMESTAMP');
  campos['id'] = id;
  campos['empresa'] = empresaId;

  final atualizado = await banco.execute(
    Sql.named('''
      UPDATE produto
      SET ${partes.join(', ')}
      WHERE id = @id AND empresa_id = @empresa
      RETURNING id, nome, unidade, empresa_id, criado_em, atualizado_em
    '''),
    parameters: campos,
  );

  if (atualizado.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'erro': 'Produto nao encontrado.'},
    );
  }

  final produto = atualizado.first.toColumnMap();
  return Response.json(
    body: {
      'id': produto['id'],
      'nome': produto['nome'],
      'unidade': produto['unidade'],
      'empresa_id': produto['empresa_id'],
      'criado_em': produto['criado_em']?.toIso8601String(),
      'atualizado_em': produto['atualizado_em']?.toIso8601String(),
    },
  );
}

int? _idDaRota(RequestContext context) {
  final segmentos = context.request.uri.pathSegments;
  if (segmentos.isEmpty) return null;
  return int.tryParse(segmentos.last);
}

Response _erro(int status, String mensagem) =>
    Response.json(statusCode: status, body: {'erro': mensagem});
