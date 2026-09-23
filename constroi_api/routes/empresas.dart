import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:constroi_api/senha.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final Map<String, dynamic> corpo;
  try {
    corpo = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return _erro(HttpStatus.badRequest, 'Envie um JSON valido.');
  }

  final dadosEmpresa = corpo['empresa'] is Map<String, dynamic>
      ? corpo['empresa'] as Map<String, dynamic>
      : null;
  final dadosUsuario = corpo['usuario'] is Map<String, dynamic>
      ? corpo['usuario'] as Map<String, dynamic>
      : null;

  final nomeEmpresa =
      ((dadosEmpresa?['nome'] ??
                  corpo['nome_empresa'] ??
                  corpo['empresa_nome'] ??
                  (dadosUsuario != null ? corpo['nome'] : null))
              as String?)
          ?.trim() ??
      '';

  final cnpj =
      ((dadosEmpresa?['cnpj'] ?? corpo['cnpj']) as String?)?.trim() ?? '';

  final nomeUsuario =
      ((dadosUsuario?['nome'] ??
                  corpo['nome_usuario'] ??
                  corpo['usuario_nome'] ??
                  corpo['nome'])
              as String?)
          ?.trim() ??
      '';

  final email =
      ((dadosUsuario?['email'] ??
                  corpo['email_usuario'] ??
                  corpo['usuario_email'] ??
                  corpo['email'])
              as String?)
          ?.trim() ??
      '';

  final senha =
      ((dadosUsuario?['senha'] ??
              corpo['senha_usuario'] ??
              corpo['usuario_senha'] ??
              corpo['senha'])
          as String?) ??
      '';

  if (nomeEmpresa.isEmpty || cnpj.isEmpty) {
    return _erro(HttpStatus.badRequest, 'Informe o nome da empresa e o CNPJ.');
  }

  if (nomeEmpresa.length > 150) {
    return _erro(
      HttpStatus.badRequest,
      'Nome da empresa deve ter no maximo 150 caracteres.',
    );
  }

  if (cnpj.length > 18) {
    return _erro(
      HttpStatus.badRequest,
      'CNPJ deve ter no maximo 18 caracteres.',
    );
  }

  if (nomeUsuario.isEmpty || email.isEmpty || senha.isEmpty) {
    return _erro(
      HttpStatus.badRequest,
      'Informe o nome, email e senha do usuario master.',
    );
  }

  if (nomeUsuario.length > 150) {
    return _erro(
      HttpStatus.badRequest,
      'Nome do usuario muito longo.',
    );
  }

  if (email.length > 150 || !email.contains('@') || !email.contains('.')) {
    return _erro(HttpStatus.badRequest, 'Email invalido.');
  }

  final erroSenha = erroDaSenha(senha);
  if (erroSenha != null) {
    return _erro(HttpStatus.badRequest, erroSenha);
  }

  final banco = context.read<Pool<void>>();

  final cnpjExistente = await banco.execute(
    Sql.named('SELECT id FROM empresa WHERE cnpj = @cnpj LIMIT 1'),
    parameters: {'cnpj': cnpj},
  );
  if (cnpjExistente.isNotEmpty) {
    return _erro(HttpStatus.conflict, 'CNPJ ja cadastrado.');
  }

  final emailExistente = await banco.execute(
    Sql.named(
      'SELECT id FROM usuario WHERE LOWER(email) = LOWER(@email) LIMIT 1',
    ),
    parameters: {'email': email},
  );
  if (emailExistente.isNotEmpty) {
    return _erro(HttpStatus.conflict, 'Email ja cadastrado.');
  }

  final resultado = await banco.runTx((transacao) async {
    final empresaRes = await transacao.execute(
      Sql.named('''
        INSERT INTO empresa (nome, cnpj)
        VALUES (@nome, @cnpj)
        RETURNING id, nome, cnpj
      '''),
      parameters: {'nome': nomeEmpresa, 'cnpj': cnpj},
    );

    final empresaId = empresaRes.first[0]! as int;

    final usuarioRes = await transacao.execute(
      Sql.named('''
        INSERT INTO usuario (empresa_id, nome, email, senha_hash, tipo)
        VALUES (@empresa, @nome, @email, @senhaHash, @tipo)
        RETURNING id, nome, email, tipo
      '''),
      parameters: {
        'empresa': empresaId,
        'nome': nomeUsuario,
        'email': email,
        'senhaHash': gerarHash(senha),
        'tipo': Nivel.master.name,
      },
    );

    final usuarioId = usuarioRes.first[0]! as int;

    return {
      'empresa': {
        'id': empresaId,
        'nome': nomeEmpresa,
        'cnpj': cnpj,
      },
      'usuario': {
        'id': usuarioId,
        'nome': nomeUsuario,
        'email': email,
        'tipo': Nivel.master.name,
        'empresa_id': empresaId,
      },
    };
  });

  return Response.json(
    statusCode: HttpStatus.created,
    body: resultado,
  );
}

Response _erro(int status, String mensagem) =>
    Response.json(statusCode: status, body: {'erro': mensagem});
