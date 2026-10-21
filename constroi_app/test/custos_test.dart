import 'dart:async';
import 'dart:convert';

import 'package:constroi_app/core/api/api_client.dart';
import 'package:constroi_app/core/api/api_config.dart';
import 'package:constroi_app/core/auth/session_manager.dart';
import 'package:constroi_app/features/custos/custos_model.dart';
import 'package:constroi_app/features/custos/custos_screen.dart';
import 'package:constroi_app/features/custos/custos_service.dart';
import 'package:constroi_app/navigation/perfil_usuario.dart';
import 'package:constroi_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'login_screen_test.dart' show MemoryTokenStorage;

Map<String, Object?> resumo({String valor = '150.25'}) => {
  'custo_acumulado': valor,
  'custo_periodo': valor,
  'orcamento_total': '1000.00',
  'saldo_orcamento': '849.75',
  'percentual_consumido': '15.0',
  'itens_sem_preco': 1,
};

Map<String, Object?> dados({
  bool vazio = false,
  String valor = '150.25',
  bool mais = false,
}) => {
  'obras': [
    {'id': 1, 'nome': 'Obra Alpha'},
    {'id': 2, 'nome': 'Obra Beta'},
  ],
  'resumo': resumo(valor: vazio ? '0' : valor),
  'totais_por_obra': [
    {'obra_id': 1, 'nome': 'Obra Alpha', ...resumo(valor: valor)},
  ],
  'categorias': vazio
      ? []
      : [
          {'nome': 'Cimento e agregados', 'valor': valor},
        ],
  'lancamentos': vazio
      ? []
      : [
          {
            'descricao': 'Cimento CP-II',
            'obra_nome': 'Obra Alpha',
            'categoria_nome': 'Cimento e agregados',
            'data_lancamento': '2026-10-20T15:00:00Z',
            'valor': valor,
          },
        ],
  'paginacao': {'tem_mais': mais},
};

http.Response resposta(Object corpo, [int status = 200]) => http.Response(
  jsonEncode(corpo),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

CustosService service(Future<http.Response> Function(http.Request) responder) =>
    CustosService(
      api: ApiClient(
        config: ApiConfig('https://api.constroi.test'),
        sessions: SessionManager(MemoryTokenStorage()),
        httpClient: MockClient(responder),
      ),
    );

Future<void> abrir(
  WidgetTester tester,
  CustosService servico, {
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
      home: CustosScreen(service: servico, perfil: PerfilUsuario.engenheiro),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('formata dinheiro sem perder centavos em valores altos', () {
    expect(dinheiro('1234567890123456.78'), 'R\$ 1.234.567.890.123.456,78');
    expect(dinheiro('-12.5'), '-R\$ 12,50');
    expect(dinheiro('0'), 'R\$ 0,00');
  });
  test('resposta malformada e falha HTTP nao viram custo zero', () async {
    await expectLater(
      service((_) async => resposta({})).carregar(),
      throwsA(isA<ApiException>()),
    );
    await expectLater(
      service((_) async => resposta({'erro': 'Sem acesso'}, 403)).carregar(),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
    );
  });
  testWidgets('mostra valores, troca obra e periodo na API', (tester) async {
    final chamadas = <Uri>[];
    await abrir(
      tester,
      service((r) async {
        chamadas.add(r.url);
        return resposta(dados());
      }),
    );
    expect(find.text('CUSTOS DA OBRA'), findsOneWidget);
    expect(find.text('R\$ 150,25'), findsWidgets);
    expect(find.textContaining('sem preço'), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier('custos-obra'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Obra Beta').last);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('custos-periodo-mes'));
    await tester.pumpAndSettle();
    expect(chamadas.last.queryParameters['obra_id'], '2');
    expect(chamadas.last.queryParameters['periodo'], 'mes');
    expect(find.text('TOTAIS POR OBRA'), findsNothing);
  });
  testWidgets('seletores semanticos expõem resumo, orcamento e lancamentos', (
    tester,
  ) async {
    await abrir(tester, service((_) async => resposta(dados())));
    expect(
      tester.getSemantics(find.bySemanticsIdentifier('custos-resumo')).label,
      contains('R\$ 150,25'),
    );
    expect(find.bySemanticsIdentifier('custos-orcamento'), findsOneWidget);
    expect(find.bySemanticsIdentifier('custos-periodo-semana'), findsOneWidget);
    expect(find.bySemanticsIdentifier('custos-periodo-total'), findsOneWidget);
    await tester.ensureVisible(find.text('LANÇAMENTOS DO PERÍODO'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsIdentifier('custos-lancamentos'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsIdentifier('custos-lancamento'))
          .label,
      contains('Cimento CP-II'),
    );
  });
  testWidgets('sem lancamentos tem estado vazio', (tester) async {
    await abrir(tester, service((_) async => resposta(dados(vazio: true))));
    await tester.scrollUntilVisible(
      find.text('Nenhum lançamento de custo neste período.'),
      300,
    );
    expect(
      find.text('Nenhum lançamento de custo neste período.'),
      findsOneWidget,
    );
  });
  testWidgets('erro permite tentar novamente', (tester) async {
    var chamadas = 0;
    await abrir(
      tester,
      service(
        (_) async => ++chamadas == 1
            ? resposta({'erro': 'Indisponível'}, 503)
            : resposta(dados()),
      ),
    );
    expect(find.text('Indisponível'), findsOneWidget);
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('CUSTO ACUMULADO'), findsOneWidget);
  });
  testWidgets('resposta atrasada nao substitui a obra selecionada', (
    tester,
  ) async {
    final antiga = Completer<http.Response>();
    await abrir(
      tester,
      service((r) async {
        if (r.url.queryParameters['periodo'] == 'mes') return antiga.future;
        return resposta(dados(valor: '250.00'));
      }),
    );
    await tester.tap(find.text('MÊS'));
    await tester.pump();
    await tester.tap(find.text('SEMANA'));
    await tester.pumpAndSettle();
    antiga.complete(resposta(dados(valor: '999.00')));
    await tester.pumpAndSettle();
    expect(find.text('R\$ 250,00'), findsWidgets);
    expect(find.text('R\$ 999,00'), findsNothing);
  });
  testWidgets('erro na proxima pagina preserva lancamentos e permite repetir', (
    tester,
  ) async {
    var falhar = true;
    final chamadas = <Uri>[];
    await abrir(
      tester,
      service((r) async {
        chamadas.add(r.url);
        if (r.url.queryParameters['offset'] != '0' && falhar) {
          return resposta({'erro': 'Falha de página'}, 503);
        }
        return resposta(dados(mais: r.url.queryParameters['offset'] == '0'));
      }),
    );
    await tester.scrollUntilVisible(find.text('Carregar mais'), 300);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Carregar mais'));
    await tester.pumpAndSettle();
    expect(find.text('Cimento CP-II'), findsOneWidget);
    expect(find.text('Falha de página'), findsOneWidget);
    falhar = false;
    await tester.ensureVisible(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(chamadas.last.queryParameters['offset'], '1');
    expect(find.text('Cimento CP-II'), findsNWidgets(2));
  });
  for (final tamanho in [
    const Size(320, 640),
    const Size(844, 390),
    const Size(1280, 800),
  ]) {
    testWidgets('sem overflow em $tamanho com fonte ampliada', (tester) async {
      tester.view.physicalSize = tamanho;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await abrir(tester, service((_) async => resposta(dados())), escala: 1.4);
      await tester.drag(find.byType(ListView), const Offset(0, -1600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
