import 'dart:async';
import 'dart:convert';

import 'package:constroi_app/core/api/api_client.dart';
import 'package:constroi_app/core/api/api_config.dart';
import 'package:constroi_app/core/auth/session_manager.dart';
import 'package:constroi_app/features/pedidos/aprovacoes_screen.dart';
import 'package:constroi_app/features/pedidos/pedidos_service.dart';
import 'package:constroi_app/navigation/perfil_usuario.dart';
import 'package:constroi_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'login_screen_test.dart' show MemoryTokenStorage;

Map<String, dynamic> pedido(int id, String produto) => {
  'id': id,
  'protocolo': 'PED-${id}ABCDEF',
  'status': 'pendente',
  'urgencia': 'padrao',
  'obra_id': id,
  'solicitante_nome': 'Pedreiro',
  'itens': [
    {'produto_id': id, 'quantidade': '10.00', 'produto_nome': produto},
  ],
};

({
  PedidosService service,
  List<Completer<String>> esperas,
  List<Uri> consultas,
})
montarLento() {
  final esperas = <Completer<String>>[];
  final consultas = <Uri>[];
  final api = ApiClient(
    config: ApiConfig('https://api.constroi.test'),
    sessions: SessionManager(MemoryTokenStorage()),
    httpClient: MockClient((requisicao) async {
      if (requisicao.url.path.endsWith('/obras')) {
        return http.Response(
          jsonEncode({
            'obras': [
              {'id': 1, 'nome': 'Obra Alpha'},
              {'id': 2, 'nome': 'Obra Beta'},
            ],
          }),
          200,
        );
      }
      consultas.add(requisicao.url);
      final espera = Completer<String>();
      esperas.add(espera);
      return http.Response(await espera.future, 200);
    }),
  );
  return (
    service: PedidosService(api: api),
    esperas: esperas,
    consultas: consultas,
  );
}

void main() {
  testWidgets('trocar de obra consulta a obra escolhida e troca a fila', (
    tester,
  ) async {
    final montagem = montarLento();
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: AprovacoesScreen(
          service: montagem.service,
          perfil: PerfilUsuario.engenheiro,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(montagem.esperas, hasLength(1));
    expect(montagem.consultas.single.queryParameters['obra_id'], isNull);
    expect(montagem.consultas.single.queryParameters['com_itens'], 'true');

    montagem.esperas[0].complete(
      jsonEncode({
        'pedidos': [pedido(1, 'Cimento da Alpha')],
      }),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Cimento da Alpha'), findsOneWidget);

    final seletor = find.byType(DropdownButton<int?>);
    await tester.ensureVisible(seletor);
    await tester.pumpAndSettle();
    await tester.tap(seletor);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Obra Beta').last);
    await tester.pump();
    await tester.pump();

    expect(montagem.esperas, hasLength(2));
    expect(montagem.consultas.last.queryParameters['obra_id'], '2');

    montagem.esperas[1].complete(
      jsonEncode({
        'pedidos': [pedido(2, 'Vergalhao da Beta')],
      }),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Vergalhao da Beta'), findsOneWidget);
    expect(find.textContaining('Cimento da Alpha'), findsNothing);
  });

  testWidgets('fila vazia mostra o aviso e o contador zera', (tester) async {
    final montagem = montarLento();
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: AprovacoesScreen(
          service: montagem.service,
          perfil: PerfilUsuario.engenheiro,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    montagem.esperas[0].complete(jsonEncode({'pedidos': <Object?>[]}));
    await tester.pumpAndSettle();

    expect(find.text('0 PENDENTES'), findsOneWidget);
    expect(
      find.text('Nenhuma requisição aguardando decisão.'),
      findsOneWidget,
    );
  });

  for (final tamanho in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets('fila sem overflow em $tamanho e texto ampliado', (
      tester,
    ) async {
      final montagem = montarLento();
      await tester.binding.setSurfaceSize(tamanho);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
          child: MaterialApp(
            theme: AppTheme.dark,
            home: AprovacoesScreen(
              service: montagem.service,
              perfil: PerfilUsuario.engenheiro,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      montagem.esperas[0].complete(
        jsonEncode({
          'pedidos': [
            pedido(1, 'Vergalhao CA-50 de 12 metros'),
            pedido(2, 'Cimento Portland CP-II'),
          ],
        }),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
