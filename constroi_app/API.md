# Camada de API do Constrói

`lib/core/api` contém a URL base e o cliente HTTP único. `lib/core/auth` contém os modelos de usuário/sessão e o armazenamento seguro do token. Não colocar tokens em `SharedPreferences`, logs ou no código-fonte.

Configure a URL ao executar o app:

```powershell
flutter run --dart-define=API_BASE_URL=https://api.exemplo.com
```

Em desenvolvimento local, HTTP exige a opção explícita `--dart-define=ALLOW_INSECURE_API=true`. Builds de produção sempre exigem HTTPS. A URL da API é configuração pública, não uma senha.

Integração prevista após existir uma rota de login no backend:

```dart
final sessions = SessionManager(SecureTokenStorage());
await sessions.restore();
final api = ApiClient(config: ApiConfig.fromEnvironment(), sessions: sessions);

// Após o backend autenticar o usuário:
await sessions.start(AppSession(accessToken: token, user: usuario));
final obras = await api.get('obras');
```

O cliente acrescenta `Authorization: Bearer` automaticamente. Em resposta 401, apaga o token e notifica os ouvintes de `SessionManager`. Quando a tela de login e o roteamento forem criados, a interface deverá observar `isSignedIn` e mostrar o login quando ficar `false`. A API atual não possui rotas de autenticação nem contrato de resposta definido: esta camada não implementa login real nem inventa endpoints.

Na web, armazenamento no navegador não oferece a mesma proteção que o cofre nativo do Android/iOS. Para implantação web, avaliar sessão com cookie `HttpOnly`, `Secure` e proteção CSRF no backend. O armazenamento seguro web exige HTTPS ou localhost.
