import 'dart:io';

import 'package:constroi_api/autenticacao.dart';
import 'package:dart_frog/dart_frog.dart';

Middleware exigirNivel(Nivel minimo) {
  return (handler) {
    return (context) async {
      final usuario = context.read<UsuarioAutenticado?>();

      if (usuario == null) {
        return _erro(
          HttpStatus.unauthorized,
          'Envie o token no cabecalho Authorization: Bearer <token>.',
        );
      }

      if (!usuario.nivel.alcanca(minimo)) {
        return _erro(
          HttpStatus.forbidden,
          'Esta acao e restrita ao perfil ${minimo.name} ou superior.',
        );
      }

      return handler(context);
    };
  };
}

Response _erro(int status, String mensagem) =>
    Response.json(statusCode: status, body: {'erro': mensagem});
