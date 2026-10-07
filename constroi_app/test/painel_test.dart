import 'dart:async';
import 'dart:convert';

import 'package:constroi_app/core/api/api_client.dart';
import 'package:constroi_app/core/api/api_config.dart';
import 'package:constroi_app/core/auth/session.dart';
import 'package:constroi_app/core/auth/session_manager.dart';
import 'package:constroi_app/features/painel/painel_model.dart';
import 'package:constroi_app/features/painel/painel_service.dart';
import 'package:constroi_app/main.dart';
import 'package:constroi_app/navigation/perfil_usuario.dart';
import 'package:constroi_app/screens/login_screen.dart';
import 'package:constroi_app/theme/app_theme.dart';
import 'package:constroi_app/widgets/app_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'login_screen_test.dart' show MemoryTokenStorage;

Map<String, dynamic> respostaPainel({
  int total = 17,
  int linhas = 1,
  int inicio = 1,
  bool temMais = false,
  int? obraId,
  bool semObras = false,
  String? valor = '1234.50',
}) => {
  'obras': semObras
      ? []
      : [
          {'id': 10, 'nome': 'Obra de teste'},
          {'id': 11, 'nome': 'Segunda obra'},
        ],
  'obra_id': obraId,
  'atualizado_em': '2026-10-07T12:30:00Z',
  'indicadores': {
    'total_itens': total,
    'rupturas_criticas': 2,
    'requisicoes_pendentes': 3,
    'obras_ativas': 1,
    'valor_estimado': valor,
    'itens_sem_preco': 0,
  },
  'movimentacoes': List.generate(
    linhas,
    (i) => {
      'id': 'ENT-${inicio + i}',
      'produto_nome': 'Cimento ${inicio + i}',
      'obra_nome': 'Obra de teste',
      'acao': 'entrada',
      'quantidade': '12.50',
      'unidade': 'sacos',
      'data': '2026-10-07T10:00:00Z',
    },
  ),
  'paginacao': {'limite': 5, 'offset': inicio - 1, 'tem_mais': temMais},
};

