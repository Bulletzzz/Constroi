import 'dart:convert';

import 'package:constroi_app/core/api/api_client.dart';
import 'package:constroi_app/core/api/api_config.dart';
import 'package:constroi_app/core/auth/session_manager.dart';
import 'package:constroi_app/features/pedidos/pedidos_service.dart';
import 'package:constroi_app/features/pedidos/requisicao_screen.dart';
import 'package:constroi_app/navigation/perfil_usuario.dart';
import 'package:constroi_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'login_screen_test.dart' show MemoryTokenStorage;

({PedidosService service, List<Map<String, Object?>> enviados}) montar({
  int statusDaCriacao = 201,
  String erroDaCriacao = 'Falha',
}) {
  final enviados = <Map<String, Object?>>[];
  final api = ApiClient(
    config: ApiConfig('https://api.constroi.test'),
    sessions: SessionManager(MemoryTokenStorage()),
    httpClient: MockClient((requisicao) async {
      final caminho = requisicao.url.path;
      if (caminho.endsWith('/obras')) {
        return http.Response(
          jsonEncode({
            'obras': [
              {'id': 7, 'nome': 'Obra Alpha'},
            ],
          }),
          200,
        );
      }
      if (caminho.endsWith('/produtos')) {
        return http.Response(
          jsonEncode({
            'produtos': [
              {
                'id': 20,
                'nome': 'Cimento CP-II',
                'unidade': 'saco',
                'sku': 'CIM-01',
              },
            ],
          }),
          200,
        );
      }
      enviados.add(
        jsonDecode(requisicao.body) as Map<String, Object?>,
      );
      if (statusDaCriacao != 201) {
        return http.Response(
          jsonEncode({'erro': erroDaCriacao}),
          statusDaCriacao,
        );
      }
      return http.Response(
        jsonEncode({
          'id': 30,
          'protocolo': 'PED-ABC123',
          'status': 'pendente',
          'urgencia': 'urgente',
          'local_obra': 'Setor 4',
          'itens': [
            {'produto_id': 20, 'quantidade': '150.00'},
          ],
        }),
        201,
      );
    }),
  );
  return (service: PedidosService(api: api), enviados: enviados);
}

Future<void> abrir(WidgetTester tester, PedidosService service) async {
  await tester.binding.setSurfaceSize(const Size(420, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: RequisicaoScreen(
        service: service,
        perfil: PerfilUsuario.pedreiro,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tocar(WidgetTester tester, String rotulo) async {
  await tester.ensureVisible(find.text(rotulo));
  await tester.pumpAndSettle();
  await tester.tap(find.text(rotulo));
  await tester.pumpAndSettle();
}

Future<void> escolherMaterial(WidgetTester tester) async {
  final seletor = find.byType(DropdownButton<int>).first;
  await tester.ensureVisible(seletor);
  await tester.pumpAndSettle();
  await tester.tap(seletor);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Cimento CP-II · CIM-01').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('envia a requisicao com quantidade numerica e campos novos', (
    tester,
  ) async {
    final montagem = montar();
    await abrir(tester, montagem.service);

    await escolherMaterial(tester);
    await tester.enterText(find.byType(TextField).at(0), '150');
    await tester.enterText(find.byType(TextField).at(1), ' Setor 4 ');
    await tester.enterText(find.byType(TextField).at(2), 'Marca X');
    await tester.pumpAndSettle();

    await tocar(tester, 'REVISAR');
    expect(find.text('CONFIRA ANTES DE ENVIAR'), findsOneWidget);
    expect(find.text('150 saco'), findsOneWidget);

    await tocar(tester, 'ENVIAR');

    final pedido = montagem.enviados.single['pedido']! as Map<String, Object?>;
    expect(pedido['obra_id'], 7);
    expect(pedido['urgencia'], 'padrao');
    expect(pedido['local_obra'], 'Setor 4');
    expect(pedido['justificativa'], 'Marca X');
    final itens = pedido['itens']! as List<Object?>;
    final item = itens.single! as Map<String, Object?>;
    expect(item['produto_id'], 20);
    expect(item['quantidade'], 150);
    expect(item['quantidade'], isA<num>());

    expect(find.text('REQUISIÇÃO ENVIADA'), findsOneWidget);
    expect(find.text('PED-ABC123'), findsOneWidget);
  });

  testWidgets('quantidade decimal com virgula vira numero', (tester) async {
    final montagem = montar();
    await abrir(tester, montagem.service);

    await escolherMaterial(tester);
    await tester.enterText(find.byType(TextField).at(0), '2,５'.replaceAll('５', '5'));
    await tester.pumpAndSettle();
    await tocar(tester, 'REVISAR');
    await tocar(tester, 'ENVIAR');

    final pedido = montagem.enviados.single['pedido']! as Map<String, Object?>;
    final item = (pedido['itens']! as List<Object?>).single!
        as Map<String, Object?>;
    expect(item['quantidade'], 2.5);
  });

  testWidgets('nao avanca sem material nem quantidade valida', (tester) async {
    final montagem = montar();
    await abrir(tester, montagem.service);

    await tocar(tester, 'REVISAR');
    expect(find.text('Escolha o material.'), findsOneWidget);
    expect(find.text('CONFIRA ANTES DE ENVIAR'), findsNothing);

    await escolherMaterial(tester);
    await tester.enterText(find.byType(TextField).at(0), '0');
    await tocar(tester, 'REVISAR');
    expect(find.text('Informe uma quantidade maior que zero.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), '1,555');
    await tocar(tester, 'REVISAR');
    expect(
      find.text('A quantidade aceita no máximo duas casas decimais.'),
      findsOneWidget,
    );
    expect(montagem.enviados, isEmpty);
  });

  testWidgets('falha da API volta ao formulario com a mensagem', (
    tester,
  ) async {
    final montagem = montar(
      statusDaCriacao: 403,
      erroDaCriacao: 'Voce nao atua nesta obra.',
    );
    await abrir(tester, montagem.service);

    await escolherMaterial(tester);
    await tester.enterText(find.byType(TextField).at(0), '10');
    await tester.pumpAndSettle();
    await tocar(tester, 'REVISAR');
    await tocar(tester, 'ENVIAR');

    expect(find.text('Voce nao atua nesta obra.'), findsOneWidget);
    expect(find.text('REQUISIÇÃO ENVIADA'), findsNothing);
    expect(find.text('QUANTIDADE'), findsOneWidget);
  });

  for (final tamanho in [
    const Size(320, 900),
    const Size(390, 900),
  ]) {
    testWidgets('requisicao sem overflow em $tamanho e texto ampliado', (
      tester,
    ) async {
      final montagem = montar();
      await tester.binding.setSurfaceSize(tamanho);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
          child: MaterialApp(
            theme: AppTheme.dark,
            home: RequisicaoScreen(
              service: montagem.service,
              perfil: PerfilUsuario.pedreiro,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
