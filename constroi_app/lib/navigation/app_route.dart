import 'package:flutter/material.dart';

import 'perfil_usuario.dart';

enum AppRoute {
  painel('/painel', 'Painel', Icons.dashboard_outlined, PerfilUsuario.pedreiro),
  estoque(
    '/estoque',
    'Estoque',
    Icons.inventory_2_outlined,
    PerfilUsuario.pedreiro,
  ),
  custos(
    '/custos',
    'Custos',
    Icons.payments_outlined,
    PerfilUsuario.engenheiro,
  ),
  equipe('/equipe', 'Equipe', Icons.groups_outlined, PerfilUsuario.pedreiro),
  requisicoes(
    '/requisicoes',
    'Requisições',
    Icons.description_outlined,
    PerfilUsuario.pedreiro,
  );

  const AppRoute(this.caminho, this.rotulo, this.icone, this.perfilMinimo);

  final String caminho;
  final String rotulo;
  final IconData icone;
  final PerfilUsuario perfilMinimo;

  bool podeSerAcessadaPor(PerfilUsuario perfil) =>
      perfil.possuiNivel(perfilMinimo);

  static AppRoute? porCaminho(String? caminho) {
    for (final rota in values) {
      if (rota.caminho == caminho) return rota;
    }
    return null;
  }
}
