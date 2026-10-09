import 'package:flutter/material.dart';

import '../navigation/app_bottom_navigation.dart';
import '../navigation/app_route.dart';
import '../navigation/perfil_usuario.dart';
import '../widgets/app_header.dart';
import '../widgets/base_card.dart';

class ModuleScreen extends StatelessWidget {
  const ModuleScreen({super.key, required this.rota, required this.perfil});

  final AppRoute rota;
  final PerfilUsuario perfil;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppHeader(perfil: perfil),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: BaseCard(
            child: Text('Módulo ${rota.rotulo} pronto para receber a tela.'),
          ),
        ),
      ),
    ),
    bottomNavigationBar: AppBottomNavigation(rotaAtual: rota, perfil: perfil),
  );
}
