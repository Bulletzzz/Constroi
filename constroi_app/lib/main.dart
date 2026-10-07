import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'core/api/api_client.dart';
import 'core/api/api_config.dart';
import 'core/auth/auth_service.dart';
import 'core/auth/session_manager.dart';
import 'core/auth/token_storage.dart';
import 'features/painel/painel_service.dart';
import 'navigation/app_route.dart';
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
      final auth = AuthService(api: api, sessions: sessoes);
      _auth = auth;
      await auth.restaurar();
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
    onGenerateRoute: (settings) {
      final rota = AppRoute.porCaminho(settings.name);
      if (rota == null) return null;
      final destino = RouteGuard.doToken(
        _sessoes?.accessToken,
      ).destinoPermitido(rota);
      return MaterialPageRoute<void>(
        settings: RouteSettings(
          name: destino.caminho,
          arguments: settings.arguments,
        ),
        builder: (_) => _areaAutenticada(destino),
      );
    },
  );

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

    return _areaAutenticada(AppRoute.painel);
  }

  Widget _areaAutenticada(AppRoute rota) {
    final sessoes = _sessoes!;
    return ListenableBuilder(
      listenable: sessoes,
      builder: (_, _) {
        if (!sessoes.isSignedIn) return LoginScreen(auth: _auth!);
        final guarda = RouteGuard.doToken(sessoes.accessToken);
        final perfil = guarda.perfil;
        if (perfil == null) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: sessoes.signOut,
                child: const Text('Perfil inválido. Voltar ao login'),
              ),
            ),
          );
        }
        final destino = guarda.destinoPermitido(rota);
        if (destino != AppRoute.painel) {
          return ModuleScreen(rota: destino, perfil: perfil);
        }
        return AppHome(
          service: PainelService(_api!),
          perfil: perfil,
          onSair: sessoes.signOut,
        );
      },
    );
  }
}

class _ConfiguracaoAusente extends StatelessWidget {
  const _ConfiguracaoAusente({required this.detalhe});

  final String detalhe;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.background,
    body: SingleChildScrollView(
      child: Center(
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
                  'No Flutter Web a API fica na mesma origem da página, '
                  'então basta um caminho. No Android e iOS informe a '
                  'URL completa:',
                  style: TextStyle(height: 1.4),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: AppTheme.surface,
                  child: const SelectableText(
                    'flutter build web \\\n'
                    '  --dart-define=API_BASE_URL=/api\n\n'
                    'flutter run -d android \\\n'
                    '  --dart-define=API_BASE_URL=https://api.constroi.com.br',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  detalhe,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9A978E),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
