import 'dart:convert';

import 'package:constroi_app/core/api/api_client.dart';
import 'package:constroi_app/core/api/api_config.dart';
import 'package:constroi_app/core/auth/session.dart';
import 'package:constroi_app/core/auth/session_manager.dart';
import 'package:constroi_app/core/auth/token_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryTokenStorage implements TokenStorage {
  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async => token = value;

  @override
  Future<void> delete() async => token = null;
}

void main() {
  test('envia a URL base e o Bearer no cliente único', () async {
    final sessions = SessionManager(MemoryTokenStorage());
    await sessions.start(const AppSession(accessToken: 'segredo'));
    final client = ApiClient(
      config: ApiConfig('https://api.exemplo.com/v1'),
      sessions: sessions,
      httpClient: MockClient((request) async {
        expect(request.url.toString(), 'https://api.exemplo.com/v1/obras');
        expect(request.headers['Authorization'], 'Bearer segredo');
        return http.Response(jsonEncode({'obras': []}), 200);
      }),
    );

    expect(await client.get('obras'), {'obras': []});
  });

  test('401 apaga o token e encerra a sessão', () async {
    final storage = MemoryTokenStorage();
    final sessions = SessionManager(storage);
    await sessions.start(const AppSession(accessToken: 'expirado'));
    var changes = 0;
    sessions.addListener(() => changes++);
    final client = ApiClient(
      config: ApiConfig('https://api.exemplo.com'),
      sessions: sessions,
      httpClient: MockClient((_) async => http.Response('', 401)),
    );

    await expectLater(
      client.get('obras'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
    );
    expect(storage.token, isNull);
    expect(sessions.isSignedIn, isFalse);
    expect(changes, 1);
  });

  test('um 401 antigo não apaga uma sessão nova', () async {
    final storage = MemoryTokenStorage();
    final sessions = SessionManager(storage);
    await sessions.start(const AppSession(accessToken: 'novo'));
    await sessions.expireIfCurrent('antigo');

    expect(sessions.accessToken, 'novo');
    expect(storage.token, 'novo');
  });

  test('recusa HTTP sem permissão explícita de desenvolvimento', () {
    expect(() => ApiConfig('http://api.exemplo.com'), throwsArgumentError);
  });
}
