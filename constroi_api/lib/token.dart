import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

/// Validade do token de acesso devolvido no login.
const duracaoDoToken = Duration(hours: 8);

/// Validade da sessao gravada em sessao_usuario.
const duracaoDaSessao = Duration(days: 30);

final _sorteio = Random.secure();

/// Assina o token de acesso com os dados que as rotas precisam conferir.
String gerarToken({
  required String segredo,
  required int usuarioId,
  required int empresaId,
  required String tipo,
}) {
  final jwt = JWT(
    {'empresa_id': empresaId, 'tipo': tipo},
    subject: '$usuarioId',
    issuer: 'constroi-api',
  );
  return jwt.sign(SecretKey(segredo), expiresIn: duracaoDoToken);
}

/// Sorteia o refresh token que vai para o cliente em texto puro.
String gerarRefreshToken() {
  final bytes = List<int>.generate(32, (_) => _sorteio.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// SHA-256 em hexa, que e o formato CHAR(64) das tabelas de sessao e tentativa.
String resumir(String valor) => sha256.convert(utf8.encode(valor)).toString();
