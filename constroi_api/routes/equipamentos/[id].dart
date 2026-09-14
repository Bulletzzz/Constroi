import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/equipamentos.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context, String idDaRota) async {
  final id = int.tryParse(idDaRota);
  if (id == null) {
    return _erro(HttpStatus.badRequest, 'Id do equipamento invalido.');
  }

  final metodo = context.request.method;
  if (metodo == HttpMethod.get) {
    return _buscar(context, id);
  }
  if (metodo == HttpMethod.patch) {
    return _editar(context, id);
  }
  return Response(statusCode: HttpStatus.methodNotAllowed);
}

Future<Response> _buscar(RequestContext context, int id) async {
  final banco = context.read<Pool<void>>();
  final empresaId = context.usuario.empresaId;

  final encontrados = await banco.execute(
    Sql.named('''
      SELECT id, nome, patrimonio, status, empresa_id, criado_em, atualizado_em
      FROM equipamento
      WHERE id = @id AND empresa_id = @empresa
      LIMIT 1
    '''),
    parameters: {'id': id, 'empresa': empresaId},
  );

  if (encontrados.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'erro': 'Equipamento nao encontrado.'},
    );
  }

  final equipamento = encontrados.first.toColumnMap();
  final criadoEm = equipamento['criado_em'] as DateTime?;
  final atualizadoEm = equipamento['atualizado_em'] as DateTime?;
  return Response.json(
    body: {
      'id': equipamento['id'],
      'nome': equipamento['nome'],
      'patrimonio': equipamento['patrimonio'],
      'status': equipamento['status'],
      'empresa_id': equipamento['empresa_id'],
      'criado_em': criadoEm?.toIso8601String(),
      'atualizado_em': atualizadoEm?.toIso8601String(),
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

  final dados = corpo['equipamento'];
  if (dados is! Map<String, dynamic>) {
    return _erro(
      HttpStatus.badRequest,
      'Envie o objeto dentro da chave "equipamento".',
    );
  }

  final nome = validarNomeEquipamento(dados['nome'] as String?);
  final patrimonio = validarPatrimonio(dados['patrimonio'] as String?);
  final status = validarStatusEquipamento(dados['status'] as String?);

  if (nome == null && patrimonio == null && status == null) {
    return _erro(
      HttpStatus.badRequest,
      'Informe nome, patrimonio ou status para atualizar.',
    );
  }

  final campos = <String, dynamic>{};
  final partes = <String>[];

  if (nome != null) {
    campos['nome'] = nome;
    partes.add('nome = @nome');
  }

  if (patrimonio != null) {
    final jaExiste = await banco.execute(
      Sql.named('''
        SELECT id
        FROM equipamento
        WHERE empresa_id = @empresa
          AND patrimonio = @patrimonio
          AND id != @id
        LIMIT 1
      '''),
      parameters: {'empresa': empresaId, 'patrimonio': patrimonio, 'id': id},
    );

    if (jaExiste.isNotEmpty) {
      return _erro(
        HttpStatus.conflict,
        'Ja existe um equipamento com este numero de patrimonio nesta empresa.',
      );
    }

    campos['patrimonio'] = patrimonio;
    partes.add('patrimonio = @patrimonio');
  }

  if (status != null) {
    campos['status'] = status;
    partes.add('status = @status');
  }

  partes.add('atualizado_em = CURRENT_TIMESTAMP');
  campos['id'] = id;
  campos['empresa'] = empresaId;

  final atualizado = await banco.execute(
    Sql.named('''
      UPDATE equipamento
      SET ${partes.join(', ')}
      WHERE id = @id AND empresa_id = @empresa
      RETURNING id, nome, patrimonio, status, empresa_id, criado_em, atualizado_em
    '''),
    parameters: campos,
  );

  if (atualizado.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'erro': 'Equipamento nao encontrado.'},
    );
  }

  final equipamento = atualizado.first.toColumnMap();
  final criadoEm = equipamento['criado_em'] as DateTime?;
  final atualizadoEm = equipamento['atualizado_em'] as DateTime?;
  return Response.json(
    body: {
      'id': equipamento['id'],
      'nome': equipamento['nome'],
      'patrimonio': equipamento['patrimonio'],
      'status': equipamento['status'],
      'empresa_id': equipamento['empresa_id'],
      'criado_em': criadoEm?.toIso8601String(),
      'atualizado_em': atualizadoEm?.toIso8601String(),
    },
  );
}

Response _erro(int status, String mensagem) =>
    Response.json(statusCode: status, body: {'erro': mensagem});
