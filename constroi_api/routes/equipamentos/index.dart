import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/equipamentos.dart';
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
      SELECT id, nome, patrimonio, status, empresa_id, criado_em, atualizado_em
      FROM equipamento
      WHERE empresa_id = @empresa
      ORDER BY nome, id
    '''),
    parameters: {'empresa': empresaId},
  );

  final equipamentos = linhas.map((linha) => linha.toColumnMap()).map((
    equipamento,
  ) {
    final id = equipamento['id'] as int?;
    final nome = equipamento['nome'] as String?;
    final patrimonio = equipamento['patrimonio'] as String?;
    final status = equipamento['status'] as String?;
    final empresaId = equipamento['empresa_id'] as int?;
    final criadoEm = equipamento['criado_em'] as DateTime?;
    final atualizadoEm = equipamento['atualizado_em'] as DateTime?;

    return {
      'id': id,
      'nome': nome,
      'patrimonio': patrimonio,
      'status': status,
      'empresa_id': empresaId,
      'criado_em': criadoEm?.toIso8601String(),
      'atualizado_em': atualizadoEm?.toIso8601String(),
    };
  }).toList();

  return Response.json(body: {'equipamentos': equipamentos});
}

Future<Response> _criar(RequestContext context) async {
  final banco = context.read<Pool<void>>();

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

  if (nome == null || patrimonio == null || status == null) {
    return _erro(
      HttpStatus.badRequest,
      'Informe nome, patrimonio e status validos do equipamento.',
    );
  }

  final empresaId = context.usuario.empresaId;

  final jaExistePatrimonio = await banco.execute(
    Sql.named('''
      SELECT id
      FROM equipamento
      WHERE empresa_id = @empresa AND patrimonio = @patrimonio
      LIMIT 1
    '''),
    parameters: {'empresa': empresaId, 'patrimonio': patrimonio},
  );

  if (jaExistePatrimonio.isNotEmpty) {
    return _erro(
      HttpStatus.conflict,
      'Ja existe um equipamento com este numero de patrimonio nesta empresa.',
    );
  }

  final resultado = await banco.execute(
    Sql.named('''
      INSERT INTO equipamento (empresa_id, nome, patrimonio, status)
      VALUES (@empresa, @nome, @patrimonio, @status)
      RETURNING id, nome, patrimonio, status, empresa_id
    '''),
    parameters: {
      'empresa': empresaId,
      'nome': nome,
      'patrimonio': patrimonio,
      'status': status,
    },
  );

  final linha = resultado.first.toColumnMap();
  return Response.json(
    statusCode: HttpStatus.created,
    body: {
      'id': linha['id'],
      'nome': linha['nome'],
      'patrimonio': linha['patrimonio'],
      'status': linha['status'],
      'empresa_id': linha['empresa_id'],
    },
  );
}

Response _erro(int status, String mensagem) =>
    Response.json(statusCode: status, body: {'erro': mensagem});
