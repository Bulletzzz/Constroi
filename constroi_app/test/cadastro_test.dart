import 'dart:convert';

import 'package:constroi_app/core/api/api_client.dart';
import 'package:constroi_app/core/api/api_config.dart';
import 'package:constroi_app/core/auth/session_manager.dart';
import 'package:constroi_app/features/cadastro/cadastro_screen.dart';
import 'package:constroi_app/features/cadastro/cadastro_service.dart';
import 'package:constroi_app/navigation/perfil_usuario.dart';
import 'package:constroi_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'login_screen_test.dart' show MemoryTokenStorage;

final categorias = {
  'categorias': [
    {'id': 2, 'nome': 'Cimento e agregados'},
    {'id': 1, 'nome': 'Aço e vergalhão'},
  ],
};

http.Response ok(Object corpo) =>
    http.Response(jsonEncode(corpo), 200, headers: {
      'content-type': 'application/json',
    });

http.Response criado(Object corpo) =>
    http.Response(jsonEncode(corpo), 201, headers: {
      'content-type': 'application/json',
    });

http.Response falha(int status, String erro) =>
    http.Response(jsonEncode({'erro': erro}), status, headers: {
      'content-type': 'application/json',
    });

({CadastroService service, List<http.Request> chamadas}) montar(
  Future<http.Response> Function(http.Request) responder,
) {
  final chamadas = <http.Request>[];
  final service = CadastroService(
    api: ApiClient(
      config: ApiConfig('https://api.constroi.test'),
      sessions: SessionManager(MemoryTokenStorage()),
      httpClient: MockClient((r) {
        chamadas.add(r);
        return responder(r);
      }),
    ),
  );
  return (service: service, chamadas: chamadas);
}

Future<http.Response> padrao(http.Request r) async {
  if (r.url.path.endsWith('/categorias')) return ok(categorias);
  if (r.url.path.endsWith('/produtos')) {
    return criado({'id': 10, 'nome': 'Cimento CP-II'});
  }
  return criado({'id': 20, 'nome': 'Betoneira 400L'});
}

Future<void> abrir(
  WidgetTester tester,
  CadastroService service, {
  double escala = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(escala),
        ),
        child: child!,
      ),
      home: CadastroScreen(
        service: service,
        perfil: PerfilUsuario.engenheiro,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder campoDe(String identificador) => find.descendant(
  of: find.bySemanticsIdentifier(identificador),
  matching: find.byType(TextFormField),
);

Future<void> tocar(WidgetTester tester, String identificador) async {
  final alvo = find.bySemanticsIdentifier(identificador);
  await tester.ensureVisible(alvo);
  await tester.pumpAndSettle();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Future<void> escrever(
  WidgetTester tester,
  String identificador,
  String texto,
) async {
  final alvo = campoDe(identificador);
  await tester.ensureVisible(alvo);
  await tester.pumpAndSettle();
  await tester.enterText(alvo, texto);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('abre em produto e troca para equipamento', (tester) async {
    await abrir(tester, montar(padrao).service);

    expect(find.bySemanticsIdentifier('cadastro-unidade'), findsOneWidget);
    expect(find.bySemanticsIdentifier('cadastro-status'), findsNothing);

    await tocar(tester, 'cadastro-tipo-equipamento');

    expect(find.bySemanticsIdentifier('cadastro-status'), findsOneWidget);
    expect(find.bySemanticsIdentifier('cadastro-unidade'), findsNothing);
    expect(find.bySemanticsIdentifier('cadastro-minimo'), findsNothing);
  });

  testWidgets('nao envia produto sem nome', (tester) async {
    final tudo = montar(padrao);
    await abrir(tester, tudo.service);
    tudo.chamadas.clear();

    await tocar(tester, 'cadastro-salvar');

    expect(find.text('Informe o nome do item.'), findsOneWidget);
    expect(tudo.chamadas, isEmpty);
  });

  testWidgets('equipamento exige patrimonio, produto nao', (tester) async {
    final tudo = montar(padrao);
    await abrir(tester, tudo.service);

    await escrever(tester, 'cadastro-nome', 'Betoneira 400L');
    await tocar(tester, 'cadastro-tipo-equipamento');
    await escrever(tester, 'cadastro-nome', 'Betoneira 400L');
    tudo.chamadas.clear();

    await tocar(tester, 'cadastro-salvar');

    expect(
      find.text('O patrimônio é obrigatório no equipamento.'),
      findsOneWidget,
    );
    expect(tudo.chamadas, isEmpty);
  });

  testWidgets('envia o produto com unidade e categoria escolhidas', (
    tester,
  ) async {
    final tudo = montar(padrao);
    await abrir(tester, tudo.service);

    await escrever(tester, 'cadastro-nome', 'Cimento CP-II');
    await escrever(tester, 'cadastro-minimo', '12,5');
    tudo.chamadas.clear();

    await tocar(tester, 'cadastro-salvar');

    final enviada = tudo.chamadas.last;
    final corpo =
        jsonDecode(enviada.body) as Map<String, dynamic>;
    final produto = corpo['produto'] as Map<String, dynamic>;
    expect(enviada.url.path, endsWith('/produtos'));
    expect(produto['nome'], 'Cimento CP-II');
    expect(produto['unidade'], 'un');
    expect(produto['estoque_minimo'], '12.5');
  });

  testWidgets('gerar preenche o codigo a partir do nome', (tester) async {
    await abrir(tester, montar(padrao).service);

    await escrever(tester, 'cadastro-nome', 'Cimento Portland');
    await tocar(tester, 'cadastro-gerar-codigo');

    final campo = tester.widget<TextFormField>(campoDe('cadastro-codigo'));
    expect(campo.controller!.text, startsWith('CIM-POR-'));
  });

  testWidgets('erro da API aparece na tela', (tester) async {
    final tudo = montar((r) async {
      if (r.url.path.endsWith('/categorias')) return ok(categorias);
      return falha(409, 'Produto ja cadastrado para esta empresa.');
    });
    await abrir(tester, tudo.service);

    await escrever(tester, 'cadastro-nome', 'Cimento CP-II');
    await tocar(tester, 'cadastro-salvar');

    expect(find.bySemanticsIdentifier('cadastro-erro'), findsOneWidget);
    expect(
      find.text('Produto ja cadastrado para esta empresa.'),
      findsOneWidget,
    );
  });

  testWidgets('categoria indisponivel nao impede o cadastro', (tester) async {
    final tudo = montar((r) async {
      if (r.url.path.endsWith('/categorias')) {
        return falha(503, 'Servico indisponivel.');
      }
      return criado({'id': 10, 'nome': 'Cimento CP-II'});
    });
    await abrir(tester, tudo.service);

    expect(find.bySemanticsIdentifier('cadastro-categoria'), findsOneWidget);
    expect(find.bySemanticsIdentifier('cadastro-erro'), findsNothing);
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

      await abrir(tester, montar(padrao).service, escala: 1.4);
      await tester.drag(find.byType(ListView), const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tocar(tester, 'cadastro-tipo-equipamento');
      await tester.drag(find.byType(ListView), const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
