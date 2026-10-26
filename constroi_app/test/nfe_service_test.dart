import 'dart:async';
import 'dart:convert';

import 'package:constroi_app/core/api/api_client.dart';
import 'package:constroi_app/core/api/api_config.dart';
import 'package:constroi_app/core/auth/session.dart';
import 'package:constroi_app/core/auth/session_manager.dart';
import 'package:constroi_app/features/nfe/nfe_preview.dart';
import 'package:constroi_app/features/nfe/nfe_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'api_client_test.dart' show MemoryTokenStorage;
import 'support/nfe_fixture.dart';

void main() {
  final nota = NfePreview.ler('nota.xml', utf8.encode(xmlNfe()));
  for (final anexo in [false, true]) {
    test(
      '${anexo ? 'PATCH anexa' : 'POST importa'} multipart com token e bytes originais',
      () async {
        final sessions = SessionManager(MemoryTokenStorage());
        await sessions.start(const AppSession(accessToken: 'token-teste'));
        final api = ApiClient(
          config: ApiConfig('https://api.exemplo.test/api'),
          sessions: sessions,
          httpClient: MockClient((request) async {
            expect(request.method, anexo ? 'PATCH' : 'POST');
            expect(
              request.url.path,
              anexo ? '/api/entradas/42/xml' : '/api/entradas/xml',
            );
            expect(request.headers['Authorization'], 'Bearer token-teste');
            expect(
              request.headers['content-type'],
              startsWith('multipart/form-data; boundary='),
            );
            expect(request.body, contains('name="xml"; filename="nota.xml"'));
            expect(request.body, contains(xmlNfe()));
            if (anexo) {
              expect(request.body, isNot(contains('name="obra_id"')));
            } else {
              expect(request.body, contains('name="obra_id"\r\n\r\n7\r\n'));
            }
            return http.Response(
              jsonEncode(resultadoNfe(anexo: anexo)),
              anexo ? 200 : 201,
            );
          }),
        );
        final service = NfeService(api: api);
        final resultado = anexo
            ? await service.anexar(nota, 42)
            : await service.importar(nota, 7);
        expect(resultado.id, 42);
        expect(resultado.obraId, 7);
      },
    );
  }

  test('preserva detalhes do 422 para informar todos os materiais', () async {
    final api = ApiClient(
      config: ApiConfig('https://api.exemplo.test'),
      sessions: SessionManager(MemoryTokenStorage()),
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode(pendenciasNfe),
          422,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    await expectLater(
      NfeService(api: api).importar(nota, 7),
      throwsA(
        isA<ApiException>().having(
          (e) => e.details['materiais_pendentes'],
          'pendências',
          hasLength(3),
        ),
      ),
    );
  });

  test('401 de upload encerra a sessão atual', () async {
    final sessions = SessionManager(MemoryTokenStorage());
    await sessions.start(const AppSession(accessToken: 'expirado'));
    final api = ApiClient(
      config: ApiConfig('https://api.exemplo.test'),
      sessions: sessions,
      httpClient: MockClient((_) async => http.Response('', 401)),
    );
    await expectLater(
      NfeService(api: api).anexar(nota, 42),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
    );
    expect(sessions.isSignedIn, isFalse);
  });

  test('401 atrasado do upload não encerra uma sessão nova', () async {
    final sessions = SessionManager(MemoryTokenStorage());
    await sessions.start(const AppSession(accessToken: 'antigo'));
    final pendente = Completer<http.Response>();
    final api = ApiClient(
      config: ApiConfig('https://api.exemplo.test'),
      sessions: sessions,
      httpClient: MockClient((_) => pendente.future),
    );
    final resultado = NfeService(api: api).anexar(nota, 42);
    final verificacao = expectLater(resultado, throwsA(isA<ApiException>()));
    await sessions.start(const AppSession(accessToken: 'novo'));
    pendente.complete(http.Response('', 401));
    await verificacao;
    expect(sessions.accessToken, 'novo');
  });

  test('recusa upload para outra origem antes de enviar o token', () {
    final api = ApiClient(
      config: ApiConfig('https://api.exemplo.test'),
      sessions: SessionManager(MemoryTokenStorage()),
      httpClient: MockClient(
        (_) async => throw StateError('Não deveria enviar'),
      ),
    );
    for (final caminho in ['https://outra.test/xml', '/xml', '../xml']) {
      expect(
        () => api.multipart('POST', caminho, files: []),
        throwsArgumentError,
      );
    }
  });

  test('não indica sucesso com retorno incompleto da API', () async {
    final api = ApiClient(
      config: ApiConfig('https://api.exemplo.test'),
      sessions: SessionManager(MemoryTokenStorage()),
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );
    await expectLater(
      NfeService(api: api).anexar(nota, 42),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 502)),
    );
  });
}
