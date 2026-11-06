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
import 'support/legibilidade.dart';

({
  PedidosService service,
  List<Map<String, Object?>> enviados,
  List<Uri> consultas,
})
montar({
  int statusDaCriacao = 201,
  String erroDaCriacao = 'Falha',
  List<Map<String, Object?>> meus = const [],
  List<Map<String, Object?>> catalogo = const [],
}) {
  final enviados = <Map<String, Object?>>[];
  final consultas = <Uri>[];
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
            'produtos': catalogo.isEmpty
                ? [
                    {
                      'id': 20,
                      'nome': 'Cimento CP-II',
                      'unidade': 'saco',
                      'sku': 'CIM-01',
                    },
                  ]
                : catalogo,
          }),
          200,
        );
      }
      if (caminho.endsWith('/pedidos') && requisicao.method == 'GET') {
        consultas.add(requisicao.url);
        return http.Response(jsonEncode({'pedidos': meus}), 200);
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
  return (
    service: PedidosService(api: api),
    enviados: enviados,
    consultas: consultas,
  );
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

Future<void> escolherMaterial(
  WidgetTester tester, {
  String termo = '',
  String alvo = 'Cimento CP-II · CIM-01',
}) async {
  final seletor = find.bySemanticsIdentifier('requisicao-material');
  await tester.ensureVisible(seletor);
  await tester.pumpAndSettle();
  await tester.tap(seletor);
  await tester.pumpAndSettle();
  if (termo.isNotEmpty) {
    await tester.enterText(
      find.bySemanticsIdentifier('requisicao-busca-material'),
      termo,
    );
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text(alvo).last);
  await tester.pumpAndSettle();
}

void main() {
  Map<String, Object?> pedidoFeito(
    int id,
    String status, {
    String? motivo,
    String urgencia = 'padrao',
  }) => {
    'id': id,
    'protocolo': 'PED-00000$id',
    'status': status,
    'urgencia': urgencia,
    'obra_id': 7,
    'obra_nome': 'Obra Alpha',
    'data': '2026-11-05T13:40:00.000Z',
    'justificativa_recusa': motivo,
    'itens': [
      {'produto_id': 20, 'quantidade': '12.00', 'produto_nome': 'Cimento'},
    ],
  };

  testWidgets('a aba minhas mostra situacao e motivo da recusa', (
    tester,
  ) async {
    final montagem = montar(
      meus: [
        pedidoFeito(1, 'recusado', motivo: 'Sem verba neste mes'),
        pedidoFeito(2, 'aprovado'),
        pedidoFeito(3, 'pendente', urgencia: 'urgente'),
      ],
    );
    await abrir(tester, montagem.service);

    await tocar(tester, 'MINHAS');

    expect(find.text('RECUSADO'), findsOneWidget);
    expect(find.text('APROVADO'), findsOneWidget);
    expect(find.text('PENDENTE'), findsOneWidget);
    expect(find.text('Sem verba neste mes'), findsOneWidget);
    expect(find.text('MOTIVO DA RECUSA'), findsOneWidget);
    expect(find.textContaining('Obra Alpha'), findsNWidgets(3));
    expect(montagem.consultas.single.queryParameters['status'], isNull);
    expect(montagem.consultas.single.queryParameters['ordem'], 'recentes');
    expect(montagem.consultas.single.queryParameters['com_itens'], 'true');
  });

  testWidgets('o filtro de situacao consulta a API de novo', (tester) async {
    final montagem = montar(meus: [pedidoFeito(1, 'aprovado')]);
    await abrir(tester, montagem.service);

    await tocar(tester, 'MINHAS');
    expect(montagem.consultas, hasLength(1));

    await tocar(tester, 'Recusado');
    expect(montagem.consultas.last.queryParameters['status'], 'recusado');

    await tocar(tester, 'Todas');
    expect(montagem.consultas.last.queryParameters['status'], isNull);
    expect(montagem.consultas, hasLength(3));
  });

  testWidgets('sem requisicoes a aba explica em vez de ficar vazia', (
    tester,
  ) async {
    final montagem = montar();
    await abrir(tester, montagem.service);

    await tocar(tester, 'MINHAS');

    expect(
      find.text('Você ainda não fez nenhuma requisição.'),
      findsOneWidget,
    );
  });

  testWidgets('enviar uma requisicao obriga a aba minhas a recarregar', (
    tester,
  ) async {
    final montagem = montar(meus: [pedidoFeito(1, 'aprovado')]);
    await abrir(tester, montagem.service);

    await tocar(tester, 'MINHAS');
    expect(montagem.consultas, hasLength(1));

    await tocar(tester, 'NOVA');
    await escolherMaterial(tester);
    await tester.enterText(find.byType(TextField).at(0), '150');
    await tocar(tester, 'REVISAR');
    await tocar(tester, 'ENVIAR');

    await tocar(tester, 'MINHAS');
    expect(montagem.consultas, hasLength(2));
  });

  testWidgets('a busca filtra o catalogo do material', (tester) async {
    final montagem = montar(
      catalogo: [
        {'id': 20, 'nome': 'Cimento CP-II', 'unidade': 'saco', 'sku': 'CIM-01'},
        {'id': 21, 'nome': 'Areia media', 'unidade': 'm3', 'sku': 'ARE-01'},
        {'id': 22, 'nome': 'Brita 1', 'unidade': 'm3', 'sku': 'BRI-01'},
      ],
    );
    await abrir(tester, montagem.service);

    await tester.tap(find.bySemanticsIdentifier('requisicao-material'));
    await tester.pumpAndSettle();
    expect(find.text('Cimento CP-II · CIM-01'), findsOneWidget);
    expect(find.text('Areia media · ARE-01'), findsOneWidget);

    await tester.enterText(
      find.bySemanticsIdentifier('requisicao-busca-material'),
      'areia',
    );
    await tester.pumpAndSettle();
    expect(find.text('Cimento CP-II · CIM-01'), findsNothing);
    expect(find.text('Areia media · ARE-01'), findsOneWidget);

    await tester.enterText(
      find.bySemanticsIdentifier('requisicao-busca-material'),
      'inexistente',
    );
    await tester.pumpAndSettle();
    expect(find.text('Nenhum material com esse termo.'), findsOneWidget);

    await tester.enterText(
      find.bySemanticsIdentifier('requisicao-busca-material'),
      'BRI',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brita 1 · BRI-01'));
    await tester.pumpAndSettle();
    expect(find.text('Brita 1 · BRI-01'), findsOneWidget);
  });

  testWidgets('os seletores abrem com fundo legivel', (tester) async {
    final montagem = montar();
    await abrir(tester, montagem.service);
    conferirDropdownsLegiveis(tester);
  });

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
