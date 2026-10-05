import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context, String idDaRota) async {
  final obraId = int.tryParse(idDaRota);
  if (obraId == null || obraId < 1) {
    return _erro(HttpStatus.badRequest, 'Id da obra invalido.');
  }

  if (context.request.method == HttpMethod.get) {
    return _listar(context, obraId);
  }
  if (context.request.method == HttpMethod.post) {
    return _criar(context, obraId);
  }
  return Response(statusCode: HttpStatus.methodNotAllowed);
}

Future<Response> _listar(RequestContext context, int obraId) async {
  final banco = context.read<Pool<void>>();
  final empresaId = context.usuario.empresaId;
  final obra = await banco.execute(
    Sql.named('''
      SELECT id
      FROM obra
      WHERE id = @obra AND empresa_id = @empresa
      LIMIT 1
    '''),
    parameters: {'obra': obraId, 'empresa': empresaId},
  );

  if (obra.isEmpty) {
    return _erro(HttpStatus.notFound, 'Obra nao encontrada.');
  }

  final linhas = await banco.execute(
    Sql.named('''
      SELECT uo.id AS vinculo_id, u.id AS usuario_id, u.nome, u.email, u.tipo,
             uo.data_inicio
      FROM usuario_obra AS uo
      JOIN usuario AS u ON u.id = uo.usuario_id
      WHERE uo.obra_id = @obra
        AND uo.empresa_id = @empresa
        AND uo.data_fim IS NULL
      ORDER BY u.nome, u.id
    '''),
    parameters: {'obra': obraId, 'empresa': empresaId},
  );

  final equipe = linhas.map((linha) {
    final dados = linha.toColumnMap();
    final dataInicio = dados['data_inicio'] as DateTime?;
    return {
      'vinculo_id': dados['vinculo_id'],
      'usuario_id': dados['usuario_id'],
      'nome': dados['nome'],
      'email': dados['email'],
      'tipo': dados['tipo'],
      'data_inicio': dataInicio?.toIso8601String(),
    };
  }).toList();

  return Response.json(body: {'equipe': equipe});
}

Future<Response> _criar(RequestContext context, int obraId) async {
  final Map<String, dynamic> corpo;
  try {
    corpo = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return _erro(HttpStatus.badRequest, 'Envie um JSON valido.');
  }

  final dados = corpo['equipe'];
  if (dados is! Map<String, dynamic>) {
    return _erro(
      HttpStatus.badRequest,
      'Envie o objeto dentro da chave "equipe".',
    );
  }

  final usuarioId = dados['usuario_id'];
  if (usuarioId is! int || usuarioId < 1) {
    return _erro(HttpStatus.badRequest, 'Id do usuario invalido.');
  }

  final banco = context.read<Pool<void>>();
  final empresaId = context.usuario.empresaId;
  final obra = await banco.execute(
    Sql.named('''
      SELECT id
      FROM obra
      WHERE id = @obra AND empresa_id = @empresa
      LIMIT 1
    '''),
    parameters: {'obra': obraId, 'empresa': empresaId},
  );

  if (obra.isEmpty) {
    return _erro(HttpStatus.notFound, 'Obra nao encontrada.');
  }

  final usuario = await banco.execute(
    Sql.named('''
      SELECT empresa_id
      FROM usuario
      WHERE id = @usuario
      LIMIT 1
    '''),
    parameters: {'usuario': usuarioId},
  );

  if (usuario.isEmpty) {
    return _erro(HttpStatus.notFound, 'Usuario nao encontrado.');
  }

  final empresaDoUsuario = usuario.first.toColumnMap()['empresa_id'] as int;
  if (empresaDoUsuario != empresaId) {
    return _erro(
      HttpStatus.badRequest,
      'Usuario e obra devem pertencer a mesma empresa.',
    );
  }

  final criado = await banco.execute(
    Sql.named('''
      INSERT INTO usuario_obra (empresa_id, usuario_id, obra_id)
      VALUES (@empresa, @usuario, @obra)
      ON CONFLICT (usuario_id, obra_id) WHERE data_fim IS NULL DO NOTHING
      RETURNING id, empresa_id, usuario_id, obra_id, data_inicio, data_fim
    '''),
    parameters: {
      'empresa': empresaId,
      'usuario': usuarioId,
      'obra': obraId,
    },
  );

  if (criado.isEmpty) {
    return _erro(
      HttpStatus.conflict,
      'Usuario ja possui vinculo ativo com esta obra.',
    );
  }

  final vinculo = criado.first.toColumnMap();
  final dataInicio = vinculo['data_inicio'] as DateTime?;
  return Response.json(
    statusCode: HttpStatus.created,
    body: {
      'id': vinculo['id'],
      'empresa_id': vinculo['empresa_id'],
      'usuario_id': vinculo['usuario_id'],
      'obra_id': vinculo['obra_id'],
      'data_inicio': dataInicio?.toIso8601String(),
      'data_fim': null,
    },
  );
}

Response _erro(int status, String mensagem) =>
    Response.json(statusCode: status, body: {'erro': mensagem});
