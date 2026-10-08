import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/senha.dart';
import 'package:constroi_api/usuarios.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context, String idDaRota) async {
  final id = int.tryParse(idDaRota);
  if (id == null) {
    return _erro(HttpStatus.badRequest, 'Id do usuario invalido.');
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
      SELECT id, nome, email, tipo, ativo, empresa_id, criado_em, atualizado_em
      FROM usuario
      WHERE id = @id AND empresa_id = @empresa
      LIMIT 1
    '''),
    parameters: {'id': id, 'empresa': empresaId},
  );

  if (encontrados.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'erro': 'Usuario nao encontrado.'},
    );
  }

  final usuario = encontrados.first.toColumnMap();
  final criadoEm = usuario['criado_em'] as DateTime?;
  final atualizadoEm = usuario['atualizado_em'] as DateTime?;
  return Response.json(
    body: {
      'id': usuario['id'],
      'nome': usuario['nome'],
      'email': usuario['email'],
      'tipo': usuario['tipo'],
      'ativo': usuario['ativo'],
      'empresa_id': usuario['empresa_id'],
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

  final dados = corpo['usuario'];
  if (dados is! Map<String, dynamic>) {
    return _erro(
      HttpStatus.badRequest,
      'Envie o objeto dentro da chave "usuario".',
    );
  }

  final nome = (dados['nome'] as String?)?.trim();
  final email = (dados['email'] as String?)?.trim();
  final senha = dados['senha'] as String?;
  final tipo = validarTipoUsuario(dados['tipo'] as String?);
  final ativo = dados['ativo'] is bool ? dados['ativo'] as bool : null;

  if (nome == null &&
      email == null &&
      senha == null &&
      tipo == null &&
      ativo == null) {
    return _erro(
      HttpStatus.badRequest,
      'Informe pelo menos um campo para atualizar.',
    );
  }

  final campos = <String, dynamic>{};
  final partes = <String>[];

  if (nome != null) {
    if (nome.isEmpty) {
      return _erro(HttpStatus.badRequest, 'Nome nao pode ficar vazio.');
    }
    if (nome.length > 150) {
      return _erro(
        HttpStatus.badRequest,
        'Nome do usuario deve ter ate 150 caracteres.',
      );
    }
    campos['nome'] = nome;
    partes.add('nome = @nome');
  }

  if (email != null) {
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      return _erro(HttpStatus.badRequest, 'Email invalido.');
    }
    if (email.length > 150) {
      return _erro(HttpStatus.badRequest, 'Email invalido.');
    }

    final emailEmUso = await banco.execute(
      Sql.named('''
        SELECT id
        FROM usuario
        WHERE LOWER(email) = LOWER(@email)
          AND id != @id
          AND empresa_id = @empresa
        LIMIT 1
      '''),
      parameters: {'email': email, 'id': id, 'empresa': empresaId},
    );

    if (emailEmUso.isNotEmpty) {
      return _erro(
        HttpStatus.conflict,
        'Email ja cadastrado para esta empresa.',
      );
    }

    campos['email'] = email;
    partes.add('email = @email');
  }

  if (senha != null) {
    final erroSenha = erroDaSenha(senha);
    if (erroSenha != null) {
      return _erro(HttpStatus.badRequest, erroSenha);
    }
    campos['senhaHash'] = gerarHash(senha);
    partes.add('senha_hash = @senhaHash');
  }

  if (tipo != null) {
    campos['tipo'] = tipo;
    partes.add('tipo = @tipo');
  }

  if (ativo != null) {
    campos['ativo'] = ativo;
    partes.add('ativo = @ativo');
  }

  partes.add('atualizado_em = CURRENT_TIMESTAMP');
  campos['id'] = id;
  campos['empresa'] = empresaId;

  final atualizado = await banco.execute(
    Sql.named('''
      UPDATE usuario
      SET ${partes.join(', ')}
      WHERE id = @id AND empresa_id = @empresa
      RETURNING id, nome, email, tipo, ativo, empresa_id, criado_em, atualizado_em
    '''),
    parameters: campos,
  );

  if (atualizado.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {'erro': 'Usuario nao encontrado.'},
    );
  }

  final usuario = atualizado.first.toColumnMap();
  final criadoEm = usuario['criado_em'] as DateTime?;
  final atualizadoEm = usuario['atualizado_em'] as DateTime?;
  return Response.json(
    body: {
      'id': usuario['id'],
      'nome': usuario['nome'],
      'email': usuario['email'],
      'tipo': usuario['tipo'],
      'ativo': usuario['ativo'],
      'empresa_id': usuario['empresa_id'],
      'criado_em': criadoEm?.toIso8601String(),
      'atualizado_em': atualizadoEm?.toIso8601String(),
    },
  );
}

Response _erro(int status, String mensagem) =>
    Response.json(statusCode: status, body: {'erro': mensagem});
