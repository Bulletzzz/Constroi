# Camada de API do Constrói

`lib/core/api` contém a URL base e o cliente HTTP único. `lib/core/auth` contém os modelos de usuário/sessão e o armazenamento seguro do token. Não colocar tokens em `SharedPreferences`, logs ou no código-fonte.

Configure a URL ao executar o app:

```powershell
flutter run --dart-define=API_BASE_URL=https://api.exemplo.com
```

Em desenvolvimento local, HTTP exige a opção explícita `--dart-define=ALLOW_INSECURE_API=true`. Builds de produção sempre exigem HTTPS. A URL da API é configuração pública, não uma senha.

Integração utilizada pelo aplicativo:

```dart
final sessions = SessionManager(SecureTokenStorage());
await sessions.restore();
final api = ApiClient(config: ApiConfig.fromEnvironment(), sessions: sessions);

// Após o backend autenticar o usuário:
await sessions.start(AppSession(accessToken: token, user: usuario));
final obras = await api.get('obras');
```

O cliente acrescenta `Authorization: Bearer` automaticamente. Em resposta 401, apaga o token e notifica os ouvintes de `SessionManager`; a interface observa a sessão e volta ao login. `AuthService` integra `POST /login` e valida a sessão restaurada com `GET /eu`.

`PainelService` consulta `GET /painel` com filtro opcional por obra e paginação. O Painel apresenta os dados do servidor, carregamento, erro, estado vazio e atualização ao puxar. As fórmulas, o escopo por perfil e as limitações do histórico estão em `Documentação/Tela de Painel.txt`. A chamada expira em 15 segundos para permitir nova tentativa em caso de conexão interrompida.

Na web, armazenamento no navegador não oferece a mesma proteção que o cofre nativo do Android/iOS. Para implantação web, avaliar sessão com cookie `HttpOnly`, `Secure` e proteção CSRF no backend. O armazenamento seguro web exige HTTPS ou localhost.
