import 'dart:convert';

import 'package:constroi_app/core/api/api_client.dart';
import 'package:constroi_app/core/api/api_config.dart';
import 'package:constroi_app/core/auth/session_manager.dart';
import 'package:constroi_app/features/estoque/estoque_screen.dart';
import 'package:constroi_app/features/estoque/estoque_service.dart';
import 'package:constroi_app/features/painel/painel_service.dart';
import 'package:constroi_app/navigation/perfil_usuario.dart';
import 'package:constroi_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'login_screen_test.dart' show MemoryTokenStorage;

Map<String, dynamic> item(
  int id, {
  String nome = 'Cimento CP-II',
  String sku = 'CIM-01',
  bool baixo = false,
  int? categoria = 2,
  String categoriaNome = 'Cimento e agregados',
}) => {
  'id': id,
  'obra_id': 7,
  'produto_id': id + 100,
  'produto_nome': nome,
  'unidade': 'SC',
  'sku': sku,
  'categoria_custo_id': categoria,
  'categoria_nome': categoriaNome,
  'quantidade': '4.50',
  'estoque_minimo': '5.00',
  'baixo': baixo,
};

({EstoqueService service, List<Uri> chamadas}) montar(
  List<Map<String, dynamic>> Function(int chamada) responder,
) {
  final chamadas = <Uri>[];
  final api = ApiClient(
    config: ApiConfig('https://api.constroi.test'),
    sessions: SessionManager(MemoryTokenStorage()),
    httpClient: MockClient((requisicao) async {
      chamadas.add(requisicao.url);
      return http.Response(
        jsonEncode({'estoque': responder(chamadas.length)}),
        200,
      );
    }),
  );
  return (service: EstoqueService(api: api), chamadas: chamadas);
}


