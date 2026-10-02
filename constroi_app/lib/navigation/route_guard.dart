import 'app_route.dart';
import 'perfil_usuario.dart';

class RouteGuard {
  const RouteGuard(this.perfil);

  factory RouteGuard.doToken(String? token) =>
      RouteGuard(PerfilDoToken.ler(token));

  final PerfilUsuario? perfil;

  bool permite(AppRoute rota) =>
      perfil != null && rota.podeSerAcessadaPor(perfil!);

  AppRoute destinoPermitido(AppRoute solicitada) =>
      permite(solicitada) ? solicitada : AppRoute.painel;
}
