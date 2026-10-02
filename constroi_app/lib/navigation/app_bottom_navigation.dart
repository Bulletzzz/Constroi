import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_route.dart';
import 'perfil_usuario.dart';

class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    super.key,
    required this.rotaAtual,
    required this.perfil,
  });

  final AppRoute rotaAtual;
  final PerfilUsuario perfil;

  @override
  Widget build(BuildContext context) {
    final rotas = AppRoute.values
        .where((rota) => rota.podeSerAcessadaPor(perfil))
        .toList(growable: false);
    final indice = rotas.indexOf(rotaAtual);

    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      backgroundColor: const Color(0xFF111313),
      selectedItemColor: AppTheme.accent,
      unselectedItemColor: const Color(0xFFD1D1D1),
      selectedFontSize: 11,
      unselectedFontSize: 11,
      currentIndex: indice < 0 ? 0 : indice,
      onTap: (novoIndice) {
        final destino = rotas[novoIndice];
        if (destino != rotaAtual) {
          Navigator.of(context).pushReplacementNamed(destino.caminho);
        }
      },
      items: [
        for (final rota in rotas)
          BottomNavigationBarItem(
            icon: Icon(rota.icone),
            activeIcon: Icon(rota.icone, color: AppTheme.accent),
            label: rota.rotulo,
          ),
      ],
    );
  }
}