({EstoqueService estoque, PainelService painel, List<Uri> chamadas}) montarComPainel(
  List<Map<String, dynamic>> itens, {
  List<Map<String, dynamic>> obras = const [
    {'id': 7, 'nome': 'Obra Alpha'},
    {'id': 8, 'nome': 'Obra Beta'},
  ],
}) {
  final chamadas = <Uri>[];
  final api = ApiClient(
    config: ApiConfig('https://api.constroi.test'),
    sessions: SessionManager(MemoryTokenStorage()),
    httpClient: MockClient((requisicao) async {
      chamadas.add(requisicao.url);
      if (requisicao.url.path.endsWith('/painel')) {
        return http.Response(
          jsonEncode({
            'obras': obras,
            'atualizado_em': '2026-10-08T12:00:00.000Z',
            'indicadores': {
              'total_itens': 1248,
              'rupturas_criticas': 12,
              'requisicoes_pendentes': 4,
              'obras_ativas': 2,
            },
            'movimentacoes': [],
            'paginacao': {'limite': 5, 'offset': 0, 'tem_mais': false},
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'estoque': itens}), 200);
    }),
  );
  return (
    estoque: EstoqueService(api: api),
    painel: PainelService(api),
    chamadas: chamadas,
  );
}

Future<void> abrir(
  WidgetTester tester,
  EstoqueService service, {
  PerfilUsuario perfil = PerfilUsuario.engenheiro,
}) async {
  tester.view.physicalSize = const Size(900, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: EstoqueScreen(service: service, perfil: perfil),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('desenha os elementos do Figma 03', (tester) async {
    final tudo = montar((_) => [item(1)]);
    await abrir(tester, tudo.service);

    expect(find.text('INVENTÁRIO DE MATERIAIS'), findsOneWidget);
    expect(find.text('EXPORTAR'), findsOneWidget);
    expect(find.text('NOVO ITEM'), findsOneWidget);
    expect(find.text('Buscar SKU ou nome'), findsOneWidget);
    expect(find.text('CATEGORIA:'), findsOneWidget);
    expect(find.text('SOMENTE ESTOQUE BAIXO'), findsOneWidget);
    expect(find.text('STS'), findsOneWidget);
    expect(find.text('SKU / ID'), findsOneWidget);
    expect(find.text('DESCRIÇÃO'), findsOneWidget);
    expect(find.text('CIM-01'), findsOneWidget);
    expect(find.text('Cimento CP-II'), findsOneWidget);
  });

  testWidgets('a primeira carga pede a pagina inicial', (tester) async {
    final tudo = montar((_) => [item(1)]);
    await abrir(tester, tudo.service);

    expect(tudo.chamadas.single.queryParameters, {
      'limit': '50',
      'offset': '0',
    });
  });

  testWidgets('busca espera a digitacao parar antes de chamar', (tester) async {
    final tudo = montar((_) => [item(1)]);
    await abrir(tester, tudo.service);

    await tester.enterText(find.byType(TextField), 'cim');
    await tester.pump(const Duration(milliseconds: 100));
    expect(tudo.chamadas.length, 1);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(tudo.chamadas.length, 2);
    expect(tudo.chamadas.last.queryParameters['busca'], 'cim');
  });

  testWidgets('somente estoque baixo envia o filtro', (tester) async {
    final tudo = montar((_) => [item(1, baixo: true)]);
    await abrir(tester, tudo.service);

    await tester.tap(find.byType(Checkbox));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(tudo.chamadas.last.queryParameters['baixo'], 'true');
  });

  testWidgets('filtro de categoria usa as categorias carregadas', (
    tester,
  ) async {
    final tudo = montar((_) => [item(1), item(2, categoria: 9, categoriaNome: 'Madeira')]);
    await abrir(tester, tudo.service);

    await tester.tap(find.byType(DropdownButton<int?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Madeira').last);
    await tester.pumpAndSettle();

    expect(tudo.chamadas.last.queryParameters['categoria_id'], '9');
  });

  testWidgets('carregar mais avanca o offset sem perder a pagina', (
    tester,
  ) async {
    final tudo = montar(
      (chamada) => chamada == 1
          ? List.generate(50, (i) => item(i + 1, sku: 'SKU-$i'))
          : [item(999, sku: 'SKU-NOVO')],
    );
    await abrir(tester, tudo.service);

    await tester.ensureVisible(find.text('CARREGAR MAIS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CARREGAR MAIS'));
    await tester.pumpAndSettle();

    expect(tudo.chamadas.last.queryParameters['offset'], '50');
    expect(find.text('SKU-0'), findsOneWidget);
  });

  testWidgets('item abaixo do minimo aparece em vermelho', (tester) async {
    final tudo = montar((_) => [item(1, baixo: true)]);
    await abrir(tester, tudo.service);

    final icone = tester.widget<Icon>(find.byIcon(Icons.warning_rounded).first);
    expect(icone.color, const Color(0xFFBA1A1A));
  });

  testWidgets('lista vazia explica em vez de ficar em branco', (tester) async {
    final tudo = montar((_) => []);
    await abrir(tester, tudo.service);

    expect(find.textContaining('Nenhum material encontrado'), findsOneWidget);
  });

  testWidgets('erro da API aparece com opcao de tentar de novo', (
    tester,
  ) async {
    final api = ApiClient(
      config: ApiConfig('https://api.constroi.test'),
      sessions: SessionManager(MemoryTokenStorage()),
      httpClient: MockClient(
        (_) async => http.Response(jsonEncode({'erro': 'Obra invalida.'}), 400),
      ),
    );
    await abrir(tester, EstoqueService(api: api));

    expect(find.text('Obra invalida.'), findsOneWidget);
    expect(find.text('TENTAR DE NOVO'), findsOneWidget);
  });

  testWidgets('resposta antiga nao sobrescreve o filtro mais recente', (
    tester,
  ) async {
    final tudo = montar(
      (chamada) => [item(chamada, sku: 'SKU-CHAMADA-$chamada')],
    );
    await abrir(tester, tudo.service);

    await tester.enterText(find.byType(TextField), 'a');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ab');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('SKU-CHAMADA-3'), findsOneWidget);
    expect(find.text('SKU-CHAMADA-2'), findsNothing);
  });

  testWidgets('layout aguenta texto ampliado sem estourar', (tester) async {
    final tudo = montar((_) => [item(1, nome: 'Vergalhao CA-50 (12m) nervurado')]);
    tester.view.physicalSize = const Size(390, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: EstoqueScreen(
            service: tudo.service,
            perfil: PerfilUsuario.engenheiro,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('cards vem do painel, nao da pagina carregada', (tester) async {
    final tudo = montarComPainel([item(1)]);
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: EstoqueScreen(
          service: tudo.estoque,
          painel: tudo.painel,
          perfil: PerfilUsuario.master,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1248'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('o painel nao recarrega a cada tecla digitada', (tester) async {
    final tudo = montarComPainel([item(1)]);
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: EstoqueScreen(
          service: tudo.estoque,
          painel: tudo.painel,
          perfil: PerfilUsuario.master,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'cim');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'cimento');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    final painel = tudo.chamadas.where((u) => u.path.endsWith('/painel'));
    expect(painel.length, 1);
  });

  testWidgets('trocar de obra manda o obra_id nas duas consultas', (
    tester,
  ) async {
    final tudo = montarComPainel([item(1)]);
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: EstoqueScreen(
          service: tudo.estoque,
          painel: tudo.painel,
          perfil: PerfilUsuario.master,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<int?>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Obra Beta').last);
    await tester.pumpAndSettle();

    final estoque = tudo.chamadas.where((u) => u.path.endsWith('/estoque'));
    expect(estoque.last.queryParameters['obra_id'], '8');
    final painel = tudo.chamadas.where((u) => u.path.endsWith('/painel'));
    expect(painel.last.queryParameters['obra_id'], '8');
  });

  testWidgets('listando todas as obras a linha diz de qual obra e', (
    tester,
  ) async {
    final tudo = montarComPainel([
      {...item(1), 'obra_id': 8},
    ]);
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: EstoqueScreen(
          service: tudo.estoque,
          painel: tudo.painel,
          perfil: PerfilUsuario.master,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Obra Beta'), findsWidgets);
  });

  testWidgets('a linha mostra o saldo e a unidade', (tester) async {
    final tudo = montar((_) => [item(1)]);
    await abrir(tester, tudo.service);

    expect(find.textContaining('4.50 SC'), findsOneWidget);
  });

  testWidgets('saldo baixo tambem destaca o texto, nao so o icone', (
    tester,
  ) async {
    final tudo = montar((_) => [item(1, baixo: true)]);
    await abrir(tester, tudo.service);

    final texto = tester.widget<Text>(find.textContaining('4.50 SC'));
    expect(texto.style?.color, const Color(0xFFBA1A1A));
  });

  testWidgets('o status tem rotulo para leitor de tela', (tester) async {
    final tudo = montar((_) => [item(1, baixo: true)]);
    await abrir(tester, tudo.service);

    expect(
      find.bySemanticsLabel(RegExp('Abaixo do mínimo')),
      findsOneWidget,
    );
  });

  testWidgets('puxar para atualizar recarrega lista e indicadores', (
    tester,
  ) async {
    final tudo = montarComPainel([item(1)]);
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: EstoqueScreen(
          service: tudo.estoque,
          painel: tudo.painel,
          perfil: PerfilUsuario.master,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final antes = tudo.chamadas.where((u) => u.path.endsWith('/painel')).length;

    await tester.fling(find.byType(ListView), const Offset(0, 320), 1000);
    await tester.pumpAndSettle();

    final depois = tudo.chamadas.where((u) => u.path.endsWith('/painel')).length;
    expect(depois, antes + 1);
  });
}
