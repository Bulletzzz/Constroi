import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/senha.dart';
import 'package:constroi_api/usuarios.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  switch (context.request.method) {
    case HttpMethod.get:
      return _listar(context);
    case HttpMethod.post:
      return _criar(context);
    default:
      return Response(statusCode: HttpStatus.methodNotAllowed);
  }
}

Future<Response> _listar(RequestContext context) async {
  final banco = context.read<Pool<void>>();
  final empresaId = context.usuario.empresaId;

  final linhas = await banco.execute(
    Sql.named('''
      SELECT id, nome, email, tipo, ativo, criado_em, atualizado_em
      FROM usuario
      WHERE empresa_id = @empresa
      ORDER BY nome, id
    '''),
    parameters: {'empresa': empresaId},
  );

  final usuarios = linhas
      .map((linha) => linha.toColumnMap())
      .map(
        (usuario) => {
          'id': usuario['id'],
          'nome': usuario['nome'],
          'email': usuario['email'],
          'tipo': usuario['tipo'],
          'ativo': usuario['ativo'],
          'criado_em': usuario['criado_em']?.toIso8601String(),
          'atualizado_em': usuario['atualizado_em']?.toIso8601String(),
        },
      )
      .toList();

  return Response.json(body: {'usuarios': usuarios});
}

Future<Response> _criar(RequestContext context) async {
  final banco = context.read<Pool<void>>();

  final Map<String, dynamic> corpo;
  try {
    corpo = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return _erro(HttpStatus.badRequest, 'Envie um JSON valido.');
  }

  final dados = corpo['usuario'] is Map<String, dynamic>
      ? corpo['usuario'] as Map<String, dynamic>
      : corpo;

  final nome = ((dados['nome'] as String?) ?? '').trim();
  final email = ((dados['email'] as String?) ?? '').trim();
  final senha = (dados['senha'] as String?) ?? '';
  final tipo = validarTipoUsuario((dados['tipo'] as String?) ?? '');

  if (nome.isEmpty || email.isEmpty || senha.isEmpty) {
    return _erro(
      HttpStatus.badRequest,
      'Informe nome, email e senha do usuario.',
    );
  }

  if (tipo == null) {
    return _erro(
      HttpStatus.badRequest,
      'Tipo invalido. Use pedreiro, engenheiro ou master.',
    );
  }

  if (nome.length > 150) {
    return _erro(
      HttpStatus.badRequest,
      'Nome do usuario deve ter ate 150 caracteres.',
    );
  }

  if (email.length > 150 || !email.contains('@') || !email.contains('.')) {
    return _erro(HttpStatus.badRequest, 'Email invalido.');
  }

  if (senha.length < 6) {
    return _erro(
      HttpStatus.badRequest,
      'A senha deve ter no minimo 6 caracteres.',
    );
  }

  final emailExistente = await banco.execute(
    Sql.named('''
      SELECT id
      FROM usuario
      WHERE LOWER(email) = LOWER(@email)
      LIMIT 1
    '''),
    parameters: {'email': email},
  );

  if (emailExistente.isNotEmpty) {
    return _erro(HttpStatus.conflict, 'Email ja cadastrado.');
  }

  final empresaId = context.usuario.empresaId;
  final resultado = await banco.execute(
    Sql.named('''
      INSERT INTO usuario (empresa_id, nome, email, senha_hash, tipo)
      VALUES (@empresa, @nome, @email, @senhaHash, @tipo)
      RETURNING id, nome, email, tipo, ativo
    '''),
    parameters: {
      'empresa': empresaId,
      'nome': nome,
      'email': email,
      'senhaHash': gerarHash(senha),
      'tipo': tipo,
    },
  );

  final linha = resultado.first.toColumnMap();
  return Response.json(
    statusCode: HttpStatus.created,
    body: {
      'id': linha['id'],
      'nome': linha['nome'],
      'email': linha['email'],
      'tipo': linha['tipo'],
      'ativo': linha['ativo'],
      'empresa_id': empresaId,
    },
  );
}

Response _erro(int status, String mensagem) =>
    Response.json(statusCode: status, body: {'erro': mensagem});
