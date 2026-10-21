import 'dart:async';
import 'dart:convert';

import 'package:constroi_app/core/api/api_client.dart';
import 'package:constroi_app/core/api/api_config.dart';
import 'package:constroi_app/core/auth/session_manager.dart';
import 'package:constroi_app/features/equipe/equipe_screen.dart';
import 'package:constroi_app/features/equipe/equipe_service.dart';
import 'package:constroi_app/main.dart';
import 'package:constroi_app/navigation/perfil_usuario.dart';
import 'package:constroi_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'login_screen_test.dart' show MemoryTokenStorage;
import 'navigation_test.dart' show tokenDe;

const obras = {
  'obras': [
    {'id': 1, 'nome': 'Obra Alpha'},
    {'id': 2, 'nome': 'Obra Beta'},
  ],
};
Map<String, Object?> pessoa(String nome, String perfil) => {
  'usuario_id': 7,
  'nome': nome,
  'email': 'pessoa@example.test',
  'tipo': perfil,
  'data_inicio': '2026-10-20T15:00:00Z',
};
http.Response resposta(Object corpo, [int status = 200]) => http.Response(
  jsonEncode(corpo),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
EquipeService service(Future<http.Response> Function(http.Request) responder) =>
    EquipeService(
      api: ApiClient(
        config: ApiConfig('https://api.constroi.test'),
        sessions: SessionManager(MemoryTokenStorage()),
        httpClient: MockClient(responder),
      ),
    );
Future<void> abrir(
  WidgetTester tester,
  EquipeService servico, {
  double escala = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(escala)),
        child: child!,
      ),
      home: EquipeScreen(service: servico, perfil: PerfilUsuario.pedreiro),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('nao converte resposta invalida em equipe vazia', () async {
    await expectLater(
      service((_) async => resposta({})).listar(1),
      throwsA(isA<ApiException>()),
    );
    await expectLater(
      service((_) async => resposta({'erro': 'Sem acesso'}, 403)).obras(),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
    );
    expect(
      PessoaEquipe.fromJson(pessoa('Ana', 'desconhecido')).papel,
      'Perfil não informado',
    );
  });
  testWidgets('lista perfis por obra, pesquisa e abre detalhes', (
    tester,
  ) async {
    final chamadas = <String>[];
    await abrir(
      tester,
      service((r) async {
        chamadas.add(r.url.path);
        return resposta(
          r.url.path == '/obras'
              ? obras
              : {
                  'equipe': [
                    pessoa('Ana', 'engenheiro'),
                    pessoa('Bruno', 'pedreiro'),
                    pessoa('Carla', 'master'),
                  ],
                },
        );
      }),
    );
    expect(chamadas, ['/obras', '/obras/1/equipe']);
    expect(find.text('Engenheiro'), findsOneWidget);
    expect(find.text('Pedreiro'), findsOneWidget);
    expect(find.text('Master'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.bySemanticsIdentifier('equipe-busca'),
        matching: find.byType(TextField),
      ),
      'engenheiro',
    );
    await tester.pump();
    expect(find.text('Bruno'), findsNothing);
    await tester.tap(find.bySemanticsIdentifier('equipe-pessoa'));
    await tester.pumpAndSettle();
    expect(find.text('pessoa@example.test'), findsOneWidget);
    expect(find.textContaining('Desde'), findsOneWidget);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('equipe-obra'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Obra Beta').last);
    await tester.pumpAndSettle();
    expect(chamadas.last, '/obras/2/equipe');
    expect(find.text('Bruno'), findsOneWidget);
  });
  testWidgets('obra sem equipe mostra estado vazio', (tester) async {
    await abrir(
      tester,
      service(
        (r) async => resposta(r.url.path == '/obras' ? obras : {'equipe': []}),
      ),
    );
    expect(
      find.text('Esta obra ainda não tem equipe vinculada.'),
      findsOneWidget,
    );
    expect(find.bySemanticsIdentifier('equipe-vazio'), findsOneWidget);
    expect(find.bySemanticsIdentifier('equipe-pessoa'), findsNothing);
  });
  testWidgets('sem obras nao consulta uma equipe arbitraria', (tester) async {
    final chamadas = <String>[];
    await abrir(
      tester,
      service((r) async {
        chamadas.add(r.url.path);
        return resposta({'obras': []});
      }),
    );
    expect(chamadas, ['/obras']);
    expect(
      find.text('Nenhuma obra disponível para consultar a equipe.'),
      findsOneWidget,
    );
  });
  testWidgets(
    'erro pode ser recuperado e busca vazia e distinta da equipe vazia',
    (tester) async {
      var falhar = true;
      await abrir(
        tester,
        service(
          (r) async => falhar
              ? resposta({'erro': 'Indisponível'}, 503)
              : resposta(
                  r.url.path == '/obras'
                      ? obras
                      : {
                          'equipe': [pessoa('Ana', 'engenheiro')],
                        },
                ),
        ),
      );
      expect(find.text('Indisponível'), findsOneWidget);
      falhar = false;
      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'xyz');
      await tester.pump();
      expect(
        find.text('Nenhuma pessoa encontrada para esta busca.'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Limpar busca'));
      await tester.pump();
      expect(find.text('Ana'), findsOneWidget);
    },
  );
  testWidgets('troca de obra ignora uma resposta antiga', (tester) async {
    final antiga = Completer<http.Response>();
    await abrir(
      tester,
      service((r) async {
        if (r.url.path == '/obras') return resposta(obras);
        if (r.url.path == '/obras/2/equipe') return antiga.future;
        return resposta({
          'equipe': [
            pessoa(
              r.url.path == '/obras/1/equipe' ? 'Ana' : 'Bruno',
              'pedreiro',
            ),
          ],
        });
      }),
    );
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Obra Beta').last);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Obra Alpha').last);
    await tester.pumpAndSettle();
    antiga.complete(
      resposta({
        'equipe': [pessoa('Resposta antiga', 'master')],
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Resposta antiga'), findsNothing);
  });
  testWidgets('navegacao abre equipe para pedreiro', (tester) async {
    await tester.pumpWidget(
      ConstroiApp(
        config: ApiConfig('https://api.constroi.test'),
        storage: MemoryTokenStorage()..token = tokenDe('pedreiro'),
        httpClient: MockClient(
          (r) async => resposta(
            r.url.path == '/obras'
                ? obras
                : r.url.path.endsWith('/equipe')
                ? {'equipe': []}
                : {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Equipe'));
    await tester.pumpAndSettle();
    expect(find.byType(EquipeScreen), findsOneWidget);
    expect(
      find.text('Esta obra ainda não tem equipe vinculada.'),
      findsOneWidget,
    );
  });
  for (final tamanho in [
    const Size(320, 640),
    const Size(844, 390),
    const Size(1280, 800),
  ]) {
    testWidgets('layout e perfil sem overflow em $tamanho', (tester) async {
      tester.view.physicalSize = tamanho;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await abrir(
        tester,
        service(
          (r) async => resposta(
            r.url.path == '/obras'
                ? obras
                : {
                    'equipe': [
                      pessoa('Ana Maria com nome completo longo', 'engenheiro'),
                    ],
                  },
          ),
        ),
        escala: 1.4,
      );
      await tester.ensureVisible(
        find.text('Ana Maria com nome completo longo'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ana Maria com nome completo longo'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
