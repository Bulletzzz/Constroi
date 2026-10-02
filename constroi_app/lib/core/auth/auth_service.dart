import '../api/api_client.dart';
import 'session.dart';
import 'session_manager.dart';

class AuthService {
  AuthService({required ApiClient api, required SessionManager sessions})
    : _api = api,
      _sessions = sessions;

  final ApiClient _api;
  final SessionManager _sessions;

  Future<void> restaurar() async {
    await _sessions.restore();
    if (_sessions.accessToken == null) return;
    try {
      _sessions.definirUsuario(AppUser.talvezDoJson(await _api.get('eu')));
    } catch (_) {
      return;
    }
  }

  Future<AppSession> entrar({
    required String email,
    required String senha,
  }) async {
    final resposta = await _api.post(
      'login',
      body: {'email': email.trim(), 'senha': senha},
    );

    if (resposta is! Map<String, dynamic>) {
      throw const ApiException(500, 'Resposta inesperada do servidor.');
    }

    final token = resposta['token'];
    if (token is! String || token.trim().isEmpty) {
      throw const ApiException(500, 'O servidor não devolveu o token.');
    }

    final sessao = AppSession(
      accessToken: token,
      user: AppUser.talvezDoJson(resposta['usuario']),
    );

    await _sessions.start(sessao);
    return sessao;
  }

  Future<void> sair() => _sessions.signOut();
}
