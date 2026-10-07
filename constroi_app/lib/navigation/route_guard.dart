import '../core/auth/session.dart';
import 'app_route.dart';
import 'perfil_usuario.dart';

class RouteGuard {
  const RouteGuard(this.perfil);

  factory RouteGuard.daSessao(AppSession? sessao) =>
      RouteGuard(PerfilDaSessao.ler(sessao));

  final PerfilUsuario? perfil;

  bool permite(AppRoute rota) =>
      perfil != null && rota.podeSerAcessadaPor(perfil!);

  AppRoute destinoPermitido(AppRoute solicitada) =>
      permite(solicitada) ? solicitada : AppRoute.painel;
}
