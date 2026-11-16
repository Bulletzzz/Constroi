import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../navigation/perfil_usuario.dart';
import '../theme/app_theme.dart';

const _tinta = Color(0xFF1A1C1C);
const _apoio = Color(0xFF5E5E5E);
const _perigo = Color(0xFFB3261E);

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
        Semantics(
          identifier: 'conta-abrir',
          button: true,
          child: IconButton(
            tooltip: 'Minha conta',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => _abrirConta(context),
          ),
        ),
    ],
  );

  void _abrirConta(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(),
      builder: (contexto) => Semantics(
        identifier: 'conta-painel',
        container: true,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: _tinta,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: const Text(
                  'MINHA CONTA',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (perfil != null) ...[
                      Row(
                        children: [
                          const Icon(
                            Icons.badge_outlined,
                            color: _tinta,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'PERFIL DE ACESSO',
                                  style: TextStyle(
                                    color: _apoio,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  perfil!.rotulo,
                                  style: const TextStyle(
                                    color: _tinta,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                    Semantics(
                      identifier: 'conta-sair',
                      button: true,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(contexto);
                          onSair?.call();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _perigo,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: const RoundedRectangleBorder(),
                          padding: const EdgeInsets.symmetric(vertical: 18),
                        ),
                        icon: const Icon(Icons.logout),
                        label: const Text(
                          'SAIR DA CONTA',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Semantics(
                      identifier: 'conta-fechar',
                      button: true,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(contexto),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _tinta,
                          side: const BorderSide(color: _tinta, width: 2),
                          shape: const RoundedRectangleBorder(),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text(
                          'FECHAR',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
