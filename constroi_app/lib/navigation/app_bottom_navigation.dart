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
  Widget build(BuildContext context) => Material(
    color: AppTheme.background,
    child: SafeArea(
      top: false,
      child: Row(
        children: [
          for (final rota in AppRoute.values.where(
            (r) => r.podeSerAcessadaPor(perfil),
          ))
            Expanded(
              child: Semantics(
                selected: rota == rotaAtual,
                button: true,
                child: InkWell(
                  onTap: () {
                    if (rota != rotaAtual) {
                      Navigator.of(context).pushReplacementNamed(rota.caminho);
                    }
                  },
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 64),
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 2,
                    ),
                    color: rota == rotaAtual ? AppTheme.accent : null,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          rota.icone,
                          color: rota == rotaAtual
                              ? AppTheme.background
                              : Colors.white,
                          size: 23,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          rota.rotulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: rota == rotaAtual
                                ? AppTheme.background
                                : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