http.Response ok(Map<String, dynamic> dados) => http.Response(
  jsonEncode(dados),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

String tokenPerfil(String tipo) =>
    '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.${base64Url.encode(utf8.encode(jsonEncode({'sub': '7', 'empresa_id': 3, 'tipo': tipo})))}.assinatura';

Future<void> abrirPainel(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) responder, {
  PerfilUsuario perfil = PerfilUsuario.master,
  Size tamanho = const Size(390, 844),
  double escala = 1,
}) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final sessoes = SessionManager(MemoryTokenStorage());
  await sessoes.start(AppSession(accessToken: tokenPerfil(perfil.name)));
  final api = ApiClient(
    config: ApiConfig('https://api.constroi.test'),
    sessions: sessoes,
    httpClient: MockClient(responder),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(escala)),
        child: child!,
      ),
      home: AppHome(
        key: UniqueKey(),
        service: PainelService(api),
        perfil: perfil,
        onSair: sessoes.signOut,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  test('decimais e moeda sao lidos sem converter ausencia em zero', () {
    final dados = PainelDados.fromJson(respostaPainel(valor: null));
    expect(dados.indicadores.valorEstimado, isNull);
    expect(dados.movimentacoes.single.quantidade, 12.5);
    expect(formatarNumero(1234.5, casas: 2), '1.234,50');
    final invalido = respostaPainel();
    (invalido['indicadores'] as Map).remove('total_itens');
    expect(() => PainelDados.fromJson(invalido), throwsFormatException);
  });

  testWidgets('carrega e usa indicadores e entradas reais da resposta', (
    tester,
  ) async {
    final pendente = Completer<http.Response>();
    http.Request? enviada;
    await abrirPainel(tester, (request) {
      enviada = request;
      return pendente.future;
    });
    expect(find.text('Carregando painel...'), findsOneWidget);
    expect(find.text('14.208'), findsNothing);
    pendente.complete(ok(respostaPainel()));
    await tester.pumpAndSettle();
    expect(find.text('VISÃO GERAL\nDO ESTOQUE'), findsOneWidget);
    expect(find.text('17'), findsOneWidget);
    expect(find.text('R\$ 1.234,50'), findsOneWidget);
    expect(find.text('Cimento 1'), findsOneWidget);
    expect(find.text('+12,50'), findsOneWidget);
    expect(enviada!.url.path, '/painel');
    expect(enviada!.headers['Authorization'], startsWith('Bearer '));
  });

  testWidgets('erro e nova tentativa sem expor detalhes internos', (
    tester,
  ) async {
    var chamadas = 0;
    await abrirPainel(
      tester,
      (_) async => ++chamadas == 1
          ? http.Response('{"erro":"postgresql://segredo"}', 503)
          : ok(respostaPainel()),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Não foi possível carregar o painel'),
      findsOneWidget,
    );
    expect(find.textContaining('segredo'), findsNothing);
    await tester.tap(find.text('TENTAR NOVAMENTE'));
    await tester.pumpAndSettle();
    expect(find.text('17'), findsOneWidget);
    expect(chamadas, 2);
  });

  testWidgets('puxar atualiza dados e mantem ultimo resultado se falhar', (
    tester,
  ) async {
    var chamadas = 0;
    await abrirPainel(tester, (_) async {
      chamadas++;
      return chamadas == 3
          ? http.Response('{}', 503)
          : ok(respostaPainel(total: chamadas == 1 ? 17 : 22));
    });
    await tester.pumpAndSettle();
    await tester.fling(
      find.byKey(const ValueKey('painel-scroll')),
      const Offset(0, 450),
      1000,
    );
    await tester.pumpAndSettle();
    expect(chamadas, 2);
    expect(find.text('22'), findsOneWidget);
    await tester.fling(
      find.byKey(const ValueKey('painel-scroll')),
      const Offset(0, 450),
      1000,
    );
    await tester.pumpAndSettle();
    expect(chamadas, 3);
    expect(find.text('22'), findsOneWidget);
    expect(find.textContaining('última consulta'), findsOneWidget);
  });

  testWidgets('filtro de obra envia o id escolhido e troca os indicadores', (
    tester,
  ) async {
    final consultas = <Uri>[];
    await abrirPainel(tester, (request) async {
      consultas.add(request.url);
      final obra = int.tryParse(request.url.queryParameters['obra_id'] ?? '');
      return ok(respostaPainel(total: obra == null ? 17 : 8, obraId: obra));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Segunda obra').last);
    await tester.pumpAndSettle();
    expect(consultas.last.queryParameters['obra_id'], '11');
    expect(find.text('8'), findsOneWidget);
    expect(find.text('17'), findsNothing);
  });

  testWidgets('movimentacoes sao paginadas sem descartar a primeira pagina', (
    tester,
  ) async {
    final offsets = <String?>[];
    await abrirPainel(tester, (request) async {
      final offset = request.url.queryParameters['offset'];
      offsets.add(offset);
      return ok(
        offset == '0'
            ? respostaPainel(linhas: 5, temMais: true)
            : respostaPainel(inicio: 6),
      );
    });
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('CARREGAR MAIS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CARREGAR MAIS'));
    await tester.pumpAndSettle();
    expect(offsets, ['0', '5']);
    expect(find.text('Cimento 1'), findsOneWidget);
    expect(find.text('Cimento 6'), findsOneWidget);
    expect(find.text('CARREGAR MAIS'), findsNothing);
  });

  testWidgets('pedreiro nao ve custos nem equipe e nao ve valor estimado', (
    tester,
  ) async {
    await abrirPainel(
      tester,
      (_) async => ok(respostaPainel()),
      perfil: PerfilUsuario.pedreiro,
    );
    await tester.pumpAndSettle();
    expect(find.text('VALOR ESTIMADO'), findsNothing);
    expect(find.text('Custos'), findsNothing);
    expect(find.text('Equipe'), findsNothing);
    expect(find.text('Estoque'), findsOneWidget);
    expect(find.text('Requisições'), findsOneWidget);
  });

  testWidgets('lista vazia, obras ausentes e precos ausentes sao explicados', (
    tester,
  ) async {
    await abrirPainel(
      tester,
      (_) async => ok(respostaPainel(linhas: 0, valor: null)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Não informado'), findsOneWidget);
    expect(find.textContaining('Nenhuma movimentação'), findsOneWidget);
    await abrirPainel(
      tester,
      (_) async => ok(respostaPainel(semObras: true)),
      perfil: PerfilUsuario.engenheiro,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('ainda não tem obras'), findsOneWidget);
  });

  testWidgets('resposta antiga nao sobrescreve o filtro mais recente', (
    tester,
  ) async {
    var chamadas = 0;
    final antiga = Completer<http.Response>();
    await abrirPainel(tester, (request) async {
      chamadas++;
      if (chamadas == 2) return antiga.future;
      return ok(
        respostaPainel(
          total: chamadas == 1 ? 17 : 8,
          obraId: chamadas == 1 ? null : 11,
        ),
      );
    });
    await tester.pumpAndSettle();
    final atualizacao = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pump();
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Segunda obra').last);
    await tester.pumpAndSettle();
    expect(find.text('8'), findsOneWidget);
    antiga.complete(ok(respostaPainel(total: 99)));
    await atualizacao;
    await tester.pumpAndSettle();
    expect(find.text('8'), findsOneWidget);
    expect(find.text('99'), findsNothing);
  });

  testWidgets('filtro que falha pode ser limpo sem reiniciar o app', (
    tester,
  ) async {
    await abrirPainel(
      tester,
      (request) async => request.url.queryParameters.containsKey('obra_id')
          ? http.Response('{}', 404)
          : ok(respostaPainel()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Segunda obra').last);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Não foi possível carregar o painel'),
      findsOneWidget,
    );
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Todas as obras disponíveis').last);
    await tester.pumpAndSettle();
    expect(find.text('17'), findsOneWidget);
  });

  testWidgets('401 no painel apaga token e mostra login', (tester) async {
    final cofre = MemoryTokenStorage()..token = tokenPerfil('master');
    await tester.pumpWidget(
      ConstroiApp(
        config: ApiConfig('https://api.constroi.test'),
        storage: cofre,
        httpClient: MockClient(
          (request) async => request.url.path == '/eu'
              ? ok({
                  'id': 7,
                  'empresa_id': 3,
                  'tipo': 'master',
                  'nome': 'Operador',
                })
              : http.Response('{}', 401),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(cofre.token, isNull);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(AppHome), findsNothing);
  });

  for (final tamanho in [
    const Size(320, 640),
    const Size(844, 390),
    const Size(1280, 800),
  ]) {
    testWidgets('layout sem overflow em $tamanho e texto ampliado', (
      tester,
    ) async {
      await abrirPainel(
        tester,
        (_) async => ok(respostaPainel()),
        tamanho: tamanho,
        escala: 1.4,
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('painel-scroll')),
        const Offset(0, -1600),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
