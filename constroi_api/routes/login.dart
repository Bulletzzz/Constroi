import 'dart:io';

import 'package:constroi_api/ambiente.dart';
import 'package:constroi_api/logs.dart';
import 'package:constroi_api/senha.dart';
import 'package:constroi_api/token.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final segredo = variavel('JWT_SECRET');
  if (segredo == null) {
    return _erro(HttpStatus.serviceUnavailable, 'Servidor sem JWT_SECRET.');
  }

  final Map<String, dynamic> corpo;
  try {
    corpo = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return _erro(HttpStatus.badRequest, 'Envie um JSON com email e senha.');
  }

  final email = (corpo['email'] as String?)?.trim() ?? '';
  final senha = corpo['senha'] as String? ?? '';
  if (email.isEmpty || senha.isEmpty) {
    return _erro(HttpStatus.badRequest, 'Informe email e senha.');
  }

  final banco = context.read<Pool<void>>();
  final emailResumido = resumir(email.toLowerCase());
  final ip = context.request.headers['x-forwarded-for']
      ?.split(',')
      .first
      .trim();

  final encontrados = await banco.execute(
    Sql.named('''
      SELECT id, empresa_id, nome, email, tipo, senha_hash, ativo, bloqueado_ate, tentativas_login
      FROM usuario
      WHERE LOWER(email) = LOWER(@email)
      LIMIT 1
    '''),
    parameters: {'email': email},
  );

  if (encontrados.isEmpty) {
    gastarTempoDeComparacao(senha);
    await _registrarTentativa(banco, null, emailResumido, ip, false);
    return _credenciaisInvalidas();
  }

  final usuario = encontrados.first.toColumnMap();
  final usuarioId = usuario['id'] as int;
  // So revelar o estado da conta depois de validar a senha.
  final senhaValida = senhaConfere(senha, usuario['senha_hash'] as String);
  final agora = DateTime.now().toUtc();
  final bloqueadoAte = usuario['bloqueado_ate'] as DateTime?;
  final bloqueado = bloqueadoAte != null && bloqueadoAte.isAfter(agora);

  if (!senhaValida) {
    // Uma tentativa durante o bloqueio nao pode limpa-lo nem prolonga-lo.
    if (usuario['ativo'] != false && !bloqueado) {
      final bloqueadoExpirou =
          bloqueadoAte != null && !bloqueadoAte.isAfter(agora);
      final tentativas = bloqueadoExpirou
          ? 1
          : ((usuario['tentativas_login'] as int? ?? 0) + 1);
      final bloquear = tentativas >= 5;

      await banco.execute(
        Sql.named('''
          UPDATE usuario
          SET tentativas_login = @tentativas,
              bloqueado_ate = @bloqueadoAte,
              atualizado_em = CURRENT_TIMESTAMP
          WHERE id = @id
        '''),
        parameters: {
          'id': usuarioId,
          'tentativas': bloquear ? 0 : tentativas,
          'bloqueadoAte': bloquear
              ? agora.add(const Duration(minutes: 10))
              : null,
        },
      );
    }

    await _registrarTentativa(banco, usuarioId, emailResumido, ip, false);
    return _credenciaisInvalidas();
  }

  if (usuario['ativo'] == false) {
    await _registrarTentativa(banco, usuarioId, emailResumido, ip, false);
    return _erro(
      HttpStatus.forbidden,
      'Usuario inativo. Procure o administrador.',
    );
  }

  if (bloqueado) {
    await _registrarTentativa(banco, usuarioId, emailResumido, ip, false);
    return _erro(
      HttpStatus.tooManyRequests,
      'Muitas tentativas. Tente novamente mais tarde.',
    );
  }

  final refreshToken = gerarRefreshToken();
  final expiraEm = DateTime.now().toUtc().add(duracaoDaSessao);

  await banco.runTx<void>((transacao) async {
    await transacao.execute(
      Sql.named('''
        UPDATE usuario
        SET tentativas_login = 0,
            bloqueado_ate = NULL,
            ultimo_login_em = CURRENT_TIMESTAMP,
            atualizado_em = CURRENT_TIMESTAMP
        WHERE id = @id
      '''),
      parameters: {'id': usuarioId},
    );
    await transacao.execute(
      Sql.named('''
        INSERT INTO sessao_usuario
          (usuario_id, refresh_token_hash, expira_em, endereco_ip, user_agent)
        VALUES (@usuario, @hash, @expira, @ip, @agente)
      '''),
      parameters: {
        'usuario': usuarioId,
        'hash': resumir(refreshToken),
        'expira': expiraEm,
        'ip': ip,
        'agente': context.request.headers['user-agent'],
      },
    );
    await registrarLog(
      transacao,
      usuarioId: usuarioId,
      acao: 'LOGIN usuario=$usuarioId',
    );
  });

  await _registrarTentativa(banco, usuarioId, emailResumido, ip, true);

  return Response.json(
    body: {
      'token': gerarToken(
        segredo: segredo,
        usuarioId: usuarioId,
        empresaId: usuario['empresa_id'] as int,
        tipo: usuario['tipo'] as String,
      ),
      'expira_em': DateTime.now().toUtc().add(duracaoDoToken).toIso8601String(),
      'refresh_token': refreshToken,
      'usuario': {
        'id': usuarioId,
        'nome': usuario['nome'],
        'email': usuario['email'],
        'tipo': usuario['tipo'],
        'empresa_id': usuario['empresa_id'],
      },
    },
  );
}

Future<void> _registrarTentativa(
  Pool<void> banco,
  int? usuarioId,
  String emailResumido,
  String? ip,
  bool sucesso,
) async {
  await banco.execute(
    Sql.named('''
      INSERT INTO tentativa_login (usuario_id, email_hash, endereco_ip, sucesso)
      VALUES (@usuario, @email, @ip, @sucesso)
    '''),
    parameters: {
      'usuario': usuarioId,
      'email': emailResumido,
      'ip': ip,
      'sucesso': sucesso,
    },
  );
}

/// Mesma resposta para email inexistente e senha errada, para nao entregar
/// quais emails estao cadastrados.
Response _credenciaisInvalidas() =>
    _erro(HttpStatus.unauthorized, 'Email ou senha invalidos.');

Response _erro(int status, String mensagem) =>
    Response.json(statusCode: status, body: {'erro': mensagem});
