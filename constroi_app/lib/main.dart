import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'core/api/api_client.dart';
import 'core/api/api_config.dart';
import 'core/auth/auth_service.dart';
import 'core/auth/session_manager.dart';
import 'core/auth/token_storage.dart';
import 'navigation/app_route.dart';
import 'navigation/perfil_usuario.dart';
import 'navigation/route_guard.dart';
import 'screens/login_screen.dart';
import 'screens/module_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/app_home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ConstroiApp());
}

class ConstroiApp extends StatefulWidget {
  const ConstroiApp({super.key, this.config, this.storage, this.httpClient});

  final ApiConfig? config;
  final TokenStorage? storage;
  final http.Client? httpClient;

  @override
  State<ConstroiApp> createState() => _ConstroiAppState();
}

class _ConstroiAppState extends State<ConstroiApp> {
  SessionManager? _sessoes;
  AuthService? _auth;
  ApiClient? _api;
  String? _erroDeConfiguracao;
  bool _iniciando = true;

  @override
  void initState() {
    super.initState();
    _preparar();
  }

  @override
  void dispose() {
    _api?.close();
    super.dispose();
  }

  Future<void> _preparar() async {
    try {
      final config = widget.config ?? ApiConfig.fromEnvironment();
      final sessoes = SessionManager(widget.storage ?? SecureTokenStorage());
      final api = ApiClient(
        config: config,
        sessions: sessoes,
        httpClient: widget.httpClient,
      );
      _sessoes = sessoes;
      _api = api;
      _auth = AuthService(api: api, sessions: sessoes);
      await sessoes.restore();
    } catch (erro) {
      _erroDeConfiguracao = '$erro';
    }
    if (mounted) setState(() => _iniciando = false);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Constrói',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark,
    home: _inicio(),
    onGenerateRoute: _gerarRota,
  );

  Route<void>? _gerarRota(RouteSettings settings) {
    final solicitada = AppRoute.porCaminho(settings.name);
    if (solicitada == null) return null;

    final guarda = RouteGuard.daSessao(_sessoes?.session);
    final destino = guarda.destinoPermitido(solicitada);
    return MaterialPageRoute<void>(
      settings: RouteSettings(name: destino.caminho),
      builder: (_) => _areaAutenticada(destino),
    );
  }

  Widget _inicio() {
    if (_iniciando) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(child: CircularProgressIndicator(color: AppTheme.accent)),
      );
    }
    if (_erroDeConfiguracao != null) {
      return _ConfiguracaoAusente(detalhe: _erroDeConfiguracao!);
    }

    final sessoes = _sessoes!;
    return ListenableBuilder(
      listenable: sessoes,
      builder: (_, _) => sessoes.isSignedIn
          ? _areaAutenticada(AppRoute.painel)
          : LoginScreen(auth: _auth!),
    );
  }

  Widget _areaAutenticada(AppRoute solicitada) {
    final sessoes = _sessoes!;
    return ListenableBuilder(
      listenable: sessoes,
      builder: (_, _) {
        if (!sessoes.isSignedIn) return LoginScreen(auth: _auth!);

        final guarda = RouteGuard.daSessao(sessoes.session);
        final perfil = guarda.perfil;
        if (perfil == null) {
          return _SessaoSemPerfil(onSair: sessoes.signOut);
        }

        return _telaDaRota(guarda.destinoPermitido(solicitada), perfil);
      },
    );
  }

  Widget _telaDaRota(AppRoute rota, PerfilUsuario perfil) {
    if (rota == AppRoute.painel) return AppHome(perfil: perfil);
    return ModuleScreen(rota: rota, perfil: perfil);
  }
}

class _SessaoSemPerfil extends StatelessWidget {
  const _SessaoSemPerfil({required this.onSair});

  final Future<void> Function() onSair;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, color: AppTheme.accent, size: 36),
              const SizedBox(height: 16),
              Text(
                'Não foi possível identificar seu perfil.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: onSair,
                child: const Text('VOLTAR AO LOGIN'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ConfiguracaoAusente extends StatelessWidget {
  const _ConfiguracaoAusente({required this.detalhe});

  final String detalhe;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.background,
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.settings_outlined,
                color: AppTheme.accent,
                size: 34,
              ),
              const SizedBox(height: 16),
              Text(
                'Falta configurar o endereço da API',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              const Text(
                'Rode o aplicativo informando onde a API está:',
                style: TextStyle(height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: AppTheme.surface,
                child: const SelectableText(
                  'flutter run -d chrome \\\n'
                  '  --dart-define=API_BASE_URL=http://localhost:8080 \\\n'
                  '  --dart-define=ALLOW_INSECURE_API=true',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                detalhe,
                style: const TextStyle(fontSize: 12, color: Color(0xFF9A978E)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
