import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../navigation/perfil_usuario.dart';
import '../theme/app_theme.dart';

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppHeader({super.key, this.perfil, this.onSair});

  final PerfilUsuario? perfil;
  final VoidCallback? onSair;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) => AppBar(
    backgroundColor: AppTheme.background,
    foregroundColor: Colors.white,
    toolbarHeight: 64,
    centerTitle: true,
    title: Semantics(
      label: 'Constrói',
      child: SvgPicture.asset('assets/Constroi.svg', height: 36),
    ),
    actions: [
      if (onSair != null)
        IconButton(
          tooltip: 'Minha conta',
          icon: const Icon(Icons.account_circle_outlined),
          onPressed: () => _abrirConta(context),
        ),
    ],
  );

  void _abrirConta(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (contexto) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (perfil != null) Text('Perfil: ${perfil!.name}'),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(contexto);
                  onSair?.call();
                },
                icon: const Icon(Icons.logout),
                label: const Text('Sair da conta'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
