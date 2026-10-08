import 'package:flutter/material.dart';

import '../navigation/app_bottom_navigation.dart';
import '../navigation/app_route.dart';
import '../navigation/perfil_usuario.dart';
import 'app_header.dart';
import 'base_card.dart';

class AppHome extends StatelessWidget {
  const AppHome({super.key, this.perfil});

  final PerfilUsuario? perfil;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const AppHeader(title: 'PAINEL'),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: BaseCard(child: Text('Acompanhe suas obras em um só lugar.')),
        ),
      ),
    ),
    bottomNavigationBar: perfil == null
        ? null
        : AppBottomNavigation(rotaAtual: AppRoute.painel, perfil: perfil!),
  );
}
